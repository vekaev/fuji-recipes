#if os(macOS)
import Foundation

/// Finds the recipes the owner actually shot with: every Fujifilm JPEG stores the full recipe in its MakerNote.
/// Reads them with exiftool (brew install exiftool), groups photos with identical settings.
public enum ExifImport {
    public struct Group: Sendable {
        public var settings: RecipeSettings
        public var files: [String]
        public var cameras: Set<String>
        public var dates: [String]
    }

    static let tags = ["Model", "FilmMode", "Saturation", "GrainEffectRoughness", "GrainEffectSize", "ColorChromeEffect",
                       "ColorChromeFXBlue", "WhiteBalance", "WhiteBalanceFineTune", "ColorTemperature", "DynamicRangeSetting",
                       "DevelopmentDynamicRange", "DRangePriority", "DRangePriorityFixed", "HighlightTone", "ShadowTone",
                       "Sharpness", "NoiseReduction", "Clarity", "BWAdjustment", "BWMagentaGreen", "DateTimeOriginal"]
    static let film: [(String, String)] = [("provia", "Provia"), ("standard", "Provia"), ("velvia", "Velvia"), ("astia", "Astia"),
        ("classic chrome", "Classic Chrome"), ("reala", "Reala Ace"), ("pro neg. hi", "Pro Neg. Hi"), ("pro neg. std", "Pro Neg. Std"),
        ("pro neg. standard", "Pro Neg. Std"), ("classic neg", "Classic Neg."), ("nostalgic", "Nostalgic Neg."),
        ("bleach", "Eterna Bleach Bypass"), ("eterna", "Eterna")]
    // Fujifilm stores the monochrome simulations in the Saturation tag.
    static let mono: [(String, String)] = [("acros red", "Acros+R"), ("acros yellow", "Acros+Ye"), ("acros green", "Acros+G"),
        ("acros", "Acros"), ("b&w red", "Monochrome+R"), ("b&w yellow", "Monochrome+Ye"), ("b&w green", "Monochrome+G"),
        ("b&w sepia", "Sepia"), ("sepia", "Sepia"), ("none (b&w)", "Monochrome"), ("b&w", "Monochrome")]
    static let sharp = ["softest": -4, "very soft": -3, "soft": -2, "medium soft": -1, "normal": 0, "medium hard": 1,
                        "hard": 2, "very hard": 3, "hardest": 4]

    static func lookup(_ text: Any?, _ table: [(String, String)]) -> String? {
        let t = "\(text ?? "")".lowercased()
        return table.first { t.contains($0.0) }?.1
    }

