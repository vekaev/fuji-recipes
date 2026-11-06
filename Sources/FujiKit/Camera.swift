import Foundation

/// PTP response codes worth naming (zgrimz 01-transport).
public enum PTPCode {
    public static let ok: UInt16 = 0x2001
    public static let generalError: UInt16 = 0x2002
    public static let notSupported: UInt16 = 0x200A
    public static let accessDenied: UInt16 = 0x200F
    public static let busy: UInt16 = 0x2019
    public static let invalidValue: UInt16 = 0x201C
    public static let sessionOpen: UInt16 = 0x201E

    public static func describe(_ code: UInt16) -> String {
        switch code {
        case ok: return "OK"
        case generalError: return "general error"
        case notSupported: return "not supported by this camera"
        case accessDenied: return "access denied"
        case busy: return "camera busy (switch it off and on)"
        case invalidValue: return "value refused (it may not fit this film, ISO or D-Range Priority)"
        case sessionOpen: return "session already open"
        default: return String(format: "response 0x%04X", code)
        }
    }
}

public enum PTPOp {
    public static let getDeviceInfo: UInt16 = 0x1001
    public static let getDevicePropValue: UInt16 = 0x1015
    public static let setDevicePropValue: UInt16 = 0x1016
}

public struct PTPResult: Sendable {
    public var code: UInt16
    public var data: Data
    public init(code: UInt16, data: Data = Data()) { self.code = code; self.data = data }
    public var ok: Bool { code == PTPCode.ok }
}

/// One PTP command at a time to one camera. `data` is the raw data-out payload (no container header).
public protocol PTPTransport: AnyObject, Sendable {
    var displayName: String { get }
    func send(_ op: UInt16, _ params: [UInt32], data: Data?) async throws -> PTPResult
    /// Close the PTP session so the next command opens a fresh one (the camera refuses a settings restore in a session
    /// that already downloaded the file).
    func resetSession() async
}

extension PTPTransport {
    public func resetSession() async {}
}

/// What a write to FS1–FS3 did, read back from the camera.
public struct DialWriteReport: Sendable {
    public var slot: String
    public var after: RecipeSettings
    public var kept: [String]          // recipe fields left as they are on the camera (not mapped yet)
    public var mismatches: [String]    // "field: wanted → camera has"
    public var unexpected: Int         // other bytes the camera changed beyond its own bookkeeping
    public var ok: Bool { mismatches.isEmpty && unexpected == 0 }
}

public struct CameraError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ d: String) { description = d }
}

/// GetDeviceInfo, parsed far enough for the model, firmware and serial number.
public struct DeviceInfo: Codable, Sendable {
    public var manufacturer = "", model = "", firmware = "", serial = ""
    public var vendorExtension = ""

