import Foundation

/// The in-camera settings a Fujifilm custom slot (C1–C7) stores. Field names and value spellings match the
/// recipe files in the library (`recipes/<slug>.json`); see skills/fuji-recipes/references/schema.md.
public struct RecipeSettings: Codable, Equatable, Hashable, Sendable {
    public var film: String = "Provia"
    public var grainRoughness: String = "Off"      // Off, Weak, Strong
    public var grainSize: String = "Off"           // Off (when roughness is Off), Small, Large
    public var colorChrome: String = "Off"         // Off, Weak, Strong
    public var colorChromeFxBlue: String = "Off"   // Off, Weak, Strong
    public var wb: String = "Auto"
    public var wbKelvin: Int? = nil                // 2500…10000 when wb == "Kelvin"
    public var wbRed: Int = 0                      // −9…+9
    public var wbBlue: Int = 0
    public var dynamicRange: String = "DR100"      // Auto, DR100, DR200, DR400
    public var dRangePriority: String = "Off"      // Off, Auto, Weak, Strong
    public var highlight: Double = 0               // −2…+4, half steps
    public var shadow: Double = 0
    public var color: Int? = 0                     // −4…+4; nil for monochrome films
    public var monoWarmCool: Int? = nil            // −9…+9 for monochrome films; nil for colour films
    public var monoMagentaGreen: Int? = nil
    public var sharpness: Int = 0                  // −4…+4
    public var highIsoNr: Int = 0                  // −4…+4
    public var clarity: Int = 0                    // −5…+5

    public init() {}

    enum CodingKeys: String, CodingKey {
        case film, wb, color, sharpness, clarity, highlight, shadow
        case grainRoughness = "grain_roughness", grainSize = "grain_size", colorChrome = "color_chrome"
        case colorChromeFxBlue = "color_chrome_fx_blue", wbKelvin = "wb_kelvin", wbRed = "wb_red", wbBlue = "wb_blue"
        case dynamicRange = "dynamic_range", dRangePriority = "d_range_priority", monoWarmCool = "mono_warm_cool"
        case monoMagentaGreen = "mono_magenta_green", highIsoNr = "high_iso_nr"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        film = try c.decodeIfPresent(String.self, forKey: .film) ?? "Provia"
        grainRoughness = try c.decodeIfPresent(String.self, forKey: .grainRoughness) ?? "Off"
        grainSize = try c.decodeIfPresent(String.self, forKey: .grainSize) ?? "Off"
        colorChrome = try c.decodeIfPresent(String.self, forKey: .colorChrome) ?? "Off"
        colorChromeFxBlue = try c.decodeIfPresent(String.self, forKey: .colorChromeFxBlue) ?? "Off"
        wb = try c.decodeIfPresent(String.self, forKey: .wb) ?? "Auto"
        wbKelvin = try c.decodeIfPresent(Int.self, forKey: .wbKelvin)
        wbRed = try c.decodeIfPresent(Int.self, forKey: .wbRed) ?? 0
        wbBlue = try c.decodeIfPresent(Int.self, forKey: .wbBlue) ?? 0
        dynamicRange = try c.decodeIfPresent(String.self, forKey: .dynamicRange) ?? "DR100"
        dRangePriority = try c.decodeIfPresent(String.self, forKey: .dRangePriority) ?? "Off"
        highlight = try c.decodeIfPresent(Double.self, forKey: .highlight) ?? 0
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? 0
        color = try c.decodeIfPresent(Int.self, forKey: .color)
        monoWarmCool = try c.decodeIfPresent(Int.self, forKey: .monoWarmCool)
        monoMagentaGreen = try c.decodeIfPresent(Int.self, forKey: .monoMagentaGreen)
        sharpness = try c.decodeIfPresent(Int.self, forKey: .sharpness) ?? 0
        highIsoNr = try c.decodeIfPresent(Int.self, forKey: .highIsoNr) ?? 0
        clarity = try c.decodeIfPresent(Int.self, forKey: .clarity) ?? 0
        normalize()
    }