    /// "-2 (soft)" → -2, "+1.5" → 1.5, "Normal" → 0.
    static func number(_ v: Any?) -> Double {
        if let n = v as? NSNumber { return n.doubleValue }
        let text = "\(v ?? "")"
        if let r = text.range(of: #"^\s*[+-]?\d+(\.\d+)?"#, options: .regularExpression) {
            return Double(text[r].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    /// One photo's EXIF → settings, or nil for a JPEG without a recipe (converted, edited, another brand).
    public static func settings(_ r: [String: Any]) -> RecipeSettings? {
        guard let filmName = lookup(r["Saturation"], mono) ?? lookup(r["FilmMode"], film), r["GrainEffectRoughness"] != nil else { return nil }
        var s = RecipeSettings()
        s.film = filmName
        s.grainRoughness = "\(r["GrainEffectRoughness"] ?? "Off")"
        s.grainSize = "\(r["GrainEffectSize"] ?? "Off")"
        s.colorChrome = "\(r["ColorChromeEffect"] ?? "Off")"
        s.colorChromeFxBlue = "\(r["ColorChromeFXBlue"] ?? "Off")"
        let wb = "\(r["WhiteBalance"] ?? "Auto")"
        s.wb = wb.lowercased().contains("kelvin") ? "Kelvin" : wb
        if s.wb == "Kelvin" { s.wbKelvin = Int(number(r["ColorTemperature"])) }
        let fine = "\(r["WhiteBalanceFineTune"] ?? "")".matches(#"[+-]?\d+"#)
        if fine.count > 1 { s.wbRed = (Int(fine[0]) ?? 0) / 20; s.wbBlue = (Int(fine[1]) ?? 0) / 20 }   // stored ×20
        s.dynamicRange = "\(r["DynamicRangeSetting"] ?? "")".lowercased() == "auto" ? "Auto" : "DR\(Int(number(r["DevelopmentDynamicRange"] ?? 100)))"
        let drp = "\(r["DRangePriority"] ?? "")".lowercased()
        if !drp.isEmpty, drp != "off", drp != "n/a" { s.dRangePriority = drp == "auto" ? "Auto" : "\(r["DRangePriorityFixed"] ?? "Strong")" }
        s.highlight = number(r["HighlightTone"]); s.shadow = number(r["ShadowTone"])
        if s.isMonochrome {
            s.monoWarmCool = Int(number(r["BWAdjustment"])); s.monoMagentaGreen = Int(number(r["BWMagentaGreen"]))
        } else {
            s.color = Int(number(r["Saturation"]))
        }
        let sh = "\(r["Sharpness"] ?? "normal")".lowercased()
        s.sharpness = sharp[sh] ?? Int(number(sh))
        s.highIsoNr = Int(number(r["NoiseReduction"]))
        s.clarity = Int(number(r["Clarity"]))
        s.normalize()
        return s
    }

    public static func spotlightFiles() -> [String] {
        let out = run("/usr/bin/mdfind", ["kMDItemAcquisitionMake == \"FUJIFILM\""])
        return out.split(separator: "\n").map(String.init).filter { ["jpg", "jpeg"].contains(($0 as NSString).pathExtension.lowercased()) }
    }

    public static func files(in folders: [String]) -> [String] {
        folders.flatMap { folder -> [String] in
            let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
            let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            return (e?.allObjects as? [URL] ?? []).filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }.map(\.path)
        }
    }

    public static func exiftool() -> String? {
        ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func groups(files: [String]) throws -> [Group] {
        guard let tool = exiftool() else { throw CameraError("exiftool isn't installed. Run: brew install exiftool") }
        guard !files.isEmpty else { return [] }
        let list = FileManager.default.temporaryDirectory.appendingPathComponent("fuji-exif-\(UUID().uuidString).txt")
        try files.joined(separator: "\n").write(to: list, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: list) }
        let json = run(tool, ["-j", "-@", list.path] + tags.map { "-\($0)" })
        let rows = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] ?? []
        var byKey: [RecipeSettings: Group] = [:]
        for row in rows {
            guard let s = settings(row), let file = row["SourceFile"] as? String else { continue }
            var g = byKey[s] ?? Group(settings: s, files: [], cameras: [], dates: [])
            g.files.append(file)
            g.cameras.insert("\(row["Model"] ?? "?")")
            if let d = row["DateTimeOriginal"] { g.dates.append(String("\(d)".prefix(10)).replacingOccurrences(of: ":", with: "-")) }
            byKey[s] = g
        }
        return byKey.values.sorted { $0.files.count > $1.files.count }
    }

    /// Files the groups with at least `min` shots: a recipe with the same settings is updated (shots, cameras, dates,
    /// samples, status mine), otherwise a new recipe named after its film is added. Returns "added …" / "updated …".
    public static func importGroups(_ groups: [Group], into library: Library, min: Int) throws -> [String] {
        var report: [String] = []
        for g in groups where g.files.count >= min {
            let step = Swift.max(1, g.files.count / 6)
            let samples = Array(stride(from: 0, to: g.files.count, by: step).map { g.files[$0] }.prefix(6))
            var r: Recipe
            if let existing = library.match(g.settings) {
                r = existing
                if r.status == "to-try" || r.status == "tried" { r.status = "mine" }
                report.append("updated \(r.slug) (\(g.files.count) shots)")
            } else {
                let hash = stableHash(g.settings)
                r = Recipe(slug: "\(Recipe.slugify(g.settings.film))-\(hash)", name: "\(g.settings.film) (\(g.files.count) shots)", status: "mine", settings: g.settings)
                r.source = .init(kind: "exif", dateAdded: Date().day)
                report.append("added \(r.slug) (\(g.files.count) shots) — give it a name")
            }
            r.shots = g.files.count
            r.cameras = g.cameras.sorted()
            r.firstShot = g.dates.min(); r.lastShot = g.dates.max()
            r.samples = samples
            try library.save(r, allowDuplicate: true)
        }
        return report
    }

    /// 6 hex digits from the settings JSON (FNV-1a), the same on every run.
    static func stableHash(_ s: RecipeSettings) -> String {
        let data = (try? Library.encoder.encode(s)) ?? Data()
        var h: UInt32 = 2166136261
        for b in data { h = (h ^ UInt32(b)) &* 16777619 }
        return String(String(h, radix: 16).prefix(6))
    }

    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    func matches(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self).map { String(self[$0]) } }
    }
}
#endif
