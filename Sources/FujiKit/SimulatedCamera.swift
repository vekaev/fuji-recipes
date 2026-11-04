import Foundation
import ImageIO
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A stand-in X-E5 for tests and demos (`fuji --simulate …`, `FUJI_SIMULATE=1`). It keeps 7 banks in memory and
/// behaves like the documented bodies: the selector refuses C8, grain Off reads back as 6/7, mono toning is refused on
/// colour films and colour on mono films, DR and tone are refused while D-Range Priority is on, Kelvin only in
/// Kelvin mode, unknown codes are refused.
public final class SimulatedCamera: PTPTransport, @unchecked Sendable {
    public let displayName: String
    public let banks: Int
    private let lock = NSLock()
    private var selector: UInt16 = 1
    private var store: [Int: [UInt16: UInt16]] = [:]
    private var names: [Int: String] = [:]
    public private(set) var log: [String] = []
    public var usbMode: UInt16? = 6
    /// The ISO each custom slot remembers (not readable over USB). DR200 needs ≥ 320, DR400 ≥ 640, as on the X-E5.
    public var bankISO: [Int: Int] = [:]
    /// The camera's settings file (object 0) with FS1–FS3, its additive checksum, and the session rule.
    public private(set) var settingsFile: Data
    private var downloadedThisSession = false
    private var pendingRestore: Int?
    /// RAW development: the uploaded RAF, the conversion profile, finished renders.
    private var raf: Data?
    private var profile: Data?
    private var objects: [UInt32: Data] = [:]
    private var nextHandle: UInt32 = 0x1000
    public var asShotDR = 200
    public private(set) var renders = 0

    public init(model: String = "X-E5", banks: Int = 7, seed: [Int: (String, RecipeSettings)] = SimulatedCamera.defaultSeed) {
        displayName = model
        self.banks = banks
        for k in 1...banks {
            let (name, s) = seed[k] ?? ("", RecipeSettings())
            var raw = BankCodec.encode(s).reduce(into: [UInt16: UInt16]()) { $0[$1.key.rawValue] = $1.value }
            // What a real bank also holds: both mono and colour values, DR and tone, image size and quality.
            raw[BankProp.imageSize.rawValue] = 7; raw[BankProp.imageQuality.rawValue] = 2
            raw[BankProp.smoothSkin.rawValue] = 1; raw[BankProp.lensModulation.rawValue] = 1; raw[BankProp.colorSpace.rawValue] = 1
            for p in [BankProp.monoWarmCool, .monoMagentaGreen, .color, .highlight, .shadow] where raw[p.rawValue] == nil { raw[p.rawValue] = 0 }
            if raw[BankProp.dynamicRange.rawValue] == nil { raw[BankProp.dynamicRange.rawValue] = 100 }
            if raw[BankProp.kelvin.rawValue] == nil { raw[BankProp.kelvin.rawValue] = 5500 }
            if raw[BankProp.grain.rawValue] == 1 { raw[BankProp.grain.rawValue] = 6 }
            store[k] = raw
            names[k] = name
            bankISO[k] = 200
        }
        settingsFile = SimulatedCamera.makeSettingsFile(model: model)
    }

    /// An X-E5-sized settings file: header, model, FS1–FS3 (Classic Neg., Acros+Ye, Classic Chrome) and a checksum.
    static func makeSettingsFile(model: String) -> Data {
        var d = Data("FUJIFILM".utf8) + Data(count: SettingsFile.xe5.size - 8)
        let m = Data(model.utf8); d.replaceSubrange(0x14..<(0x14 + m.count), with: m)
        for (_, f) in SettingsFile.xe5.fields { for i in 0..<3 { d[f.offset + i * f.step] = 4 } }
        for (i, film) in ["Classic Neg.", "Acros+Ye", "Classic Chrome"].enumerated() {
            var r = RecipeSettings(); r.film = film; r.normalize()
            if let (out, _) = try? SettingsFile.patch(d, slot: i, settings: r, model: model) { d = out }
        }
        return sealed(d)
    }

    /// The simulator's checksum: the byte sum outside 0x120…0x121 (additive, like the X-E5's: a patch moves it by the
    /// byte delta).
    static func checksum(_ d: Data) -> Int {
        var sum = 0
        for (i, b) in d.enumerated() where i != 0x120 && i != 0x121 { sum += Int(b) }
        return sum & 0xFFFF
    }
    static func sealed(_ d: Data) -> Data {
        var d = d; let c = checksum(d); d[0x120] = UInt8(c & 0xFF); d[0x121] = UInt8(c >> 8); return d
    }

    /// The owner's two recipes (from their X-E5 EXIF) in C1/C2, the rest at defaults.
    public static var defaultSeed: [Int: (String, RecipeSettings)] {
        var acros = RecipeSettings(); acros.film = "Acros+G"; acros.highIsoNr = -4; acros.normalize()
        var neg = RecipeSettings(); neg.film = "Classic Neg."; neg.grainRoughness = "Strong"; neg.grainSize = "Large"
        neg.colorChrome = "Strong"; neg.colorChromeFxBlue = "Strong"; neg.wbRed = 1; neg.wbBlue = -3; neg.highlight = -2
        neg.shadow = -1; neg.color = 1; neg.sharpness = -2; neg.highIsoNr = -4; neg.normalize()
        return [1: ("GREEN ACROS", acros), 2: ("CLASSIC NEG", neg)]
    }