    /// Nulls are written out (not omitted) so every tool reading the files sees the same keys.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(film, forKey: .film)
        try c.encode(grainRoughness, forKey: .grainRoughness)
        try c.encode(grainSize, forKey: .grainSize)
        try c.encode(colorChrome, forKey: .colorChrome)
        try c.encode(colorChromeFxBlue, forKey: .colorChromeFxBlue)
        try c.encode(wb, forKey: .wb)
        try c.encode(wbKelvin, forKey: .wbKelvin)
        try c.encode(wbRed, forKey: .wbRed)
        try c.encode(wbBlue, forKey: .wbBlue)
        try c.encode(dynamicRange, forKey: .dynamicRange)
        try c.encode(dRangePriority, forKey: .dRangePriority)
        try c.encode(highlight, forKey: .highlight)
        try c.encode(shadow, forKey: .shadow)
        try c.encode(color, forKey: .color)
        try c.encode(monoWarmCool, forKey: .monoWarmCool)
        try c.encode(monoMagentaGreen, forKey: .monoMagentaGreen)
        try c.encode(sharpness, forKey: .sharpness)
        try c.encode(highIsoNr, forKey: .highIsoNr)
        try c.encode(clarity, forKey: .clarity)
    }

    public var isMonochrome: Bool { Film.isMonochrome(film) }

    /// Puts the fields that don't apply into their canonical empty state (mono vs colour, grain size, Kelvin).
    public mutating func normalize() {
        if isMonochrome {
            color = nil
            monoWarmCool = monoWarmCool ?? 0
            monoMagentaGreen = monoMagentaGreen ?? 0
        } else {
            color = color ?? 0
            monoWarmCool = nil
            monoMagentaGreen = nil
        }
        if grainRoughness == "Off" { grainSize = "Off" } else if grainSize == "Off" { grainSize = "Small" }
        if wb != "Kelvin" { wbKelvin = nil }
    }

    /// One line, like the library index: "Classic Neg. · Grain SL · CC S · FXB S · WB Auto R+1 B−3 · DR100 H−2 S−1 · Col +1 · Sh −2 NR −4 Cl 0".
    public var summary: String {
        var p = [film]
        if grainRoughness != "Off" { p.append("Grain \(grainRoughness.prefix(1))\(grainSize.prefix(1))") }
        if colorChrome != "Off" { p.append("CC \(colorChrome.prefix(1))") }
        if colorChromeFxBlue != "Off" { p.append("FXB \(colorChromeFxBlue.prefix(1))") }
        let wbName = wb == "Kelvin" ? "\(wbKelvin ?? 0)K" : wb.replacingOccurrences(of: "Auto White Priority", with: "AWP").replacingOccurrences(of: "Auto Ambience Priority", with: "AAP")
        p.append("WB \(wbName) R\(signed(wbRed)) B\(signed(wbBlue))")
        p.append(dRangePriority != "Off" ? "DRP \(dRangePriority)" : "\(dynamicRange) H\(signed(highlight)) S\(signed(shadow))")
        if let color { p.append("Col \(signed(color))") } else { p.append("WC \(signed(monoWarmCool ?? 0)) MG \(signed(monoMagentaGreen ?? 0))") }
        p.append("Sh \(signed(sharpness)) NR \(signed(highIsoNr)) Cl \(signed(clarity))")
        return p.joined(separator: " · ")
    }

    /// The text creators post and the camera menu order, ready to dial in by hand.
    public var text: String {
        var lines = ["Film Simulation: \(film)",
                     "Grain Effect: \(grainRoughness == "Off" ? "Off" : "\(grainRoughness), \(grainSize)")",
                     "Color Chrome Effect: \(colorChrome)",
                     "Color Chrome FX Blue: \(colorChromeFxBlue)",
                     "White Balance: \(wb == "Kelvin" ? "\(wbKelvin ?? 0)K" : wb), \(signed(wbRed)) Red & \(signed(wbBlue)) Blue"]
        if dRangePriority != "Off" {
            lines.append("D-Range Priority: \(dRangePriority)")
        } else {
            lines += ["Dynamic Range: \(dynamicRange)", "Highlight: \(signed(highlight))", "Shadow: \(signed(shadow))"]
        }
        if let color { lines.append("Color: \(signed(color))") } else {
            lines.append("Monochromatic Color: WC \(signed(monoWarmCool ?? 0)), MG \(signed(monoMagentaGreen ?? 0))")
        }
        lines += ["Sharpness: \(signed(sharpness))", "High ISO NR: \(signed(highIsoNr))", "Clarity: \(signed(clarity))"]
        return lines.joined(separator: "\n")
    }

    /// Field-by-field differences, "field: old → new", only where they matter for this film.
    public func differences(to other: RecipeSettings) -> [String] {
        let a = Mirror(reflecting: self).children, b = Mirror(reflecting: other).children
        var out: [String] = []
        for (x, y) in zip(a, b) {
            guard let label = x.label else { continue }
            let l = "\(unwrap(x.value))", r = "\(unwrap(y.value))"
            if l != r { out.append("\(Self.labels[label] ?? label): \(l) → \(r)") }
        }
        return out
    }

    /// How `camera` (read from a slot) differs from this recipe only where the camera itself sets limits, or nil when
    /// anything else differs. Those limits: a lower dynamic range (DR200 / DR400 need the slot's hidden ISO at 320 /
    /// 640 or more, so the X-E5 keeps DR100), and B&W toning (WC/MG), which some slots refuse and FS positions don't
    /// read reliably. An exact match returns [].
    public func cameraLimitedDifferences(_ camera: RecipeSettings, dial: Bool = false) -> [String]? {
        var a = self, b = camera
        a.normalize(); b.normalize()
        if a == b { return [] }
        var notes: [String] = []
        let rank = ["DR100": 1, "DR200": 2, "DR400": 3]
        if a.dynamicRange != b.dynamicRange, let wa = rank[a.dynamicRange], let wb = rank[b.dynamicRange], wb < wa {
            notes.append("\(b.dynamicRange) on the camera (the recipe has \(a.dynamicRange): the slot's ISO is too low)")
            b.dynamicRange = a.dynamicRange
        }
        if a.isMonochrome, a.monoWarmCool != b.monoWarmCool || a.monoMagentaGreen != b.monoMagentaGreen {
            notes.append("toning WC \(b.monoWarmCool ?? 0) MG \(b.monoMagentaGreen ?? 0) on the camera (the recipe has WC \(a.monoWarmCool ?? 0) MG \(a.monoMagentaGreen ?? 0))")
            b.monoWarmCool = a.monoWarmCool; b.monoMagentaGreen = a.monoMagentaGreen
        }
        // Clarity left at 0 on the camera: it makes every shot wait 1–3 s for "Storing" (`Preferences.clarity`).
        if a.clarity != 0, b.clarity == 0 {
            notes.append("Clarity 0 on the camera (the recipe has \(signed(a.clarity)); off, so shots save without waiting)")
            b.clarity = a.clarity
        }
        // FS1–FS3: the WB shift isn't written there yet (offsets unmapped), so the camera keeps its own.
        if dial, a.wbRed != b.wbRed || a.wbBlue != b.wbBlue {
            notes.append("WB shift R\(b.wbRed) B\(b.wbBlue) on the camera (the recipe has R\(a.wbRed) B\(a.wbBlue); FS positions keep their own for now)")
            b.wbRed = a.wbRed; b.wbBlue = a.wbBlue
        }
        return a == b ? notes : nil
    }

    public static let labels = ["film": "Film simulation", "grainRoughness": "Grain", "grainSize": "Grain size",
        "colorChrome": "Color chrome", "colorChromeFxBlue": "FX Blue", "wb": "White balance", "wbKelvin": "Kelvin",
        "wbRed": "WB shift red", "wbBlue": "WB shift blue", "dynamicRange": "Dynamic range", "dRangePriority": "D-Range Priority",
        "highlight": "Highlight", "shadow": "Shadow", "color": "Color", "monoWarmCool": "Mono warm/cool",
        "monoMagentaGreen": "Mono magenta/green", "sharpness": "Sharpness", "highIsoNr": "High ISO NR", "clarity": "Clarity"]

    private func unwrap(_ v: Any) -> String {
        let m = Mirror(reflecting: v)
        if m.displayStyle == .optional { return m.children.first.map { unwrap($0.value) } ?? "—" }
        if let d = v as? Double { return signed(d) }
        if let i = v as? Int { return abs(i) >= 1000 ? String(i) : signed(i) }   // Kelvin unsigned
        return "\(v)"
    }
}

