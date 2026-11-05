import Foundation

/// Camera → library: every slot (C1–C7, FS1–FS3) whose recipe the library doesn't have yet is added as one of the
/// owner's own recipes ("mine"), named after the slot's name on the camera, and the photos the owner shot with it
/// (their Fujifilm JPEGs' EXIF, Mac only) become its samples. Recipes already in the library that have no photos yet
/// get them too. Nothing is removed or renamed; two slots with the same settings make one recipe.
public enum SlotSync {
    public struct SlotContents: Sendable {
        public var slot: String; public var name: String; public var settings: RecipeSettings; public var dial: Bool
        public init(slot: String, name: String, settings: RecipeSettings, dial: Bool) {
            self.slot = slot; self.name = name; self.settings = settings; self.dial = dial
        }
    }

    /// The owner's photos with one recipe (from their JPEGs' EXIF: `ExifImport.groups` on the Mac).
    public struct Photos: Sendable {
        public var settings: RecipeSettings; public var files: [String]; public var cameras: Set<String>; public var dates: [String]
        public init(settings: RecipeSettings, files: [String], cameras: Set<String>, dates: [String]) {
            self.settings = settings; self.files = files; self.cameras = cameras; self.dates = dates
        }
    }

    public struct Report: Sendable {
        public var added: [Recipe] = []                 // new recipes, in slot order
        public var photosFor: [String: Int] = [:]       // recipe slug → photos attached now
        public var known: [(slot: String, slug: String)] = []
        public var summary: String {
            let photos = photosFor.values.reduce(0, +)
            var parts: [String] = []
            if !added.isEmpty {
                parts.append("Added \(added.count) recipe\(added.count == 1 ? "" : "s") from your camera: " + added.map(\.name).joined(separator: ", "))
            }
            if photos > 0 { parts.append("\(photos) of your photos shot with \(photosFor.count == 1 ? "it" : "them")") }
            return parts.isEmpty ? "Every recipe on your camera is already in your library" : parts.joined(separator: " · ")
        }
    }

    /// Plans and (unless `dryRun`) writes the sync. `photos`: groups of the owner's JPEGs by recipe (`ExifImport.groups`
    /// on the Mac, via `photos(…)`); nil on iPhone / iPad, where the recipes come without photos. `camera`: the model, for notes.
    @discardableResult
    public static func run(_ slots: [SlotContents], library: Library, camera: String, photos: [Photos]? = nil,
                           dryRun: Bool = false) throws -> Report {
        var report = Report()
        var seen: [RecipeSettings: String] = [:]          // settings → slug made in this run
        let today = Date().day
        for s in slots where !(s.settings == RecipeSettings.factory && s.name.isEmpty) {
            var settings = s.settings; settings.normalize()
            if let r = library.matchOnCamera(settings, dial: s.dial)?.recipe ?? seen[settings].flatMap({ try? library.recipe($0) }) {
                report.known.append((s.slot, r.slug))
                if (r.samples ?? []).isEmpty, let g = group(for: settings, dial: s.dial, in: photos), !dryRun {
                    var u = r; attach(g, to: &u)
                    if u.status == "to-try" || u.status == "tried" { u.status = "mine" }
                    try library.save(u, allowDuplicate: true)
                    report.photosFor[u.slug] = g.files.count
                }
                continue
            }
            if let slug = seen[settings] { report.known.append((s.slot, slug)); continue }
            let g = group(for: settings, dial: s.dial, in: photos)
            var uncertain: [String] = []
            if s.dial {
                // FS1–FS3: the WB shift (and B&W toning) aren't read from the settings file yet; the owner's photos have them.
                if let g { settings.wbRed = g.settings.wbRed; settings.wbBlue = g.settings.wbBlue
                           settings.monoWarmCool = g.settings.monoWarmCool; settings.monoMagentaGreen = g.settings.monoMagentaGreen }
                else { uncertain = settings.isMonochrome ? ["mono_warm_cool", "mono_magenta_green"] : ["wb_red", "wb_blue"] }
            }
            // A recipe of that name that's set differently (changed on the camera): keep both, say how they differ.
            var title = name(s), differs = ""
            if let same = ((try? library.recipes()) ?? []).first(where: { $0.name.lowercased() == title.lowercased() }) {
                title += " (on camera)"
                differs = " Differs from “\(same.name)”: " + same.settings.differences(to: settings).joined(separator: ", ") + "."
            }
            var r = Recipe(slug: uniqueSlug(title, library: library, taken: Set(seen.values)), name: title, status: "mine", settings: settings)
            r.source = .init(kind: "camera", dateAdded: today)
            r.notes = "From \(s.slot) on your \(camera), \(today)." + differs
                + (uncertain.isEmpty ? "" : " WB shift / toning not read from the dial position yet: check on the camera.")
            if !uncertain.isEmpty { r.uncertain = uncertain }
            if let g { attach(g, to: &r); report.photosFor[r.slug] = g.files.count }
            if !dryRun { r = try library.save(r, allowDuplicate: true) }
            seen[s.settings.normalized] = r.slug
            seen[settings] = r.slug
            report.added.append(r)
            report.known.append((s.slot, r.slug))
        }
        return report
    }

