import Foundation

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
        }
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
            guard let v = store[Int(selector)]?[code] else { return PTPResult(code: PTPCode.notSupported) }
            return PTPResult(code: PTPCode.ok, data: u16(v))
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
        case .dynamicRange, .highlight, .shadow: guard !drpOn else { return PTPCode.invalidValue }
        case .kelvin: guard bank[BankProp.wbMode.rawValue] == 0x8007, (2500...10000).contains(Int(v)) else { return PTPCode.invalidValue }
        case .wbRed, .wbBlue: guard (-9...9).contains(Int(Int16(bitPattern: v))) else { return PTPCode.invalidValue }
        case .dRangePriority: guard [0, 1, 2, 0x8000].contains(v) else { return PTPCode.invalidValue }
        default: break
        }
        bank[code] = v
        store[Int(selector)] = bank
        return PTPCode.ok
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
