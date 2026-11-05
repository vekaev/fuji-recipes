import Foundation
import ImageIO

/// In-camera RAW development, as FUJIFILM X RAW Studio does it: upload one RAF, then for each recipe patch the
/// conversion profile (0xD185), trigger (0xD183), wait for the new object, fetch it and delete it from the camera.
/// Protocol and layout from docs/research/raw-rendering.md (FilmKit, libfuji, rawji, grawji, zgrimz; facts only).
/// The camera must be in USB RAW CONV./BACKUP RESTORE mode and the RAF must come from the same model.
public enum RenderOp {
    public static let sendObjectInfo2: UInt16 = 0x900C   // Fuji vendor SendObjectInfo for the RAF
    public static let sendObject2: UInt16 = 0x900D
    public static let getObjectHandles: UInt16 = 0x1007
    public static let getObjectInfo: UInt16 = 0x1008
    public static let getObject: UInt16 = 0x1009
    public static let getThumb: UInt16 = 0x100A
    public static let deleteObject: UInt16 = 0x100B
    public static let profile: UInt16 = 0xD185
    public static let trigger: UInt16 = 0xD183
}

/// The conversion profile: u16 count, an IOP code, then i32 cells at 0x1FD + 4·i (an odd, unaligned base).
public struct ConversionProfile: Equatable, Sendable {
    public static let base = 0x1FD
    public var data: Data

    public init(_ data: Data) { self.data = data }

    public var cellCount: Int { max(0, (data.count - Self.base) / 4) }

    public subscript(_ i: Int) -> Int32 {
        get {
            let o = Self.base + 4 * i
            guard i >= 0, o + 4 <= data.count else { return 0 }
            let b = [UInt8](data[data.startIndex + o ..< data.startIndex + o + 4])
            return Int32(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)
        }
        set {
            let o = Self.base + 4 * i
            guard i >= 0, o + 4 <= data.count else { return }
            let u = UInt32(bitPattern: newValue)
            for k in 0..<4 { data[data.startIndex + o + k] = UInt8((u >> (8 * UInt32(k))) & 0xFF) }
        }
    }

    /// The cells line up when DR (cell 6) is 100/200/400 and the film simulation (cell 8) is a known one.
    public var isValid: Bool { cellCount >= 28 && [100, 200, 400].contains(self[6]) && (1...20).contains(Int(self[8])) }

    /// The as-shot dynamic range of the uploaded RAF: a recipe may not go above it (a higher DR renders green).
    public var asShotDR: Int { Int(self[6]) }

    public enum Cell {
        public static let exposure = 5, dynamicRange = 6, dRangePriority = 7, film = 8, grain = 9, colorChrome = 10
        public static let wbSource = 11, wbMode = 12, wbRed = 13, wbBlue = 14, kelvin = 15
        public static let highlight = 16, shadow = 17, color = 18, sharpness = 19, highIsoNr = 20
        public static let monoWarmCool = 23, fxBlue = 25, monoMagentaGreen = 26, clarity = 27
    }

    /// A copy of this (as-read) profile with `recipe` applied. Returns what couldn't be applied faithfully.
    /// `exposure` is EV (from the recipe's shooting advice or a slider); nil keeps the as-shot value.
    public func applying(_ recipe: RecipeSettings, exposure: Double? = nil) -> (profile: ConversionProfile, notes: [String]) {
        var p = self
        var notes: [String] = []
        let v = BankCodec.encode(recipe)
        func signed(_ x: UInt16) -> Int32 { Int32(Int16(bitPattern: x)) }
        if let f = v[.film] { p[Cell.film] = Int32(f) }
        if let g = v[.grain] { p[Cell.grain] = Int32(g) }
        if let c = v[.colorChrome] { p[Cell.colorChrome] = Int32(c) }
        if let c = v[.colorChromeFxBlue] { p[Cell.fxBlue] = Int32(c) }
        if let dr = v[.dynamicRange] {
            let want = dr == 0xFFFF ? asShotDR : Int(dr)
            if want > asShotDR { notes.append("DR\(want) above this photo's DR\(asShotDR): rendered at DR\(asShotDR)") }
            p[Cell.dynamicRange] = Int32(min(want, asShotDR))
        }
        if recipe.dRangePriority != "Off" { notes.append("D-Range Priority can't be rendered yet: rendered without it") }
        if let w = v[.wbMode] { p[Cell.wbSource] = 2; p[Cell.wbMode] = Int32(w) }
        if let r = v[.wbRed] { p[Cell.wbRed] = signed(r) }
        if let b = v[.wbBlue] { p[Cell.wbBlue] = signed(b) }
        if let k = v[.kelvin] { p[Cell.kelvin] = Int32(k) }
        if let h = v[.highlight] { p[Cell.highlight] = signed(h) }
        if let s = v[.shadow] { p[Cell.shadow] = signed(s) }
        if let c = v[.color] { p[Cell.color] = signed(c) }
        if let s = v[.sharpness] { p[Cell.sharpness] = signed(s) }
        if let n = v[.highIsoNr] { p[Cell.highIsoNr] = Int32(n) }
        if let m = v[.monoWarmCool] { p[Cell.monoWarmCool] = signed(m) }
        if let m = v[.monoMagentaGreen] { p[Cell.monoMagentaGreen] = signed(m) }
        if let c = v[.clarity] { p[Cell.clarity] = signed(c) }
        if let ev = exposure { p[Cell.exposure] = Int32((ev * 1000).rounded()) }
        return (p, notes)
    }
}

