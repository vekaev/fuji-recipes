import Foundation

/// The camera's whole settings file (PTP object 0, what X Acquire / FUJIFILM TETHER APP save as .dat).
/// On bodies with a film simulation dial the FS1–FS3 recipes live only here, not in the 0xD18C slot properties.
///
/// Layout facts for the X-E5 (70,524-byte file; parallel per-parameter arrays, FS1's offset + slot × step; values in
/// the file's own codes) come from grawji's hardware-verified research (src/grawji/camera/fs_recipe.py, GPL-3.0: facts
/// only, no code). Verified here against the owner's X-E5 fw 1.12 on 2026-11-04: FS1 decoded to the Classic Neg. recipe
/// found in their photos' EXIF on every field but the WB shift, which reads 0/0 — so the shift offsets are unverified.
/// Writing (ADR 0004, test passed 2026-11-04): `patch` changes one slot's bytes and moves the u16 checksum at 0x120 by the
/// same byte delta; `FujiCamera.writeDialSlot` restores the whole file and reads it back. WB shift and WC/MG offsets are
/// still unverified, so patches leave them as they are.
public enum SettingsFile {
    public struct Layout: Sendable {
        public let size: Int
        public let slots: Int
        public let fields: [String: (offset: Int, step: Int)]
    }

    public static let xe5 = Layout(size: 70524, slots: 3, fields: [
        "film": (1991, 3), "kelvin": (34704, 2), "wb": (34716, 1), "nr": (34722, 1), "clarity": (34728, 1),
        "wc": (34731, 1), "mg": (34737, 1), "dr": (34743, 1), "color": (34752, 1), "sharp": (34758, 1),
        "hi": (34764, 1), "sh": (34770, 1), "cc": (34776, 1), "fxb": (34779, 1), "grain": (34782, 1),
        "gsize": (34785, 1), "r": (34864, 1), "b": (34870, 1)])

    static let films: [Int: String] = [0x01: "Provia", 0x02: "Astia", 0x04: "Velvia", 0x06: "Sepia", 0x09: "Monochrome",
        0x0A: "Monochrome+R", 0x0B: "Monochrome+Ye", 0x0C: "Monochrome+G", 0x0D: "Pro Neg. Std", 0x0E: "Pro Neg. Hi",
        0x0F: "Classic Chrome", 0x10: "Classic Neg.", 0x11: "Nostalgic Neg.", 0x12: "Reala Ace", 0x13: "Eterna",
        0x14: "Eterna Bleach Bypass", 0x16: "Acros", 0x17: "Acros+R", 0x18: "Acros+Ye", 0x19: "Acros+G"]
    static let wb: [Int: String] = [0: "Auto", 3: "Daylight", 4: "Shade", 5: "Fluorescent 1", 6: "Fluorescent 2",
        7: "Fluorescent 3", 8: "Incandescent", 9: "Underwater", 10: "Kelvin"]

    /// Bytes the camera rewrites itself on a restore (seen on the X-E5): the checksum, a "_FUJI" mark, two counters.
    public static let volatile: Set<Int> = Set([0x120, 0x121] + Array(5956...5960) + Array(0xF6C0...0xF6C5) + [0xF724, 0xF725])
    /// Recipe fields a patch writes. The rest (WB shift, mono WC/MG, D-Range Priority) stay as set on the camera.
    public static let writable = ["film", "grainRoughness", "grainSize", "colorChrome", "colorChromeFxBlue", "wb", "wbKelvin",
                                  "dynamicRange", "highlight", "shadow", "color", "sharpness", "highIsoNr", "clarity"]

    /// The file's own value codes for a recipe (inverse of `dialSlots`). Nil where a value has no code here.
    static func codes(_ r: RecipeSettings) -> [String: Int] {
        var c: [String: Int] = [:]
        if let f = films.first(where: { $0.value == r.film })?.key { c["film"] = f }
        c["grain"] = ["Strong": 0, "Weak": 1, "Off": 2][r.grainRoughness] ?? 2
        c["gsize"] = r.grainSize == "Large" ? 1 : 0
        let effect = ["Off": 0, "Weak": 1, "Strong": 2]
        c["cc"] = effect[r.colorChrome] ?? 0
        c["fxb"] = effect[r.colorChromeFxBlue] ?? 0
        if let w = wb.first(where: { $0.value == r.wb })?.key { c["wb"] = w }
        if r.wb == "Kelvin", let k = r.wbKelvin { c["kelvin"] = k }
        c["dr"] = ["Auto": 0, "DR100": 1, "DR200": 2, "DR400": 3][r.dynamicRange] ?? 1
        c["hi"] = Int(((r.highlight + 2) * 2).rounded())
        c["sh"] = Int(((r.shadow + 2) * 2).rounded())
        if let col = r.color, !r.isMonochrome { c["color"] = 7 - col }
        c["sharp"] = 4 - r.sharpness
        c["nr"] = r.highIsoNr + 4
        c["clarity"] = r.clarity + 6
        return c
    }