    public init() {}
    public init(_ d: Data) {
        var o = 0
        func u16() -> Int { defer { o += 2 }; guard o + 1 < d.count else { return 0 }; return Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
        func u32() -> Int { let lo = u16(); let hi = u16(); return lo | hi << 16 }
        func array16() { let n = u32(); o += 2 * min(n, 10_000) }
        _ = u16(); _ = u32(); _ = u16()
        vendorExtension = PTPString.decode(d, at: &o)
        _ = u16()                                   // functional mode
        array16(); array16(); array16(); array16(); array16()   // operations, events, properties, capture, image formats
        manufacturer = PTPString.decode(d, at: &o)
        model = PTPString.decode(d, at: &o)
        firmware = PTPString.decode(d, at: &o)
        serial = PTPString.decode(d, at: &o)
    }

    /// The device properties GetDeviceInfo advertises (the third array). Not reliable for gating: bodies answer
    /// properties they don't advertise (zgrimz 01-transport), but it shows which mode the camera is in.
    public static func properties(_ d: Data) -> [UInt16] {
        var o = 0
        func u16() -> Int { defer { o += 2 }; guard o + 1 < d.count else { return 0 }; return Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
        func u32() -> Int { let lo = u16(); let hi = u16(); return lo | hi << 16 }
        _ = u16(); _ = u32(); _ = u16()
        _ = PTPString.decode(d, at: &o)
        _ = u16()
        for _ in 0..<2 { let n = u32(); o += 2 * min(n, 10_000) }
        let n = min(u32(), 10_000)
        return (0..<n).map { _ in UInt16(u16()) }
    }
}

/// One custom slot as read from the camera.
public struct Bank: Codable, Sendable {
    public var index: Int                       // 1 = C1
    public var name: String
    public var settings: RecipeSettings
    public var raw: [String: Int]               // "0xD192": 17, every setting the camera answered (for backups)
    public var slot: String { "C\(index)" }

    public var rawValues: [BankProp: UInt16] {
        var out: [BankProp: UInt16] = [:]
        for (k, v) in raw { if let code = UInt16(k.dropFirst(2), radix: 16), let p = BankProp(rawValue: code) { out[p] = UInt16(truncatingIfNeeded: v) } }
        return out
    }
}

/// What happened to one field during a write.
public struct FieldResult: Codable, Sendable {
    public var field: String
    public var code: String
    public var wanted: Int
    public var response: String
}

public struct WriteReport: Codable, Sendable {
    public var slot: String
    public var name: String
    public var written: [FieldResult]
    public var unchanged: Int
    public var refused: [FieldResult]
    public var mismatches: [String]             // after reading back, "field: wanted → camera has"
    public var after: RecipeSettings
    public var ok: Bool { refused.isEmpty && mismatches.isEmpty }
}

/// The Fujifilm custom-slot protocol over any PTP transport. Every operation selects its bank itself (0xD18C is an
/// edit pointer that persists across connections) and puts the selector back afterwards.
public actor FujiCamera {
    public let transport: PTPTransport
    public private(set) var info = DeviceInfo()
    private var bankCountCache: Int?

    public init(transport: PTPTransport) { self.transport = transport }

    public func deviceInfo() async throws -> DeviceInfo {
        let r = try await transport.send(PTPOp.getDeviceInfo, [], data: nil)
        guard r.ok else { throw CameraError("GetDeviceInfo: \(PTPCode.describe(r.code))") }
        info = DeviceInfo(r.data)
        if info.model.isEmpty { info.model = transport.displayName }
        return info
    }

    public func get(_ code: UInt16) async throws -> PTPResult {
        try await transport.send(PTPOp.getDevicePropValue, [UInt32(code)], data: nil)
    }

    public func getU16(_ code: UInt16) async throws -> UInt16? {
        let r = try await get(code)
        guard r.ok, r.data.count >= 2 else { return nil }
        return UInt16(r.data[r.data.startIndex]) | UInt16(r.data[r.data.startIndex + 1]) << 8
    }

    public func setU16(_ code: UInt16, _ value: UInt16) async throws -> UInt16 {
        try await transport.send(PTPOp.setDevicePropValue, [UInt32(code)], data: Data([UInt8(value & 0xFF), UInt8(value >> 8)])).code
    }

    public func usbMode() async throws -> USBMode { USBMode(raw: try await getU16(0xD16E)) }

    /// Probes the selector: selecting n+1 is refused (0x200A). 7 on most bodies, 4 on X-S20 / X-M5 / X-S10, 6 on GFX100S.
    /// Busy says nothing about the slots, so it's an error, and only a real count is remembered.
    public func bankCount() async throws -> Int {
        if let bankCountCache { return bankCountCache }
        guard let saved = try await getU16(BankProp.selector.rawValue) else {
            throw CameraError("This camera doesn't expose custom slots over USB. Set it to \(USBMode.rawConvBackupRestore.label) (X-T3, X-T30 and older bodies can't do this).")
        }
        var n = 0
        for k in 1...8 {
            let r = try await setU16(BankProp.selector.rawValue, UInt16(k))
            if r == PTPCode.busy {
                _ = try? await setU16(BankProp.selector.rawValue, saved)
                throw CameraError("The camera is busy: another program is using it. Try again in a few minutes.")
            }
            guard r == PTPCode.ok else { break }
            n = k
        }
        _ = try await setU16(BankProp.selector.rawValue, saved)
        if n > 0 { bankCountCache = n }
        return n
    }

    private func select(_ index: Int) async throws {
        let r = try await setU16(BankProp.selector.rawValue, UInt16(index))
        guard r == PTPCode.ok else { throw CameraError("Can't select C\(index): \(PTPCode.describe(r))") }
    }

    private func readSelected(_ index: Int) async throws -> Bank {
        let nameData = try await get(BankProp.name.rawValue)
        var raw: [String: Int] = [:], values: [BankProp: UInt16] = [:]
        for p in BankProp.settings {
            if let v = try await getU16(p.rawValue) { values[p] = v; raw[p.hex] = Int(v) }
        }
        return Bank(index: index, name: nameData.ok ? PTPString.decode(nameData.data) : "", settings: BankCodec.decode(values), raw: raw)
    }

    public func readBank(_ index: Int) async throws -> Bank {
        let saved = try await getU16(BankProp.selector.rawValue)
        try await select(index)
        let bank = try await readSelected(index)
        if let saved { _ = try await setU16(BankProp.selector.rawValue, saved) }
        return bank
    }

    public func readAll() async throws -> [Bank] {
        let n = try await bankCount()
        let saved = try await getU16(BankProp.selector.rawValue)
        var banks: [Bank] = []
        for k in 1...max(1, n) { try await select(k); banks.append(try await readSelected(k)) }
        if let saved { _ = try await setU16(BankProp.selector.rawValue, saved) }
        return banks
    }

    /// Writes only what differs, in the camera's order, then reads the whole bank back and compares by meaning.
    public func writeBank(_ index: Int, settings target: RecipeSettings, name: String?) async throws -> WriteReport {
        let saved = try await getU16(BankProp.selector.rawValue)
        try await select(index)
        let before = try await readSelected(index)
        let current = before.rawValues
        var want = target; want.normalize()
        let wanted = BankCodec.encode(want)
        var written: [FieldResult] = [], refused: [FieldResult] = []
        var unchanged = 0

        if let name {
            let clean = PTPString.bankName(name)
            if clean != before.name {
                let r = try await transport.send(PTPOp.setDevicePropValue, [UInt32(BankProp.name.rawValue)], data: PTPString.encode(clean)).code
                let f = FieldResult(field: "name", code: BankProp.name.hex, wanted: clean.count, response: PTPCode.describe(r))
                if r == PTPCode.ok { written.append(f) } else { refused.append(f) }
            }
        }
        let turningOff = want.dRangePriority == "Off" && before.settings.dRangePriority != "Off"
        for p in BankCodec.writeOrder(turningPriorityOff: turningOff) {
            guard let value = wanted[p] else { continue }
            // Grain Off reads back as 6/7: compare by meaning, not by raw value.
            let same = p == .grain ? (value == 1 && [1, 6, 7].contains(current[p] ?? 0)) || current[p] == value : current[p] == value
            if same { unchanged += 1; continue }
            let r = try await setU16(p.rawValue, value)
            let f = FieldResult(field: "\(p)", code: p.hex, wanted: Int(value), response: PTPCode.describe(r))
            if r == PTPCode.ok { written.append(f) } else { refused.append(f) }
        }
        let after = try await readSelected(index)
        if let saved { _ = try await setU16(BankProp.selector.rawValue, saved) }
        var mismatches = want.differences(to: after.settings)
        if let name, PTPString.bankName(name) != after.name { mismatches.append("name: \(PTPString.bankName(name)) → \(after.name)") }
        return WriteReport(slot: "C\(index)", name: after.name, written: written, unchanged: unchanged, refused: refused,
                           mismatches: mismatches, after: after.settings)
    }

    /// Writes raw values exactly as a backup recorded them (recipe fields only), then reads back.
    public func restoreBank(_ bank: Bank) async throws -> WriteReport {
        try await writeBank(bank.index, settings: bank.settings, name: bank.name)
    }

    /// The camera's full settings backup (what X Acquire / FUJIFILM TETHER APP save as .dat): PTP object handle 0,
    /// read with GetObjectInfo + GetObject. Read-only. Starts with "FUJIFILM" (libfuji fuji_usb.c, grawji camera_backup.py).
    /// Holds every setting incl. the film simulation dial's FS1–FS3 recipes; its layout is undocumented for X-Processor 5.
    /// Sends a whole settings file back (PTP object 0, like X Acquire's restore). WRITES EVERY CAMERA SETTING.
    /// Rules from libfuji / grawji (hardware-verified there): ObjectInfo of format 0x5000, 1076 bytes as X Acquire sends;
    /// never in a session that already downloaded the file (the camera answers 0x200F), so callers use a fresh process.
    /// Refuses a file for another model or of another size; the camera itself rejects a bad checksum with 0x200F.
    public func restoreSettingsFile(_ data: Data) async throws {
        let info = try await deviceInfo()
        _ = try? await usbMode()   // the preamble the camera expects before object access
        guard data.prefix(8) == Data("FUJIFILM".utf8), data.count > 0x40 else { throw CameraError("Not a Fujifilm settings file.") }
        let fileModel = String(decoding: data[0x14..<0x34].prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let want = info.model.replacingOccurrences(of: "-", with: "").uppercased()
        guard fileModel.replacingOccurrences(of: "-", with: "").uppercased().contains(want) || want.contains(fileModel.replacingOccurrences(of: "-", with: "").uppercased()) else {
            throw CameraError("This file is from a \(fileModel); the camera is a \(info.model). Not restoring.")
        }
        if let l = SettingsFile.layout(model: info.model), data.count != l.size {
            throw CameraError("The file is \(data.count) bytes; a \(info.model) settings file is \(l.size). Not restoring.")
        }
        var objectInfo = Data(count: 1076)
        objectInfo[4] = 0x00; objectInfo[5] = 0x50                       // ObjectFormat 0x5000, little-endian
        let n = UInt32(data.count)
        objectInfo[8] = UInt8(n & 0xFF); objectInfo[9] = UInt8((n >> 8) & 0xFF)
        objectInfo[10] = UInt8((n >> 16) & 0xFF); objectInfo[11] = UInt8((n >> 24) & 0xFF)
        let r1 = try await transport.send(0x100C, [0, 0], data: objectInfo)
        guard r1.ok else { throw CameraError("SendObjectInfo: \(PTPCode.describe(r1.code))") }
        let r2 = try await transport.send(0x100D, [], data: data)
        guard r2.ok else { throw CameraError("SendObject: \(PTPCode.describe(r2.code))") }
    }

    /// Writes a recipe into FS1–FS3 (`slot` 0-based) through the settings file: download, patch, restore in a fresh
    /// session, read back in another, and compare. Returns the file as it was before (keep it: it's the undo).
    public func writeDialSlot(_ slot: Int, settings: RecipeSettings) async throws -> (report: DialWriteReport, before: Data) {
        let info = try await deviceInfo()
        let before = try await downloadSettingsBackup()
        let (target, kept) = try SettingsFile.patch(before, slot: slot, settings: settings, model: info.model)
        let id = "FS\(slot + 1)"
        if target == before, let cur = SettingsFile.dialSlots(before, model: info.model)?[slot] {
            return (DialWriteReport(slot: id, after: cur.settings, kept: kept, mismatches: [], unexpected: 0), before)
        }
        await transport.resetSession()
        try await restoreSettingsFile(target)
        await transport.resetSession()
        let after = try await downloadSettingsBackup()
        guard let read = SettingsFile.dialSlots(after, model: info.model)?[slot] else {
            throw CameraError("Wrote \(id), but couldn't read the settings file back. The previous file is saved in Backups.")
        }
        let t = [UInt8](target), a = [UInt8](after)
        let unexpected = (0..<min(t.count, a.count)).filter { t[$0] != a[$0] && !SettingsFile.volatile.contains($0) }.count
        // Compare only what the patch wrote: the fields it leaves alone come from what the camera has.
        var wanted = settings
        wanted.wbRed = read.settings.wbRed; wanted.wbBlue = read.settings.wbBlue
        wanted.monoWarmCool = read.settings.monoWarmCool; wanted.monoMagentaGreen = read.settings.monoMagentaGreen
        wanted.dRangePriority = read.settings.dRangePriority
        wanted.normalize()
        let mismatches = wanted.differences(to: read.settings)
        return (DialWriteReport(slot: id, after: read.settings, kept: kept, mismatches: mismatches, unexpected: unexpected), before)
    }

    public func downloadSettingsBackup() async throws -> Data {
        let infoR = try await transport.send(0x1008, [0], data: nil)
        guard infoR.ok else { throw CameraError("GetObjectInfo(0): \(PTPCode.describe(infoR.code))") }
        let r = try await transport.send(0x1009, [0], data: nil)
        guard r.ok else { throw CameraError("GetObject(0): \(PTPCode.describe(r.code))") }
        guard r.data.count > 0x40, r.data.prefix(8) == Data("FUJIFILM".utf8) else {
            throw CameraError("The settings backup doesn't start with FUJIFILM (\(r.data.count) bytes); not saving it.")
        }
        return r.data
    }
}