/// One render: the JPEG, and what the camera couldn't do exactly.
public struct Render: Sendable {
    public var jpeg: Data
    public var notes: [String]
    public var seconds: Double
}

extension FujiCamera {
    /// Sends a RAF to the camera's conversion buffer and returns the as-read profile (the RAF's as-shot settings).
    /// A RAF from another model fails here: the camera answers 0x2002 when the profile is read.
    public func uploadRAF(_ raf: Data) async throws -> ConversionProfile {
        guard raf.count > 1000, raf.prefix(15) == Data("FUJIFILMCCD-RAW".utf8) else { throw CameraError("That isn't a Fujifilm RAW (.RAF) file.") }
        let mode = try await usbMode()
        guard mode.canWriteSlots else { throw CameraError("The camera is in \(mode.label). \(USBMode.howToSet)") }
        let r1 = try await transport.send(RenderOp.sendObjectInfo2, [0, 0, 0], data: Self.objectInfo(size: raf.count, name: "FUP_FILE.dat", format: 0xF802))
        guard r1.ok else { throw CameraError("Sending the RAW's info: \(PTPCode.describe(r1.code))") }
        let r2 = try await transport.send(RenderOp.sendObject2, [], data: raf)
        guard r2.ok else { throw CameraError("Sending the RAW: \(PTPCode.describe(r2.code))") }
        return try await readProfile()
    }

    public func readProfile() async throws -> ConversionProfile {
        let r = try await transport.send(PTPOp.getDevicePropValue, [UInt32(RenderOp.profile)], data: nil)
        guard r.ok else {
            throw CameraError(r.code == PTPCode.generalError ? "The camera can't develop this RAW: it must come from the same camera model."
                                                            : "Reading the conversion profile: \(PTPCode.describe(r.code))")
        }
        let p = ConversionProfile(r.data)
        guard p.isValid else { throw CameraError("The conversion profile doesn't look like one this app knows (\(r.data.count) bytes); not rendering.") }
        return p
    }

    /// Renders the uploaded RAF with `recipe`, starting from `base` (the profile `uploadRAF` returned, every time).
    /// `full` renders full resolution and downloads it (~25 MB); otherwise a reduced render's 640-px thumbnail.
    /// Never triggers again after a timeout: a stuck camera answers "busy" until it's switched off and on.
    public func render(_ recipe: RecipeSettings, base: ConversionProfile, exposure: Double? = nil, full: Bool = false,
                       timeout: Double = 30) async throws -> Render {
        let start = Date()
        let (profile, notes) = base.applying(recipe, exposure: exposure)
        let w = try await transport.send(PTPOp.setDevicePropValue, [UInt32(RenderOp.profile)], data: profile.data)
        guard w.ok else { throw CameraError("Setting the recipe for the render: \(PTPCode.describe(w.code))") }
        let check = try await readProfile()
        for c in [ConversionProfile.Cell.film, ConversionProfile.Cell.dynamicRange, ConversionProfile.Cell.color, ConversionProfile.Cell.grain]
        where check[c] != profile[c] {
            throw CameraError("The camera didn't take the recipe for the render (cell \(c): wanted \(profile[c]), has \(check[c])).")
        }
        let before = Set(try await handles())
        let t = try await transport.send(PTPOp.setDevicePropValue, [UInt32(RenderOp.trigger)], data: Data([full ? 1 : 0, 0]))
        guard t.ok else { throw CameraError("Starting the render: \(PTPCode.describe(t.code))") }
        var made: UInt32?
        while made == nil {
            if Date().timeIntervalSince(start) > timeout {
                throw CameraError("The camera didn't finish the render in \(Int(timeout)) s. Switch it off and on before trying again.")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            made = try await handles().first { !before.contains($0) }
        }
        let object = made!
        let get = try await transport.send(full ? RenderOp.getObject : RenderOp.getThumb, [object], data: nil)
        _ = try? await transport.send(RenderOp.deleteObject, [object], data: nil)   // only the object this job made
        guard get.ok, get.data.count > 100 else { throw CameraError("Fetching the render: \(PTPCode.describe(get.code))") }
        return Render(jpeg: get.data, notes: notes, seconds: Date().timeIntervalSince(start))
    }

    private func handles() async throws -> [UInt32] {
        let r = try await transport.send(RenderOp.getObjectHandles, [0xFFFF_FFFF, 0, 0], data: nil)
        guard r.ok, r.data.count >= 4 else { return [] }
        let b = [UInt8](r.data)
        let n = Int(UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)
        return (0..<min(n, (b.count - 4) / 4)).map { i in
            let o = 4 + 4 * i
            return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
        }
    }

    /// A standard PTP ObjectInfo dataset with only storage, format, size and the filename set.
    static func objectInfo(size: Int, name: String, format: UInt16) -> Data {
        var d = Data()
        func w16(_ v: UInt16) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8)) }
        func w32(_ v: UInt32) { w16(UInt16(v & 0xFFFF)); w16(UInt16(v >> 16)) }
        w32(0); w16(format); w16(0); w32(UInt32(size))
        w16(0); w32(0); w32(0); w32(0); w32(0); w32(0); w32(0)   // thumb format/size/w/h, image w/h/depth
        w32(0); w16(0); w32(0); w32(0)                          // parent, association type/desc, sequence
        d.append(PTPString.encode(name))
        d.append(contentsOf: [0, 0, 0])                         // capture date, modification date, keywords: empty
        return d
    }
}