func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : v < 0 ? "−\(-v)" : "0" }
func signed(_ v: Double) -> String {
    let s = v == v.rounded() ? String(Int(abs(v))) : String(abs(v))
    return v > 0 ? "+\(s)" : v < 0 ? "−\(s)" : "0"
}

public enum Film {
    /// Camera order: the PTP value is the index + 1 (verified: rawji fuji_enums.py, zgrimz 03-encodings).
    public static let all = ["Provia", "Velvia", "Astia", "Pro Neg. Hi", "Pro Neg. Std", "Monochrome", "Monochrome+Ye",
                             "Monochrome+R", "Monochrome+G", "Sepia", "Classic Chrome", "Acros", "Acros+Ye", "Acros+R",
                             "Acros+G", "Eterna", "Classic Neg.", "Eterna Bleach Bypass", "Nostalgic Neg.", "Reala Ace"]
    public static func isMonochrome(_ film: String) -> Bool { film.hasPrefix("Acros") || film.hasPrefix("Monochrome") || film == "Sepia" }
}

public enum Values {
    public static let offWeakStrong = ["Off", "Weak", "Strong"]
    public static let grainSize = ["Off", "Small", "Large"]
    public static let wb = ["Auto", "Auto White Priority", "Auto Ambience Priority", "Daylight", "Shade", "Fluorescent 1",
                            "Fluorescent 2", "Fluorescent 3", "Incandescent", "Underwater", "Kelvin", "Custom 1", "Custom 2", "Custom 3"]
    public static let dynamicRange = ["Auto", "DR100", "DR200", "DR400"]
    public static let dRangePriority = ["Off", "Auto", "Weak", "Strong"]
    public static let status = ["favorite", "mine", "tried", "to-try", "rejected"]
}