    public func send(_ op: UInt16, _ params: [UInt32], data: Data?) async throws -> PTPResult {
        lock.withLock { handle(op, params, data) }
    }

    public func resetSession() async { lock.withLock { downloadedThisSession = false } }

    private func handle(_ op: UInt16, _ params: [UInt32], _ data: Data?) -> PTPResult {
        let code = params.first.map { UInt16(truncatingIfNeeded: $0) } ?? 0
        switch op {
        case PTPOp.getDeviceInfo:
            return PTPResult(code: PTPCode.ok, data: deviceInfo())
        case PTPOp.getDevicePropValue:
            if code == 0xD16E { return usbMode.map { PTPResult(code: PTPCode.ok, data: u16($0)) } ?? PTPResult(code: PTPCode.notSupported) }
            guard usbMode == 6 || usbMode == 5 else { return PTPResult(code: PTPCode.notSupported) }
            if code == BankProp.selector.rawValue { return PTPResult(code: PTPCode.ok, data: u16(selector)) }
            if code == BankProp.name.rawValue { return PTPResult(code: PTPCode.ok, data: PTPString.encode(names[Int(selector)] ?? "")) }
            if code == RenderOp.profile { return profile.map { PTPResult(code: PTPCode.ok, data: $0) } ?? PTPResult(code: PTPCode.generalError) }
            guard let v = store[Int(selector)]?[code] else { return PTPResult(code: PTPCode.notSupported) }
            return PTPResult(code: PTPCode.ok, data: u16(v))
        case PTPOp.setDevicePropValue where code == RenderOp.profile:
            guard raf != nil, let d = data, d.count == profile?.count else { return PTPResult(code: PTPCode.generalError) }
            profile = d; return PTPResult(code: PTPCode.ok)
        case PTPOp.setDevicePropValue where code == RenderOp.trigger:
            guard raf != nil, let p = profile else { return PTPResult(code: PTPCode.generalError) }
            let full = (data?.first ?? 0) == 1
            nextHandle += 1; objects[nextHandle] = SimulatedCamera.renderJPEG(ConversionProfile(p), full: full); renders += 1
            return PTPResult(code: PTPCode.ok)
        case 0x900C:
            guard usbMode == 6 else { return PTPResult(code: PTPCode.accessDenied) }
            return PTPResult(code: PTPCode.ok)
        case 0x900D:
            raf = data
            // The camera reads the RAF's own settings into the profile; another model's RAF can't be developed.
            if let d = data, String(decoding: d.prefix(0x100), as: UTF8.self).contains(displayName) {
                var p = Data(count: ConversionProfile.base + 4 * 29); p[0] = 29
                var cp = ConversionProfile(p); cp[6] = Int32(asShotDR); cp[8] = 1; cp[9] = 1; cp[10] = 1; cp[11] = 1; cp[12] = 2
                profile = cp.data
            } else { profile = nil }
            return PTPResult(code: PTPCode.ok)
        case RenderOp.getObjectHandles:
            var d = Data(); func w32(_ v: UInt32) { for k in 0..<4 { d.append(UInt8((v >> (8 * UInt32(k))) & 0xFF)) } }
            w32(UInt32(objects.count)); objects.keys.sorted().forEach(w32)
            return PTPResult(code: PTPCode.ok, data: d)
        case RenderOp.getThumb, RenderOp.getObject where params.first != 0:
            guard let o = objects[params.first ?? 0] else { return PTPResult(code: PTPCode.generalError) }
            return PTPResult(code: PTPCode.ok, data: o)
        case RenderOp.deleteObject:
            return PTPResult(code: objects.removeValue(forKey: params.first ?? 0) == nil ? PTPCode.generalError : PTPCode.ok)
        case RenderOp.getObjectInfo:
            guard params.first == 0 else { return PTPResult(code: PTPCode.ok, data: Data(count: 114)) }
            return PTPResult(code: PTPCode.ok, data: Data(count: 64))
        case RenderOp.getObject:   // object 0: the settings file
            downloadedThisSession = true
            return PTPResult(code: PTPCode.ok, data: settingsFile)
        case 0x100C:
            guard usbMode == 6 else { return PTPResult(code: PTPCode.accessDenied) }
            let b = [UInt8](data ?? Data())
            guard b.count >= 12, b[4] == 0x00, b[5] == 0x50 else { return PTPResult(code: PTPCode.invalidValue) }
            pendingRestore = Int(b[8]) | Int(b[9]) << 8 | Int(b[10]) << 16 | Int(b[11]) << 24
            return PTPResult(code: PTPCode.ok)
        case 0x100D:
            // The X-E5 refuses a restore in a session that downloaded the file, and a wrong checksum or size.
            guard !downloadedThisSession, let d = data, d.count == pendingRestore, d.count == settingsFile.count,
                  d.prefix(8) == Data("FUJIFILM".utf8),
                  SimulatedCamera.checksum(d) == (Int(d[0x120]) | Int(d[0x121]) << 8) else { return PTPResult(code: PTPCode.accessDenied) }
            var f = d; f.replaceSubrange(5956..<5961, with: Data("_FUJI".utf8))   // the camera's own bookkeeping
            settingsFile = SimulatedCamera.sealed(f)
            pendingRestore = nil
            log.append("settings file restored")
            return PTPResult(code: PTPCode.ok)
        case PTPOp.setDevicePropValue:
            guard usbMode == 6 || usbMode == 5 else { return PTPResult(code: PTPCode.notSupported) }
            let r = set(code, data ?? Data())
            log.append(String(format: "set 0x%04X → %@", code, PTPCode.describe(r)))
            return PTPResult(code: r)
        default:
            return PTPResult(code: PTPCode.notSupported)
        }
    }