/// Renders kept on disk: `renders/<raw key>/<recipe settings key>[-full].jpg` in the library, so a contact sheet opens
/// instantly, works without the camera, and syncs with the library. The raw key comes from the file's size and its
/// first 64 KB; the recipe key from its settings (a renamed recipe keeps its renders).
public struct RenderCache: Sendable {
    public let root: URL
    public init(library: Library) { root = library.root.appendingPathComponent("renders") }
    public init(root: URL) { self.root = root }

    public static func rawKey(_ raw: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: raw.path)[.size] as? NSNumber)?.int64Value ?? 0
        let head = (try? FileHandle(forReadingFrom: raw).read(upToCount: 65_536)) ?? Data()
        return fnv(head + Data(String(size).utf8))
    }

    public static func recipeKey(_ s: RecipeSettings, exposure: Double? = nil) -> String {
        var n = s; n.normalize()
        return fnv(((try? Library.encoder.encode(n)) ?? Data()) + Data("\(exposure ?? 0)".utf8))
    }

    public func url(raw: URL, settings: RecipeSettings, exposure: Double? = nil, full: Bool = false) -> URL {
        root.appendingPathComponent(Self.rawKey(raw)).appendingPathComponent(Self.recipeKey(settings, exposure: exposure) + (full ? "-full" : "") + ".jpg")
    }

    public func cached(raw: URL, settings: RecipeSettings, exposure: Double? = nil, full: Bool = false) -> URL? {
        let u = url(raw: raw, settings: settings, exposure: exposure, full: full)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        upright(rawFolder: u.deletingLastPathComponent(), raw: raw)
        return u
    }

    @discardableResult
    public func store(_ jpeg: Data, raw: URL, settings: RecipeSettings, exposure: Double? = nil, full: Bool = false) throws -> URL {
        let u = url(raw: raw, settings: settings, exposure: exposure, full: full)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tagged(jpeg, orientation: Self.orientation(raw)).write(to: u, options: .atomic)
        return u
    }

    // MARK: Orientation
    // The camera develops in sensor orientation and its JPEG carries no Orientation tag, so a vertical shot came back
    // sideways. Every render gets the RAW's own EXIF orientation (metadata only, the pixels aren't re-encoded); renders
    // cached before this are tagged the first time their RAW's folder is read.

    nonisolated(unsafe) private static var orientations: [String: Int] = [:]
    nonisolated(unsafe) private static var uprighted: Set<String> = []
    private static let lock = NSLock()

    /// The RAW's EXIF orientation, 1 = upright (read once per file).
    public static func orientation(_ raw: URL) -> Int {
        lock.lock(); if let o = orientations[raw.path] { lock.unlock(); return o }; lock.unlock()
        var o = 1
        if let src = CGImageSourceCreateWithURL(raw as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            o = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        }
        lock.lock(); orientations[raw.path] = o; lock.unlock()
        return o
    }

    /// The JPEG with its Orientation tag set (unchanged when it's already right).
    public static func tagged(_ jpeg: Data, orientation o: Int) -> Data {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil), let type = CGImageSourceGetType(src) else { return jpeg }
        let now = ((CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard now != o else { return jpeg }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, type, 1, nil) else { return jpeg }
        let meta: [CFString: Any] = [kCGImageDestinationOrientation: o]
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dst, src, meta as CFDictionary, &err) else { return jpeg }
        return out as Data
    }

    /// Tags every render of one RAW that predates the orientation fix (once per RAW and run).
    private func upright(rawFolder: URL, raw: URL) {
        Self.lock.lock()
        let first = Self.uprighted.insert(rawFolder.path).inserted
        Self.lock.unlock()
        guard first else { return }
        let o = Self.orientation(raw)
        guard o != 1, let files = try? FileManager.default.contentsOfDirectory(at: rawFolder, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "jpg" {
            guard let d = try? Data(contentsOf: f) else { continue }
            let t = Self.tagged(d, orientation: o)
            if t != d { try? t.write(to: f, options: .atomic) }
        }
    }

    static func fnv(_ d: Data) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in d { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }
}