    /// A copy of `file` with `settings` in FS slot `slot` (0-based) and the checksum moved by the same byte delta.
    /// Returns the new file and the recipe fields left as they are on the camera.
    public static func patch(_ file: Data, slot: Int, settings: RecipeSettings, model: String) throws -> (Data, [String]) {
        guard let l = layout(model: model), file.count == l.size, file.prefix(8) == Data("FUJIFILM".utf8) else {
            throw CameraError("No known settings-file layout for the \(model), or the file doesn't fit it.")
        }
        guard (0..<l.slots).contains(slot) else { throw CameraError("FS\(slot + 1) doesn't exist on the \(model).") }
        var b = [UInt8](file)
        var delta = 0
        for (key, value) in codes(settings) {
            guard let f = l.fields[key] else { continue }
            let o = f.offset + slot * f.step
            if key == "kelvin" {
                let lo = value & 0xFF, hi = (value >> 8) & 0xFF
                delta += lo + hi - Int(b[o]) - Int(b[o + 1])
                b[o] = UInt8(lo); b[o + 1] = UInt8(hi)
            } else {
                guard (0...255).contains(value) else { throw CameraError("\(key) can't be stored (\(value)).") }
                delta += value - Int(b[o]); b[o] = UInt8(value)
            }
        }
        let stored = Int(b[0x120]) | Int(b[0x121]) << 8
        let sum = (stored + delta) & 0xFFFF
        b[0x120] = UInt8(sum & 0xFF); b[0x121] = UInt8(sum >> 8)
        var kept = ["wb_red", "wb_blue", "mono_warm_cool", "mono_magenta_green"]
        if settings.dRangePriority != "Off" { kept.append("d_range_priority") }
        if films.first(where: { $0.value == settings.film }) == nil { kept.append("film") }
        return (Data(b), kept)
    }

    public static func layout(model: String) -> Layout? {
        model.uppercased().filter { $0.isLetter || $0.isNumber }.replacingOccurrences(of: "FUJIFILM", with: "") == "XE5" ? xe5 : nil
    }

    public struct DialSlot: Codable, Sendable {
        public var slot: String            // "FS1"
        public var settings: RecipeSettings
        public var unverified: [String]    // fields read from offsets not yet confirmed on hardware
    }

    /// FS1…FSn from a settings file, or nil when the body has no known layout or the file doesn't fit it.
    public static func dialSlots(_ d: Data, model: String) -> [DialSlot]? {
        guard let l = layout(model: model), d.count == l.size, d.prefix(8) == Data("FUJIFILM".utf8) else { return nil }
        let bytes = [UInt8](d)
        return (0..<l.slots).map { i in
            func v(_ k: String) -> Int {
                let f = l.fields[k]!, o = f.offset + i * f.step
                return k == "kelvin" ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 : Int(bytes[o])
            }
            var s = RecipeSettings()
            s.film = films[v("film")] ?? "?\(v("film"))"
            switch v("grain") { case 0: s.grainRoughness = "Strong"; case 1: s.grainRoughness = "Weak"; default: s.grainRoughness = "Off" }
            s.grainSize = v("gsize") == 1 ? "Large" : "Small"
            let effect = ["Off", "Weak", "Strong"]
            s.colorChrome = effect[min(2, v("cc"))]
            s.colorChromeFxBlue = effect[min(2, v("fxb"))]
            s.wb = wb[v("wb")] ?? "?\(v("wb"))"
            s.wbKelvin = v("kelvin")
            s.wbRed = 9 - v("r"); s.wbBlue = 9 - v("b")
            s.dynamicRange = ["Auto", "DR100", "DR200", "DR400"][min(3, v("dr"))]
            s.highlight = Double(v("hi")) / 2 - 2; s.shadow = Double(v("sh")) / 2 - 2
            s.color = 7 - v("color")
            s.monoWarmCool = (18 - v("wc")) / 2; s.monoMagentaGreen = (18 - v("mg")) / 2
            s.sharpness = 4 - v("sharp")
            s.highIsoNr = v("nr") - 4
            s.clarity = v("clarity") - 6
            s.normalize()
            return DialSlot(slot: "FS\(i + 1)", settings: s, unverified: ["wb_red", "wb_blue", "mono_warm_cool", "mono_magenta_green"])
        }
    }
}
