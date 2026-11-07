import Foundation

/// A named set of recipes for the slots ("Iceland", "City nights"), written to the camera in one go.
public struct Kit: Codable, Equatable, Sendable {
    public var slug: String
    public var name: String
    public var slots: [String: String]      // "C1": recipe slug
    public var notes: String?
    public init(slug: String, name: String, slots: [String: String], notes: String? = nil) {
        self.slug = slug; self.name = name; self.slots = slots; self.notes = notes
    }
}

/// Every slot of a camera at one moment, saved before any write.
public struct Snapshot: Codable, Sendable {
    public var date: String
    public var reason: String
    public var camera: DeviceInfo
    public var banks: [Bank]
    public init(date: String, reason: String, camera: DeviceInfo, banks: [Bank]) {
        self.date = date; self.reason = reason; self.camera = camera; self.banks = banks
    }
}

/// The recipe library: `$FUJI_RECIPES` or ~/Documents/FujiRecipes. Shared with the `/recipe` skill and the app.
///   recipes/<slug>.json   kits/<slug>.json   backups/<date>-<model>.json   library.md (generated)
public struct Library: Sendable {
    public let root: URL
    public init(root: URL? = nil) {
        if let root { self.root = root; return }
        if let env = ProcessInfo.processInfo.environment["FUJI_RECIPES"], !env.isEmpty {
            self.root = URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        } else {
            self.root = Library.defaultRoot
        }
    }

    /// iCloud Drive ▸ Fuji Recipes when iCloud Drive is on (so iPhone, iPad, Claude and /recipe share it), else
    /// ~/Documents/FujiRecipes. On iOS the app passes the folder the owner picked; this is only a fallback there.
    public static var defaultRoot: URL {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let cloudLibrary = iCloud.appendingPathComponent("Fuji Recipes")
        let local = home.appendingPathComponent("Documents/FujiRecipes")
        if FileManager.default.fileExists(atPath: cloudLibrary.path) { return cloudLibrary }
        if FileManager.default.fileExists(atPath: iCloud.path), !FileManager.default.fileExists(atPath: local.path) { return cloudLibrary }
        return local
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Fuji Recipes")
        #endif
    }

    var recipesDir: URL { root.appendingPathComponent("recipes") }
    var kitsDir: URL { root.appendingPathComponent("kits") }
    var backupsDir: URL { root.appendingPathComponent("backups") }
    public var indexFile: URL { root.appendingPathComponent("library.md") }
    var preferencesFile: URL { root.appendingPathComponent("preferences.json") }

    /// Choices shared by the app (Mac, iPhone, iPad), the `fuji` CLI and its MCP server: they live in the library
    /// folder, so iCloud carries them to every device.
    public var preferences: Preferences {
        (try? Data(contentsOf: preferencesFile)).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }

