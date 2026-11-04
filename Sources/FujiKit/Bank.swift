import Foundation

/// Fujifilm custom-setting ("bank") properties, read with GetDevicePropValue (0x1015) and written with
/// SetDevicePropValue (0x1016) after selecting the bank with 0xD18C. All values are u16 little-endian except the
/// name (a PTP string). Sources: zgrimz/fujifilm-ptp-reference docs/02–04 (CC BY 4.0), ILFforever/fujifilm-ptp-recipes,
/// FilmKit src/ptp/constants.ts (MIT), libfuji lib/fujiptp.h (MIT). See docs/PROTOCOL.md.
public enum BankProp: UInt16, CaseIterable, Sendable {
    case selector = 0xD18C
    case name = 0xD18D
    case imageSize = 0xD18E          // not a recipe field: carried through, never written
    case imageQuality = 0xD18F       // not a recipe field
    case dynamicRange = 0xD190       // percent 100/200/400, 0xFFFF = Auto
    case dRangePriority = 0xD191     // 0 Off, 1 Weak, 2 Strong, 0x8000 Auto
    case film = 0xD192               // 1…20
    case monoWarmCool = 0xD193       // signed ×10
    case monoMagentaGreen = 0xD194   // signed ×10
    case grain = 0xD195              // write 1 Off, 2 Weak/Small, 3 Strong/Small, 4 Weak/Large, 5 Strong/Large; reads 6/7 = Off
    case colorChrome = 0xD196        // 1 Off, 2 Weak, 3 Strong
    case colorChromeFxBlue = 0xD197
    case smoothSkin = 0xD198         // not a recipe field
    case wbMode = 0xD199
    case wbRed = 0xD19A              // signed, not ×10
    case wbBlue = 0xD19B
    case kelvin = 0xD19C
    case highlight = 0xD19D          // signed ×10
    case shadow = 0xD19E
    case color = 0xD19F
    case sharpness = 0xD1A0
    case highIsoNr = 0xD1A1          // lookup table
    case clarity = 0xD1A2            // signed ×10
    case lensModulation = 0xD1A3     // not a recipe field
    case colorSpace = 0xD1A4         // not a recipe field

    /// The settings stored in a bank, in read order (everything but the selector and the name).
    public static let settings: [BankProp] = allCases.filter { $0 != .selector && $0 != .name }
    public static let recipeFields: Set<BankProp> = [.dynamicRange, .dRangePriority, .film, .monoWarmCool, .monoMagentaGreen,
                                                    .grain, .colorChrome, .colorChromeFxBlue, .wbMode, .wbRed, .wbBlue,
                                                    .kelvin, .highlight, .shadow, .color, .sharpness, .highIsoNr, .clarity]
    public var hex: String { String(format: "0x%04X", rawValue) }
}

/// Fujifilm USB mode, property 0xD16E (libfuji fuji_usb.c).
public enum USBMode: Equatable, Sendable {
    case rawConvBackupRestore, tether, webcam, other(UInt16), cardReader
    public init(raw: UInt16?) {
        switch raw {
        case nil: self = .cardReader
        case 6: self = .rawConvBackupRestore
        case 5: self = .tether
        case 8: self = .webcam
        case let v?: self = .other(v)
        }
    }
    /// Where the setting is on the camera.
    public static let howToSet = "On the camera: \(USBMode.menuPath). Then switch the camera off, connect the USB-C cable, and switch it on (quit Preview or Photos if they grab the camera)."
    public static let menuPath = "MENU/OK ▸ network/USB tab ▸ CONNECTION MODE ▸ USB RAW CONV./BACKUP RESTORE, and on the same tab USB POWER SUPPLY/COMM SETTING ▸ AUTO (or POWER SUPPLY OFF/COMM ON); older bodies: SET UP ▸ CONNECTION SETTING ▸ PC CONNECTION MODE"
    public var canWriteSlots: Bool { self == .rawConvBackupRestore || self == .tether }
    public var label: String {
        switch self {
        case .rawConvBackupRestore: return "USB RAW CONV./BACKUP RESTORE"
        case .tether: return "USB TETHER SHOOTING"
        case .webcam: return "USB WEBCAM"
        case .cardReader: return "USB CARD READER"
        case .other(let v): return "unknown (\(v))"
        }
    }
}