/// One recipe file in the library.
public struct Recipe: Codable, Equatable, Sendable {
    public var slug: String
    public var name: String
    public var status: String = "to-try"
    public var settings: RecipeSettings
    public var shooting: [String: String]? = nil       // iso, exposure_compensation, notes — not stored in a slot
    public var sensors: [String]? = nil
    public var source: Source? = nil
    public var uncertain: [String]? = nil
    public var shots: Int? = nil
    public var cameras: [String]? = nil
    public var firstShot: String? = nil
    public var lastShot: String? = nil
    public var samples: [String]? = nil
    public var notes: String? = nil
    public var tags: [String]? = nil                  // "Leica style", "Warm", "B&W", …

    public struct Source: Codable, Equatable, Sendable {
        public var kind: String                       // reel, website, exif, camera, manual
        public var url: String? = nil
        public var creator: String? = nil
        public var credit: String? = nil
        public var transcript: String? = nil
        public var dateAdded: String? = nil
        public init(kind: String, url: String? = nil, creator: String? = nil, dateAdded: String? = nil) {
            self.kind = kind; self.url = url; self.creator = creator; self.dateAdded = dateAdded
        }
        enum CodingKeys: String, CodingKey { case kind, url, creator, credit, transcript, dateAdded = "date_added" }
    }