    public func setPreferences(_ p: Preferences) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Library.encoder.encode(p).write(to: preferencesFile, options: .atomic)
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try Self.encoder.encode(value)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private func files(in dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: Recipes

    public func recipes() throws -> [Recipe] {
        try files(in: recipesDir).map { url in
            do { return try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: url)) }
            catch { throw CameraError("\(url.lastPathComponent) can't be read: \(error)") }
        }
    }

    /// By slug, then by name (case-insensitive), then by a unique prefix of either.
    public func recipe(_ query: String) throws -> Recipe {
        let all = try recipes(), q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if let r = all.first(where: { $0.slug == q }) ?? all.first(where: { $0.name.lowercased() == q }) { return r }
        let hits = all.filter { $0.slug.hasPrefix(q) || $0.name.lowercased().hasPrefix(q) || $0.name.lowercased().contains(q) }
        if hits.count == 1 { return hits[0] }
        if hits.isEmpty { throw CameraError("No recipe matches \"\(query)\". fuji_recipes lists them.") }
        throw CameraError("\"\(query)\" matches \(hits.count) recipes: \(hits.map(\.slug).joined(separator: ", ")).")
    }

    /// The library recipe with exactly these settings, if any.
    public func match(_ settings: RecipeSettings) -> Recipe? {
        var s = settings; s.normalize()
        return (try? recipes())?.first { var t = $0.settings; t.normalize(); return t == s }
    }

    /// The recipe with these settings, also when Clarity was left out (0) because it slows saving: photos shot with a
    /// recipe while Clarity was off still belong to it.
    public func match(_ settings: RecipeSettings, clarityOff: Bool) -> Recipe? {
        if let r = match(settings) { return r }
        guard clarityOff else { return nil }
        var s = settings; s.normalize()
        guard s.clarity == 0 else { return nil }
        return (try? recipes())?.first { var t = $0.settings; t.normalize(); t.clarity = 0; return t == s }
    }

    /// The recipe a slot holds, allowing the differences the camera imposes (see `cameraLimitedDifferences`):
    /// an exact match first, else the closest recipe that differs only there, with what differs.
    public func matchOnCamera(_ settings: RecipeSettings, dial: Bool = false) -> (recipe: Recipe, notes: [String])? {
        if let r = match(settings) { return (r, []) }
        let all = (try? recipes()) ?? []
        return all.compactMap { r in r.settings.cameraLimitedDifferences(settings, dial: dial).map { (r, $0) } }
            .min { $0.1.count < $1.1.count }
    }

    /// Saves a recipe after checking it. Same settings as another recipe → refused unless `allowDuplicate`, naming it.
    @discardableResult
    public func save(_ input: Recipe, allowDuplicate: Bool = false) throws -> Recipe {
        var r = input
        if r.slug.isEmpty { r.slug = Recipe.slugify(r.name) }
        r.settings.normalize()
        let problems = r.problems
        guard problems.isEmpty else { throw CameraError("\(r.slug): the camera can't take \(problems.joined(separator: ", ")). See fuji_guide.") }
        if !allowDuplicate, let twin = match(r.settings), twin.slug != r.slug {
            throw CameraError("Same settings as \"\(twin.name)\" (\(twin.slug)). Add this source to that recipe's notes instead, or pass allowDuplicate.")
        }
        try write(r, to: recipesDir.appendingPathComponent("\(r.slug).json"))
        try writeIndex()
        return r
    }

    public func setStatus(_ query: String, status: String, note: String?) throws -> Recipe {
        guard Values.status.contains(status) else { throw CameraError("status must be one of \(Values.status.joined(separator: ", "))") }
        var r = try recipe(query)
        r.status = status
        if let note, !note.isEmpty { r.notes = [r.notes, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n") }
        return try save(r, allowDuplicate: true)
    }

    // MARK: Kits

    public func kits() throws -> [Kit] { try files(in: kitsDir).map { try JSONDecoder().decode(Kit.self, from: Data(contentsOf: $0)) } }

    public func kit(_ query: String) throws -> Kit {
        let q = query.lowercased()
        guard let k = try kits().first(where: { $0.slug == q || $0.name.lowercased() == q }) else { throw CameraError("No kit called \"\(query)\". fuji_kits lists them.") }
        return k
    }

    @discardableResult
    public func save(_ kit: Kit) throws -> Kit {
        var k = kit
        if k.slug.isEmpty { k.slug = Recipe.slugify(k.name) }
        for (slot, slug) in k.slots {
            guard slot.range(of: #"^C[1-7]$"#, options: .regularExpression) != nil else { throw CameraError("\(slot) isn't a custom slot (C1…C7).") }
            k.slots[slot] = try recipe(slug).slug
        }
        try write(k, to: kitsDir.appendingPathComponent("\(k.slug).json"))
        return k
    }

    // MARK: Backups

    public func saveBackup(_ snapshot: Snapshot) throws -> URL {
        let safe = Recipe.slugify(snapshot.camera.model.isEmpty ? "camera" : snapshot.camera.model)
        let stamp = snapshot.date.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "T", with: "-").prefix(17)
        var url = backupsDir.appendingPathComponent("\(stamp)-\(safe).json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {   // two backups in the same second
            url = backupsDir.appendingPathComponent("\(stamp)-\(safe)-\(n).json"); n += 1
        }
        try write(snapshot, to: url)
        return url
    }

    public func backups() -> [URL] { files(in: backupsDir).reversed() }

    public func backup(_ name: String) throws -> Snapshot {
        let url = backups().first { $0.lastPathComponent == name || $0.deletingPathExtension().lastPathComponent == name }
            ?? (name == "latest" ? backups().first : nil)
        guard let url else { throw CameraError("No backup \"\(name)\". fuji_backups lists them.") }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
    }

    // MARK: Index

    /// Rebuilds library.md: one table per status, most-shot first.
    public func writeIndex() throws {
        let all = try recipes()
        var out = ["# Fujifilm recipes", "",
                   "\(all.count) recipes. Generated from `recipes/*.json` by fuji; edit those, not this file.", ""]
        let head = "| Name | Film | Grain | CC / FX Blue | White balance | Tone | Color | Sharp / NR / Clarity | Shots | Source | File |\n|---|---|---|---|---|---|---|---|---|---|---|"
        for status in Values.status {
            let rows = all.filter { $0.status == status }.sorted { ($0.shots ?? 0, $1.name) > ($1.shots ?? 0, $0.name) }
            guard !rows.isEmpty else { continue }
            out += ["## \(status.replacingOccurrences(of: "-", with: " ").capitalized) (\(rows.count))", "", head]
            out += rows.map(Self.row)
            out.append("")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try out.joined(separator: "\n").write(to: indexFile, atomically: true, encoding: .utf8)
    }

    static func row(_ r: Recipe) -> String {
        let s = r.settings
        let wb = (s.wb == "Kelvin" ? "\(s.wbKelvin ?? 0)K" : s.wb) + " R\(signed(s.wbRed)) B\(signed(s.wbBlue))"
        let tone = s.dRangePriority != "Off" ? "DRP \(s.dRangePriority)" : "\(s.dynamicRange) H\(signed(s.highlight)) S\(signed(s.shadow))"
        let grain = s.grainRoughness == "Off" ? "off" : "\(s.grainRoughness) \(s.grainSize)"
        let color = s.color.map { "Col \(signed($0))" } ?? "WC\(signed(s.monoWarmCool ?? 0)) MG\(signed(s.monoMagentaGreen ?? 0))"
        let source: String
        if let url = r.source?.url { source = "[\(r.source?.creator ?? r.source?.kind ?? "link")](\(url))" } else { source = r.source?.kind ?? "" }
        return "| \(r.name) | \(s.film) | \(grain) | \(s.colorChrome) / \(s.colorChromeFxBlue) | \(wb) | \(tone) | \(color) | \(signed(s.sharpness)) / \(signed(s.highIsoNr)) / \(signed(s.clarity)) | \(r.shots.map(String.init) ?? "") | \(source) | `\(r.slug)` |"
    }
}

public extension Date {
    var isoStamp: String {
        let f = ISO8601DateFormatter(); f.timeZone = .current; f.formatOptions = [.withInternetDateTime]
        return f.string(from: self)
    }
    var day: String { String(isoStamp.prefix(10)) }
}