    /// Later photos: recipes that came from the camera and still have none get the owner's photos shot with them (a
    /// memory card inserted after the camera was read). Returns recipe slug → photos attached.
    @discardableResult
    public static func fillPhotos(library: Library, photos: [Photos]) throws -> [String: Int] {
        var out: [String: Int] = [:]
        for r in try library.recipes() where r.source?.kind == "camera" && (r.samples ?? []).isEmpty {
            let fromDial = r.uncertain?.isEmpty == false
            guard let g = group(for: r.settings.normalized, dial: fromDial, in: photos) else { continue }
            var u = r; attach(g, to: &u)
            if fromDial { u.settings.wbRed = g.settings.wbRed; u.settings.wbBlue = g.settings.wbBlue
                          u.settings.monoWarmCool = g.settings.monoWarmCool; u.settings.monoMagentaGreen = g.settings.monoMagentaGreen
                          u.uncertain = nil }
            try library.save(u, allowDuplicate: true)
            out[u.slug] = g.files.count
        }
        return out
    }

    /// Undo for the app's toast: removes recipes this sync added (only if they're still as added).
    public static func undo(_ added: [Recipe], library: Library) {
        for r in added {
            let file = library.root.appendingPathComponent("recipes/\(r.slug).json")
            if let now = try? library.recipe(r.slug), now.slug == r.slug, now.settings == r.settings { try? FileManager.default.removeItem(at: file) }
        }
        try? library.writeIndex()
    }

    /// The camera's names are capitals ("GREEN ACROS"): kept as words ("Green Acros"); FS positions have none.
    static func name(_ s: SlotContents) -> String {
        let n = s.name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "\(s.settings.film) (\(s.slot))" }
        return n == n.uppercased() ? n.lowercased().capitalized : n
    }

    static func uniqueSlug(_ name: String, library: Library, taken: Set<String>) -> String {
        let base = Recipe.slugify(name)
        var slug = base, n = 2
        while taken.contains(slug) || (try? library.recipe(slug))?.slug == slug { slug = "\(base)-\(n)"; n += 1 }
        return slug
    }

    /// The owner's photos shot with these settings: an exact match, or for FS positions the same recipe whatever its WB
    /// shift / toning (the most-shot one).
    static func group(for s: RecipeSettings, dial: Bool, in groups: [Photos]?) -> Photos? {
        guard let groups else { return nil }
        if let g = groups.first(where: { $0.settings.normalized == s }) { return g }
        guard dial else { return nil }
        func loose(_ x: RecipeSettings) -> RecipeSettings {
            var y = x.normalized; y.wbRed = 0; y.wbBlue = 0
            if y.isMonochrome { y.monoWarmCool = 0; y.monoMagentaGreen = 0 }
            return y
        }
        return groups.filter { loose($0.settings) == loose(s) }.max { $0.files.count < $1.files.count }
    }

    static func attach(_ g: Photos, to r: inout Recipe) {
        let step = Swift.max(1, g.files.count / 6)
        r.samples = Array(stride(from: 0, to: g.files.count, by: step).map { g.files[$0] }.prefix(6))
        r.shots = g.files.count
        r.cameras = g.cameras.sorted()
        r.firstShot = g.dates.min(); r.lastShot = g.dates.max()
    }
}

extension RecipeSettings {
    /// A slot nobody has set: Provia, everything at 0 / Off / Auto.
    public static var factory: RecipeSettings { var s = RecipeSettings(); s.normalize(); return s }
    var normalized: RecipeSettings { var s = self; s.normalize(); return s }
}

#if os(macOS)
extension SlotSync {
    /// The owner's Fujifilm JPEGs grouped by recipe: the given folders, else every one Spotlight knows plus any memory
    /// card that's mounted (Spotlight doesn't index cards). Needs exiftool; nil without it.
    public static func photos(in folders: [String]? = nil) -> [Photos]? {
        let files = folders.map { ExifImport.files(in: $0) } ?? Array(Set(ExifImport.spotlightFiles() + ExifImport.files(in: cardFolders())))
        guard let groups = try? ExifImport.groups(files: files) else { return nil }
        return groups.map { Photos(settings: $0.settings, files: $0.files, cameras: $0.cameras, dates: $0.dates) }
    }

    /// DCIM folders of mounted volumes (memory cards, a camera in card reader mode).
    public static func cardFolders(_ volumes: [URL]? = nil) -> [String] {
        let vols = volumes ?? ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? [])
        return vols.map { $0.appendingPathComponent("DCIM").path }.filter { FileManager.default.fileExists(atPath: $0) }
    }
}
#endif