    public init(slug: String, name: String, status: String = "to-try", settings: RecipeSettings) {
        self.slug = slug; self.name = name; self.status = status; self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case slug, name, status, settings, shooting, sensors, source, uncertain, shots, cameras, samples, notes, tags
        case firstShot = "first_shot", lastShot = "last_shot"
    }

    /// What's wrong with this recipe for a camera that takes X-Trans V values, as "field=value" strings.
    public var problems: [String] {
        let s = settings
        var out: [String] = []
        func check(_ name: String, _ value: String, _ allowed: [String]) { if !allowed.contains(value) { out.append("\(name)=\(value)") } }
        check("film", s.film, Film.all)
        check("grain_roughness", s.grainRoughness, Values.offWeakStrong)
        check("grain_size", s.grainSize, Values.grainSize)
        check("color_chrome", s.colorChrome, Values.offWeakStrong)
        check("color_chrome_fx_blue", s.colorChromeFxBlue, Values.offWeakStrong)
        check("wb", s.wb, Values.wb)
        check("dynamic_range", s.dynamicRange, Values.dynamicRange)
        check("d_range_priority", s.dRangePriority, Values.dRangePriority)
        check("status", status, Values.status)
        func range(_ name: String, _ v: Double?, _ lo: Double, _ hi: Double, step: Double = 1) {
            guard let v else { out.append("\(name)=null"); return }
            if v < lo || v > hi || (v / step).rounded() != v / step { out.append("\(name)=\(v)") }
        }
        range("wb_red", Double(s.wbRed), -9, 9); range("wb_blue", Double(s.wbBlue), -9, 9)
        range("highlight", s.highlight, -2, 4, step: 0.5); range("shadow", s.shadow, -2, 4, step: 0.5)
        if s.isMonochrome {
            range("mono_warm_cool", s.monoWarmCool.map(Double.init), -9, 9)
            range("mono_magenta_green", s.monoMagentaGreen.map(Double.init), -9, 9)
        } else {
            range("color", s.color.map(Double.init), -4, 4)
        }
        range("sharpness", Double(s.sharpness), -4, 4); range("high_iso_nr", Double(s.highIsoNr), -4, 4)
        range("clarity", Double(s.clarity), -5, 5)
        if s.wb == "Kelvin" { range("wb_kelvin", s.wbKelvin.map(Double.init), 2500, 10000, step: 10) }
        if slug.isEmpty || slug.contains("/") { out.append("slug=\(slug)") }
        return out
    }

    public static func slugify(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
        let parts = folded.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) || !$0.isASCII })
        return parts.joined(separator: "-").prefix(60).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// Library-wide choices (`Library.preferences`, `preferences.json` in the library folder).
public struct Preferences: Codable, Sendable, Equatable {
    /// Clarity other than 0 makes the camera stop for 1–3 s after every shot to store it ("Storing"). Off (the default):
    /// slots are written and photos rendered with Clarity 0. Each recipe keeps its own value, used again once it's on.
    public var clarity = false
    public init(clarity: Bool = false) { self.clarity = clarity }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        clarity = try c.decodeIfPresent(Bool.self, forKey: .clarity) ?? false
    }
    /// Shown wherever Clarity is offered: what turning it on costs.
    public static let clarityCost = "Clarity other than 0 makes the camera stop for 1–3 seconds after every shot to store it."
}

extension RecipeSettings {
    /// What goes to the camera (slots, renders): Clarity 0 unless the owner allows it.
    public func forCamera(_ p: Preferences) -> RecipeSettings {
        var s = self
        if !p.clarity { s.clarity = 0 }
        return s
    }
}