/// Encodes recipe settings to raw bank values and back.
public enum BankCodec {
    static let effects = ["Off": 1, "Weak": 2, "Strong": 3]
    static let wbCodes: [String: UInt16] = ["Auto": 2, "Auto White Priority": 0x8020, "Auto Ambience Priority": 0x8021,
                                            "Daylight": 4, "Shade": 0x8006, "Fluorescent 1": 0x8001, "Fluorescent 2": 0x8002,
                                            "Fluorescent 3": 0x8003, "Incandescent": 6, "Underwater": 8, "Kelvin": 0x8007,
                                            "Custom 1": 0x8008, "Custom 2": 0x8009, "Custom 3": 0x800A]
    /// High ISO NR −4…+4 (zgrimz 03-encodings; −4, 0, +4 also in FilmKit).
    static let nrCodes: [Int: UInt16] = [-4: 0x8000, -3: 0x7000, -2: 0x4000, -1: 0x3000, 0: 0x2000, 1: 0x1000, 2: 0x0000, 3: 0x6000, 4: 0x5000]
    static let drpCodes: [String: UInt16] = ["Off": 0, "Weak": 1, "Strong": 2, "Auto": 0x8000]

    static func s16(_ v: Int) -> UInt16 { UInt16(bitPattern: Int16(clamping: v)) }
    static func signedInt(_ raw: UInt16) -> Int { Int(Int16(bitPattern: raw)) }
    static func tenths(_ v: Double) -> UInt16 { s16(Int((v * 10).rounded())) }
    static func fromTenths(_ raw: UInt16) -> Double { Double(signedInt(raw)) / 10 }

    /// The raw values for every recipe property. Mono fields only for monochrome films, colour only for colour films,
    /// Kelvin only in Kelvin mode, DR and tone only when D-Range Priority is off (the camera refuses them otherwise).
    public static func encode(_ input: RecipeSettings) -> [BankProp: UInt16] {
        var s = input; s.normalize()
        var v: [BankProp: UInt16] = [:]
        v[.film] = UInt16((Film.all.firstIndex(of: s.film) ?? 0) + 1)
        let large = s.grainSize == "Large"
        switch s.grainRoughness {
        case "Weak": v[.grain] = large ? 4 : 2
        case "Strong": v[.grain] = large ? 5 : 3
        default: v[.grain] = 1
        }
        v[.colorChrome] = UInt16(effects[s.colorChrome] ?? 1)
        v[.colorChromeFxBlue] = UInt16(effects[s.colorChromeFxBlue] ?? 1)
        v[.wbMode] = wbCodes[s.wb] ?? 2
        if s.wb == "Kelvin" { v[.kelvin] = UInt16(clamping: s.wbKelvin ?? 5500) }
        v[.wbRed] = s16(s.wbRed)
        v[.wbBlue] = s16(s.wbBlue)
        v[.dRangePriority] = drpCodes[s.dRangePriority] ?? 0
        if s.dRangePriority == "Off" {
            v[.dynamicRange] = s.dynamicRange == "Auto" ? 0xFFFF : UInt16(s.dynamicRange.dropFirst(2)) ?? 100
            v[.highlight] = tenths(s.highlight)
            v[.shadow] = tenths(s.shadow)
        }
        if s.isMonochrome {
            v[.monoWarmCool] = s16((s.monoWarmCool ?? 0) * 10)
            v[.monoMagentaGreen] = s16((s.monoMagentaGreen ?? 0) * 10)
        } else {
            v[.color] = s16((s.color ?? 0) * 10)
        }
        v[.sharpness] = s16(s.sharpness * 10)
        v[.highIsoNr] = nrCodes[s.highIsoNr] ?? 0x2000
        v[.clarity] = s16(s.clarity * 10)
        return v
    }