    private func set(_ code: UInt16, _ data: Data) -> UInt16 {
        if code == BankProp.name.rawValue { names[Int(selector)] = PTPString.decode(data); return PTPCode.ok }
        guard data.count >= 2 else { return PTPCode.invalidValue }
        let v = UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8
        if code == BankProp.selector.rawValue {
            guard (1...banks).contains(Int(v)) else { return PTPCode.notSupported }
            selector = v; return PTPCode.ok
        }
        guard var bank = store[Int(selector)], bank[code] != nil, let p = BankProp(rawValue: code) else { return PTPCode.notSupported }
        let film = Int(bank[BankProp.film.rawValue] ?? 1)
        let mono = Film.isMonochrome(Film.all[max(0, min(Film.all.count - 1, film - 1))])
        let drpOn = (bank[BankProp.dRangePriority.rawValue] ?? 0) != 0
        switch p {
        case .film: guard (1...20).contains(Int(v)) else { return PTPCode.invalidValue }
        case .grain:
            guard (1...5).contains(Int(v)) else { return PTPCode.invalidValue }
            if v == 1 { let large = [4, 5, 7].contains(Int(bank[code] ?? 6)); bank[code] = large ? 7 : 6; store[Int(selector)] = bank; return PTPCode.ok }
        case .monoWarmCool, .monoMagentaGreen: guard mono else { return PTPCode.invalidValue }
        case .color: guard !mono else { return PTPCode.invalidValue }
        case .dynamicRange:
            guard !drpOn else { return PTPCode.invalidValue }
            let iso = bankISO[Int(selector)] ?? 200
            if (v == 400 && iso < 640) || (v == 200 && iso < 320) { return PTPCode.invalidValue }
        case .highlight, .shadow: guard !drpOn else { return PTPCode.invalidValue }
        case .kelvin: guard bank[BankProp.wbMode.rawValue] == 0x8007, (2500...10000).contains(Int(v)) else { return PTPCode.invalidValue }
        case .wbRed, .wbBlue: guard (-9...9).contains(Int(Int16(bitPattern: v))) else { return PTPCode.invalidValue }
        case .dRangePriority: guard [0, 1, 2, 0x8000].contains(v) else { return PTPCode.invalidValue }
        default: break
        }
        bank[code] = v
        store[Int(selector)] = bank
        return PTPCode.ok
    }

    /// A small JPEG whose colour comes from the profile (film, colour, WB shift): different recipes, different images.
    static func renderJPEG(_ p: ConversionProfile, full: Bool) -> Data {
        let w = full ? 96 : 64, h = full ? 64 : 48
        let film = Int(p[8]), mono = Film.isMonochrome(Film.all[max(0, min(19, film - 1))])
        let base = Double(film) / 20
        var r = 0.25 + base * 0.5 + Double(p[13]) / 40, g = 0.5 - base * 0.2 + Double(p[18]) / 200, b = 0.4 + Double(p[14]) / 40
        if mono { let l = (r + g + b) / 3; r = l; g = l; b = l }
        let px = [UInt8](repeating: 0, count: w * h * 4).enumerated().map { i, _ -> UInt8 in
            switch i % 4 { case 0: return UInt8(max(0, min(255, r * 255))); case 1: return UInt8(max(0, min(255, g * 255)))
                           case 2: return UInt8(max(0, min(255, b * 255))); default: return 255 }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return Data() }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
        return out as Data
    }

    private func u16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }

    private func deviceInfo() -> Data {
        var d = Data()
        func w16(_ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func w32(_ v: Int) { w16(v & 0xFFFF); w16(v >> 16) }
        w16(100); w32(6); w16(100)
        d.append(PTPString.encode("fujifilm.co.jp: 1.0; "))
        w16(0)
        for _ in 0..<5 { w32(0) }
        d.append(PTPString.encode("FUJIFILM")); d.append(PTPString.encode(displayName))
        d.append(PTPString.encode("1.10")); d.append(PTPString.encode("SIMULATED0001"))
        return d
    }
}