    /// Raw bank values → settings. Unknown codes come back as "?<raw>" so nothing is silently guessed.
    public static func decode(_ v: [BankProp: UInt16]) -> RecipeSettings {
        var s = RecipeSettings()
        if let f = v[.film] { s.film = (1...Film.all.count).contains(Int(f)) ? Film.all[Int(f) - 1] : "?\(f)" }
        switch v[.grain] ?? 1 {
        case 2: s.grainRoughness = "Weak"; s.grainSize = "Small"
        case 3: s.grainRoughness = "Strong"; s.grainSize = "Small"
        case 4: s.grainRoughness = "Weak"; s.grainSize = "Large"
        case 5: s.grainRoughness = "Strong"; s.grainSize = "Large"
        default: s.grainRoughness = "Off"; s.grainSize = "Off"     // 1, and 6/7 (Off with the size kept)
        }
        func effect(_ raw: UInt16?) -> String { ["Off", "Weak", "Strong"][max(0, min(2, Int(raw ?? 1) - 1))] }
        s.colorChrome = effect(v[.colorChrome])
        s.colorChromeFxBlue = effect(v[.colorChromeFxBlue])
        let wb = v[.wbMode] ?? 2
        s.wb = wbCodes.first { $0.value == wb }?.key ?? "?\(String(format: "0x%04X", wb))"
        if s.wb == "Kelvin" { s.wbKelvin = v[.kelvin].map(Int.init) }
        s.wbRed = v[.wbRed].map(signedInt) ?? 0
        s.wbBlue = v[.wbBlue].map(signedInt) ?? 0
        let drp = v[.dRangePriority] ?? 0
        s.dRangePriority = drpCodes.first { $0.value == drp }?.key ?? "Off"
        let dr = v[.dynamicRange] ?? 100
        s.dynamicRange = (dr == 0xFFFF || dr == 0) ? "Auto" : "DR\(dr)"
        s.highlight = v[.highlight].map(fromTenths) ?? 0
        s.shadow = v[.shadow].map(fromTenths) ?? 0
        s.color = v[.color].map { signedInt($0) / 10 } ?? 0
        s.monoWarmCool = v[.monoWarmCool].map { signedInt($0) / 10 }
        s.monoMagentaGreen = v[.monoMagentaGreen].map { signedInt($0) / 10 }
        s.sharpness = v[.sharpness].map { signedInt($0) / 10 } ?? 0
        let nr = v[.highIsoNr] ?? 0x2000
        s.highIsoNr = nrCodes.first { $0.value == nr }?.key ?? 0
        s.clarity = v[.clarity].map { signedInt($0) / 10 } ?? 0
        s.normalize()
        return s
    }

    /// The order to write changed values in (zgrimz 04-custom-slots): film first (some bodies reset tone/colour when
    /// it changes), D-Range Priority before DR when turning it off, Kelvin right after the WB mode and the shifts
    /// after Kelvin, otherwise ascending.
    public static func writeOrder(turningPriorityOff: Bool) -> [BankProp] {
        var order: [BankProp] = [.film]
        order += turningPriorityOff ? [.dRangePriority, .dynamicRange] : [.dynamicRange, .dRangePriority]
        order += [.monoWarmCool, .monoMagentaGreen, .grain, .colorChrome, .colorChromeFxBlue,
                  .wbMode, .kelvin, .wbRed, .wbBlue, .highlight, .shadow, .color, .sharpness, .highIsoNr, .clarity]
        return order
    }
}

/// Bank names are PTP strings: u8 count (characters incl. NUL), UCS-2LE, then 0x0000. An empty name is `01 00 00`.
public enum PTPString {
    public static func encode(_ text: String) -> Data {
        let units = Array(text.utf16)
        var d = Data([UInt8(units.count + 1)])
        for u in units { d.append(UInt8(u & 0xFF)); d.append(UInt8(u >> 8)) }
        d.append(contentsOf: [0, 0])
        return d
    }

    public static func decode(_ data: Data, at offset: inout Int) -> String {
        guard offset < data.count else { return "" }
        let count = Int(data[data.startIndex + offset]); offset += 1
        var units: [UInt16] = []
        for _ in 0..<count {
            guard offset + 1 < data.count else { break }
            let u = UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
            offset += 2
            if u != 0 { units.append(u) }
        }
        return String(decoding: units, as: UTF16.self)
    }

    public static func decode(_ data: Data) -> String { var o = 0; return decode(data, at: &o) }

    /// Up to 25 printable ASCII characters round-trip (zgrimz 03-encodings).
    public static func bankName(_ text: String) -> String {
        let ascii = text.unicodeScalars.filter { $0.value >= 0x20 && $0.value < 0x7F }
        return String(String.UnicodeScalarView(ascii)).prefix(25).trimmingCharacters(in: .whitespaces)
    }
}
