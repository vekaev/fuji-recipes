import FujiKit
import Foundation
import ImageIO
import Observation
import SwiftUI

/// Everything the window shows, on Mac, iPhone and iPad: the recipe library as looks, the camera's slots with staged
/// changes and their history, and the inbox. Camera I/O goes through FujiKit, like `fuji mcp`.
/// The only camera write path is `writeChanges()`: backup of every slot → write each changed slot → read back →
/// record in the slot history.
@MainActor @Observable
final class AppModel {
    enum Tab: String, CaseIterable, Identifiable { case looks, camera, studio, inbox; var id: String { rawValue } }
    enum Sheet: String, Identifiable { case help, trouble, backups, review, settings, slot, connect; var id: String { rawValue } }

    struct Slot: Identifiable, Equatable {
        let id: String           // "C1" … "C7", "FS1" … "FS3"
        let index: Int
        let dial: Bool           // FS1–FS3: written through the settings file (ADR 0004)
        var camName: String
        var cam: RecipeSettings
        var name: String
        var draft: RecipeSettings
        var changed: Bool { draft != cam || (!dial && name != camName) }
        var unused: Bool { cam == RecipeSettings.factory && camName.isEmpty }
    }

    /// `recipes`: the Studio's preview knows which recipe each photo is (nil = as shot), so it can fetch a full-size
    /// render of the one shown and pick / favorite it.
    struct Preview: Equatable {
        var title: String; var paths: [String]; var index: Int; var titles: [String]? = nil
        var recipes: [String?]? = nil
    }

    var tab: Tab = .looks
    var sheet: Sheet?
    var pickingLibrary = false      // iPhone / iPad: the Files picker for the library folder
    var preview: Preview?
    var library: Library
    var recipes: [Recipe] = []
    var tagFilter: String?          // nil = all; "status:mine", "status:to-try", "status:favorite" or a tag
    var selectedRecipe: String?
    var settingsFor: String?        // recipe slug whose settings sheet is open

    // Camera
    var steps: [Doctor.Step] = []
    var appsHolding: [String] = []
    var info: DeviceInfo?
    var connectedAt: Date?
    var slots: [Slot] = []
    var selectedSlot = "C1"
    var editing = false
    var busy: String?
    var toast: String?
    var backupCount = 0
    var history: [String: [SlotRecord]] = [:]
    var connected: Bool { info != nil && !slots.isEmpty }
    var changes: [Slot] { slots.filter(\.changed) }
    /// Off (the default): a look put in a slot, Put back or a dial edit is written right away (a backup of that slot
    /// first, read back after, Undo in the toast). On: changes wait for the review sheet.
    var askBeforeWriting = UserDefaults.standard.bool(forKey: "askBeforeWriting") {
        didSet { UserDefaults.standard.set(askBeforeWriting, forKey: "askBeforeWriting") }
    }
    /// Camera → library when the camera connects (on by default): recipes on the camera that the library doesn't have are
    /// added with the photos shot with them (`SlotSync`).
    var syncSlots = UserDefaults.standard.object(forKey: "syncSlots") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncSlots, forKey: "syncSlots") }
    }
    var syncingSlots = false
    /// Library-wide choices (`preferences.json` in the library, shared with the iPhone and the `fuji` tool).
    private(set) var preferences = Preferences()
    /// Clarity other than 0 makes the camera stop 1–3 s after every shot to store it. Off (the default): slots get
    /// Clarity 0 and Studio renders use 0; recipes keep their value. Turning it on asks first (`confirmClarity`).
    var clarityOn: Bool { preferences.clarity }
    var confirmClarity = false
    var toastAction: ToastAction?
    /// Runs when a sheet closes without its own button (Esc, a click outside, a swipe down): the recipe page saves.
    var sheetWillClose: (() -> Void)?
    func closeSheet() {
        let hook = sheetWillClose
        sheetWillClose = nil
        hook?()
        sheet = nil
    }
    struct ToastAction { let title: String; let run: () -> Void }
    private var writeTask: Task<Void, Never>?
    private var writing = false
    private var writeAgain = false

    // Inbox
    var inbox: [InboxItem] = []

    private var checking = false
    private var toastTask: Task<Void, Never>?

    init(library: Library = Library()) { self.library = library }

    /// UI tests (`-uiTesting`): a throwaway library with three recipes, sample photos and a RAW, the simulated X-E5,
    /// instant writes. Nothing touches the owner's library or camera.
    static func uiTestLibrary() -> Library? {
        guard CommandLine.arguments.contains("-uiTesting") else { return nil }
        let noCamera = CommandLine.arguments.contains("-noCamera")    // a test of what works without the camera
        Cameras.shared.simulate = !noCamera
        UserDefaults.standard.set(false, forKey: "askBeforeWriting")
        UserDefaults.standard.set(false, forKey: "syncSlots")   // a test turns it on with -syncSlots YES
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fuji-uitest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: root)
        let lib = Library(root: root)
        let seeds: [(String, String, Int, String)] = [("UI Chrome", "Classic Chrome", 2, "favorite"), ("UI Acros", "Acros+R", 0, "to-try"), ("UI Neg", "Classic Neg.", 4, "to-try")]
        for (name, film, color, status) in seeds {
            var s = RecipeSettings(); s.film = film; s.color = color
            if name == "UI Neg" { s.clarity = -2 }   // Clarity off by default: written as 0 (testClaritySwitch)
            s.normalize()
            var r = Recipe(slug: "", name: name, status: status, settings: s); r.tags = film.hasPrefix("Acros") ? ["B&W"] : ["Warm"]
            if let saved = try? lib.save(r, allowDuplicate: true) {
                let dir = root.appendingPathComponent("samples/\(saved.slug)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var p = ConversionProfile(Data(count: ConversionProfile.base + 4 * 29)); p[8] = Int32(Film.all.firstIndex(of: film)! + 1); p[18] = Int32(color * 10)
                try? SimulatedCamera.renderJPEG(p, full: true).write(to: dir.appendingPathComponent("1.jpg"))
            }
        }
        let raw = root.appendingPathComponent("studio/DSCF0001.RAF")
        try? FileManager.default.createDirectory(at: raw.deletingLastPathComponent(), withIntermediateDirectories: true)
        var rafData = Data("FUJIFILMCCD-RAW 0201FF383501X-E5".utf8) + Data(count: 4000)
        let bigPreview = Self.uiTestPreview()   // the JPEG inside a real RAF: its offset and length at bytes 84 and 88
        rafData.replaceSubrange(84..<92, with: [UInt32(rafData.count), UInt32(bigPreview.count)].flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * $0)) } })
        try? (rafData + bigPreview).write(to: raw)
        if noCamera, let r = (try? lib.recipes())?.first(where: { $0.status == "favorite" }) {
            var p = ConversionProfile(Data(count: ConversionProfile.base + 4 * 29)); p[8] = 2
            _ = try? RenderCache(library: lib).store(SimulatedCamera.renderJPEG(p, full: false), raw: raw, settings: r.settings)
        }
        UserDefaults.standard.set(raw.path, forKey: "studioRaw")
        // Match a look: a reference photo developed (by the simulated camera) with a recipe the library doesn't have.
        let ref = root.appendingPathComponent("studio/looks/Leica street.jpg")
        try? FileManager.default.createDirectory(at: ref.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lp = ConversionProfile(Data(count: ConversionProfile.base + 4 * 29))
        lp[8] = Int32(Film.all.firstIndex(of: "Classic Chrome")! + 1); lp[13] = 3; lp[14] = -3; lp[16] = -10; lp[17] = 10
        try? SimulatedCamera.renderJPEG(lp, full: true).write(to: ref)
        UserDefaults.standard.set(ref.path, forKey: "lookReference")
        UserDefaults.standard.set("recipes", forKey: "studioMode")
        return lib
    }

    private static func uiTestPreview() -> Data {
        let c = CGContext(data: nil, width: 1500, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(CGColor(gray: 0.5, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1500, height: 1000))
        c.setFillColor(CGColor(gray: 0.8, alpha: 1)); for x in stride(from: 0, to: 1500, by: 8) { c.fill(CGRect(x: x, y: 0, width: 3, height: 1000)) }
        let out = NSMutableData()
        guard let img = c.makeImage(), let d = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
        return out as Data
    }

    // MARK: Start, detect, read

    func start() {
        reload()
        if studioRaw == nil, let p = UserDefaults.standard.string(forKey: "studioRaw"), FileManager.default.fileExists(atPath: p) {
            studioRaw = URL(fileURLWithPath: p)
        }
        if lookReference == nil, let p = UserDefaults.standard.string(forKey: "lookReference"), FileManager.default.fileExists(atPath: p) {
            lookReference = URL(fileURLWithPath: p)
        }
        CameraBrowser.shared.onChange = { [weak self] _, _ in Task { @MainActor in await self?.check() } }
        CameraBrowser.shared.start()
        Task { await check() }
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                if !self.connected { await self.check() }
                self.reloadInbox()
            }
        }
    }

    func use(_ library: Library) {
        self.library = library
        reload()
    }

    func reload() {
        preferences = library.preferences
        recipes = ((try? library.recipes()) ?? []).sorted { a, b in
            (a.lastShot ?? "", a.shots ?? 0, b.name) > (b.lastShot ?? "", b.shots ?? 0, a.name)
        }
        if selectedRecipe == nil { selectedRecipe = recipes.first?.slug }
        reloadInbox()
    }

    func reloadInbox() {
        let fresh = library.inbox()
        if fresh != inbox { inbox = fresh; if fresh.contains(where: { $0.status == .read }) { recipes = (try? library.recipes()) ?? recipes } }
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let report = await Doctor.run()
        steps = report.steps
        appsHolding = report.apps
        let ready = report.steps.count >= 5 && report.steps.allSatisfy(\.ok)
        if ready, !connected { await readCamera() }
        if !ready, info != nil {
            info = nil; slots = []; editing = false; connectedAt = nil
            if sheet == .slot { sheet = nil }
            say("Camera disconnected")
        }
    }

    func readCamera() async {
        guard let cam = await Cameras.shared.current() else { return }
        busy = "Reading the camera…"
        defer { busy = nil }
        do {
            let i = try await cam.deviceInfo()
            let banks = try await cam.readAll()
            _ = try library.saveBackup(Snapshot(date: Date().isoStamp, reason: "On connect", camera: i, banks: banks))
            var all = banks.map { Slot(id: $0.slot, index: $0.index, dial: false, camName: $0.name, cam: $0.settings, name: $0.name, draft: $0.settings) }
            if SettingsFile.layout(model: i.model) != nil, let file = try? await cam.downloadSettingsBackup(),
               let dial = SettingsFile.dialSlots(file, model: i.model) {
                all += dial.enumerated().map { n, d in Slot(id: d.slot, index: n + 1, dial: true, camName: "", cam: d.settings, name: "", draft: d.settings) }
            }
            library.observe(i, slots: all.map { ($0.id, $0.camName, $0.cam) })
            info = i
            if connectedAt == nil { connectedAt = Date() }
            slots = all
            refreshHistory()
            backupCount = library.backups().count
            if !slots.contains(where: { $0.id == selectedSlot }) { selectedSlot = slots.first?.id ?? "C1" }
            if sheet == .connect { sheet = nil }
            say("\(i.model) · \(banks.count) slots and the dial read · backup saved")
            if syncSlots { syncSlotsToLibrary(quiet: true) }
        } catch {
            say("Couldn't read the camera: \(error)")
        }
    }

    /// Camera → library: slot recipes the library doesn't have are added as yours, named after the slot, with the photos
    /// you shot with them as samples (Mac: your Fujifilm JPEGs' EXIF; iPhone / iPad: no photos, they come when the Mac
    /// syncs). Recipes already here that have no photos get them. The toast offers Undo. `quiet`: on connect, no toast
    /// when there's nothing new.
    func syncSlotsToLibrary(quiet: Bool = false) {
        guard let info, !slots.isEmpty, !syncingSlots else { return }
        let contents = slots.map { SlotSync.SlotContents(slot: $0.id, name: $0.camName, settings: $0.cam, dial: $0.dial) }
        let lib = library, model = info.model
        // Only look through the photos when something needs them (a new recipe, or one without photos).
        guard let plan = try? SlotSync.run(contents, library: lib, camera: model, dryRun: true) else { return }
        let needsPhotos = !plan.added.isEmpty || plan.known.contains { k in (try? lib.recipe(k.slug))?.samples?.isEmpty ?? true }
        guard needsPhotos else { if !quiet { say(plan.summary) }; return }
        syncingSlots = true
        Task.detached(priority: .utility) {
            #if os(macOS)
            let photos = SlotSync.photos()
            #else
            let photos: [SlotSync.Photos]? = nil
            #endif
            let result = Result { try SlotSync.run(contents, library: lib, camera: model, photos: photos) }
            await MainActor.run {
                self.syncingSlots = false
                switch result {
                case .success(let r):
                    self.reload()
                    guard !quiet || !r.added.isEmpty || !r.photosFor.isEmpty else { return }
                    let added = r.added
                    self.say(r.summary, action: added.isEmpty ? nil : ToastAction(title: "Undo") { [weak self] in
                        guard let self else { return }
                        SlotSync.undo(added, library: self.library); self.reload(); self.say("Removed what was added from the camera")
                    })
                case .failure(let e):
                    if !quiet { self.say("Couldn't add the camera's recipes: \(e)") }
                }
            }
        }
    }

    #if os(macOS)
    /// A memory card mounted (or the camera switched to card reader mode): recipes that came from the camera without
    /// photos get the ones on the card. Quiet when there's nothing to find.
    func cardMounted(_ volume: URL) {
        let folders = SlotSync.cardFolders([volume])
        let lib = library
        guard !folders.isEmpty, ((try? lib.recipes()) ?? []).contains(where: { $0.source?.kind == "camera" && ($0.samples ?? []).isEmpty }) else { return }
        Task.detached(priority: .utility) {
            guard let photos = SlotSync.photos(in: folders), let found = try? SlotSync.fillPhotos(library: lib, photos: photos), !found.isEmpty else { return }
            await MainActor.run {
                self.reload()
                let names = found.keys.compactMap { s in self.recipes.first { $0.slug == s }?.name }.sorted()
                self.say("Found \(found.values.reduce(0, +)) of your photos on the card for " + names.joined(separator: ", "))
            }
        }
    }
    #endif

    func refreshHistory() {
        guard let info else { return }
        history = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, library.history(info, slot: $0.id)) })
    }

    func trySimulated() {
        Cameras.shared.simulate = true
        Task { await check() }
    }

    // MARK: Looks

    /// Photos that show a recipe's look: rendered reference scenes, then the owner's own shots, then creator frames.
    /// Never an imitation (ADR 0003).
    func photos(_ r: Recipe) -> [String] {
        let fm = FileManager.default
        func images(_ dir: String) -> [String] {
            ((try? fm.contentsOfDirectory(at: library.root.appendingPathComponent(dir), includingPropertiesForKeys: nil)) ?? [])
                .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
                .map(\.path).sorted()
        }
        let own = (r.samples ?? []).filter { fm.fileExists(atPath: $0) }
        return images("scenes/rendered/\(r.slug)") + own + images("samples/\(r.slug)")
    }

    var allTags: [String] {
        let starter = ["Leica style", "Warm", "Cool", "B&W", "Bright day", "Night", "Film", "Punchy", "Soft"]
        let used = Set(recipes.flatMap { $0.tags ?? [] })
        return starter.filter(used.contains) + used.subtracting(starter).sorted()
    }

    var visibleRecipes: [Recipe] {
        guard let f = tagFilter else { return recipes }
        if f.hasPrefix("status:") { let s = String(f.dropFirst(7)); return recipes.filter { $0.status == s } }
        return recipes.filter { ($0.tags ?? []).contains(f) || (f == "B&W" && $0.settings.isMonochrome) }
    }

    func recipe(_ slug: String?) -> Recipe? { recipes.first { $0.slug == slug } }
    /// The recipe a slot holds: exact, else one that differs only where the camera sets limits (lower DR, toning).
    func match(_ s: RecipeSettings, dial: Bool = false) -> Recipe? { matchOnCamera(s, dial: dial)?.recipe }
    func matchOnCamera(_ s: RecipeSettings, dial: Bool = false) -> (recipe: Recipe, notes: [String])? {
        if let r = recipes.first(where: { $0.settings == s }) { return (r, []) }
        return recipes.compactMap { r in r.settings.cameraLimitedDifferences(s, dial: dial).map { (r, $0) } }.min { $0.1.count < $1.1.count }
    }

    /// A camera refusal in plain words, with what to do about it.
    static func explain(_ f: FieldResult, slot: String) -> String {
        switch f.field {
        case "dynamicRange":
            let dr = f.wanted == 400 ? "DR400 needs ISO 640" : f.wanted == 200 ? "DR200 needs ISO 320" : "that DR needs a higher ISO"
            return "\(slot) keeps a lower DR: \(dr) or more, and this slot remembers a lower ISO. On the camera: dial on C, pick \(slot), set ISO to 640+, then put the recipe in again"
        case "monoWarmCool", "monoMagentaGreen":
            return "\(slot) refused the B&W toning; set WC/MG on the camera if you need it"
        default:
            return "\(slot) refused \(f.field)"
        }
    }
    func slotsHolding(_ r: Recipe) -> [String] { slots.filter { $0.cam == r.settings || $0.cam == r.settings.forCamera(preferences) }.map(\.id) }
    /// What the camera shoots for a recipe now (Clarity 0 while it's off): Studio renders use this.
    func shot(_ r: Recipe) -> RecipeSettings { r.settings.forCamera(preferences) }

    /// "In C1 and FS1 · 39 of your photos · last used 11 Jul"
    func whereabouts(_ r: Recipe) -> String {
        var parts: [String] = []
        let held = slotsHolding(r)
        if !held.isEmpty { parts.append("in " + held.joined(separator: ", ")) }
        else if let staged = slots.first(where: { $0.changed && $0.draft == shot(r) }) { parts.append("→ \(staged.id)") }
        if let n = r.shots, n > 0 { parts.append("\(n) of your photos") }
        if let last = r.lastShot { parts.append("last used \(Self.short(last))") }
        if parts.isEmpty { parts.append(r.status == "to-try" ? "to try" : r.status) }
        if let c = r.source?.creator { parts.append(c) }
        return parts.joined(separator: " · ")
    }

    static func short(_ day: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(day.prefix(10))) else { return day }
        let out = DateFormatter(); out.dateFormat = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return out.string(from: d)
    }

    func setStatus(_ r: Recipe, _ status: String) {
        _ = try? library.setStatus(r.slug, status: status, note: nil)
        reload()
        say(status == "tried" ? "\(r.name) · tried" : status == "rejected" ? "\(r.name) · not for me" : "\(r.name) · to try")
    }

    func toggleFavorite(_ r: Recipe) {
        let next = r.status == "favorite" ? ((r.shots ?? 0) > 0 ? "mine" : "tried") : "favorite"
        _ = try? library.setStatus(r.slug, status: next, note: nil)
        reload()
    }

    /// Saves an edited recipe (name, description, status, tags, source). The slug stays, so its photos stay.
    @discardableResult func update(_ r: Recipe) -> Bool {
        do { _ = try library.save(r, allowDuplicate: true); reload(); say("Saved \(r.name)"); return true }
        catch { say("Couldn't save: \(error)"); return false }
    }

    func setTags(_ r: Recipe, _ tags: [String]) {
        var x = r; x.tags = tags.isEmpty ? nil : tags
        _ = try? library.save(x, allowDuplicate: true)
        reload()
    }

    func show(_ paths: [String], at i: Int, title: String, titles: [String]? = nil, recipes: [String?]? = nil) {
        guard !paths.isEmpty else { return }
        preview = Preview(title: title, paths: paths, index: max(0, min(paths.count - 1, i)), titles: titles, recipes: recipes)
    }

    // MARK: Studio: one RAW, developed by the camera with each recipe

    var studioRaw: URL? {
        didSet {
            studioBase = nil; studioNotes = [:]; studioStopped = false; studioSelected = 0; sharpWanted = []
            UserDefaults.standard.set(studioRaw?.path, forKey: "studioRaw")
            loadStudioPicks()
        }
    }
    var studioFilter: String? { didSet { studioStopped = false } }  // like tagFilter: nil = favorites + to try; "all"; "status:…"; "picked"; a tag
    var studioSelected = 0              // keyboard selection in the grid: 0 = as shot, then the recipes in order
    var studioStopped = false           // Stop pressed: no automatic render until the RAW or the filter changes
    var studioFullLoading: String?      // recipe slug whose full-size render is on its way
    private var studioFullWanted: String?
    var studioRendering = false
    var studioProgress = (done: 0, total: 0)
    var studioNotes: [String: [String]] = [:]   // recipe slug → what the camera couldn't render exactly
    var studioError: String?
    private var studioBase: ConversionProfile?
    private var studioTask: Task<Void, Never>?
    private(set) var studioVersion = 0       // bumps when a render lands, so tiles reload

    var studioRecipes: [Recipe] {
        switch studioFilter {
        case nil: let picked = recipes.filter { $0.status == "favorite" || $0.status == "to-try" }; return picked.isEmpty ? recipes : picked
        case "all"?: return recipes
        case "picked"?: return recipes.filter { studioPicks.contains($0.slug) }
        case let f? where f.hasPrefix("status:"): return recipes.filter { $0.status == f.dropFirst(7) }
        case let f?: return recipes.filter { ($0.tags ?? []).contains(f) || (f == "B&W" && $0.settings.isMonochrome) }
        }
    }

    /// The shape of the Studio's photo: 2:3 for a vertical shot, 3:2 for a horizontal one.
    var studioRatio: CGFloat {
        guard let raw = studioRaw else { return 3 / 2 }
        return (5...8).contains(RenderCache.orientation(raw)) ? 2 / 3 : 3 / 2
    }

    func studioRender(_ r: Recipe) -> URL? {
        guard let raw = studioRaw else { return nil }
        return RenderCache(library: library).cached(raw: raw, settings: shot(r))
    }

    /// Renders every chosen recipe that isn't cached yet, one at a time, on the connected camera.
    func renderStudio() {
        guard let raw = studioRaw, !studioRendering else { return }
        let todo = studioRecipes.filter { studioRender($0) == nil }
        guard !todo.isEmpty else { say("Every recipe here is already rendered"); return }
        guard connected else { studioError = "Plug in the camera to render: it develops the RAW itself."; return }
        guard !writing else { say("Writing to the camera; render in a moment"); return }
        studioError = nil
        studioRendering = true
        studioProgress = (0, todo.count)
        studioTask = Task { [weak self] in
            guard let self else { return }
            defer { self.studioRendering = false; self.busy = nil }
            do {
                guard let cam = await Cameras.shared.current() else { throw CameraError("The camera isn't connected.") }
                if self.studioBase == nil {
                    self.busy = "Sending the RAW to the camera…"
                    let data = try Data(contentsOf: raw)
                    self.studioBase = try await cam.uploadRAF(data)
                }
                let cache = RenderCache(library: self.library)
                for (i, r) in todo.enumerated() {
                    if Task.isCancelled { break }
                    self.busy = "Rendering \(i + 1) of \(todo.count) · \(r.name)"
                    let made = try await cam.render(self.shot(r), base: self.studioBase!)
                    try cache.store(made.jpeg, raw: raw, settings: self.shot(r))
                    if !made.notes.isEmpty { self.studioNotes[r.slug] = made.notes }
                    self.studioProgress = (i + 1, todo.count)
                    self.studioVersion += 1
                }
                self.say(Task.isCancelled ? "Stopped" : "Rendered \(todo.count) recipe\(todo.count == 1 ? "" : "s")")
                self.studioRendering = false
                if let want = self.studioFullWanted { self.loadStudioFull(want) }
            } catch {
                self.studioError = "\(error)"
            }
        }
    }

    func stopStudio() { studioStopped = true; studioTask?.cancel(); lookTask?.cancel() }

    /// The Studio renders by itself: whenever it shows a RAW with recipes not developed yet and the camera is
    /// connected (quietly: no toast when there's nothing to do, no error without a camera). Stop pauses it until the
    /// RAW or the filter changes.
    func autoRenderStudio() {
        guard tab == .studio, studioMode == .recipes, connected, !writing, !studioRendering, !studioStopped,
              studioRaw != nil, studioRecipes.contains(where: { studioRender($0) == nil }) else { return }
        renderStudio()
    }

    // Full size: the grid's renders are the camera's 640-px previews; the photo opened big is developed again at full
    // size (about 5 s), kept at 3000 px in the cache, and the preview switches to it.

    func studioFull(_ slug: String) -> URL? {
        guard let raw = studioRaw, let r = recipes.first(where: { $0.slug == slug }) else { return nil }
        return RenderCache(library: library).cached(raw: raw, settings: shot(r), full: true)
    }

    func loadStudioFull(_ slug: String?) {
        studioFullWanted = slug
        guard let slug, let raw = studioRaw, let r = recipes.first(where: { $0.slug == slug }), studioFull(slug) == nil else { return }
        wantSharp(r)
        guard connected, !writing, studioFullLoading == nil else { return }
        guard !studioRendering else { return }      // the grid's renders go first; picked up when they finish
        studioFullLoading = slug
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.studioFullLoading = nil
                if let next = self.studioFullWanted, next != slug { self.loadStudioFull(next) }
            }
            do {
                guard let cam = await Cameras.shared.current() else { return }
                if self.studioBase == nil { self.studioBase = try await cam.uploadRAF(try Data(contentsOf: raw)) }
                let made = try await cam.render(self.shot(r), base: self.studioBase!, full: true, timeout: 90)
                try RenderCache(library: self.library).store(Self.shrunk(made.jpeg, to: 3000), raw: raw, settings: self.shot(r), full: true)
                self.studioVersion += 1
            } catch {
                self.say("Couldn't develop \(r.name) at full size: \(error)")
            }
        }
    }

    // The cards, and the big preview until the camera's full-size render lands: the 640-px render with detail from the
    // JPEG inside the RAF (`RenderDetail`, 0.2 s the first time for a RAW, 70 ms after). In Caches, not the library: it
    // can be remade.

    private var studioDetail: (raw: URL, detail: Task<RenderDetail?, Never>)?
    private var sharpWanted: [Recipe] = []
    private var sharpWorking = false

    func studioSharp(_ slug: String) -> URL? {
        guard let raw = studioRaw, let r = recipes.first(where: { $0.slug == slug }) else { return nil }
        let u = sharpURL(raw: raw, settings: shot(r))
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// The best picture of a recipe for a card: the camera's full size if it has been made, else the sharp one.
    func studioBetter(_ r: Recipe) -> String? {
        guard let raw = studioRaw else { return nil }
        if let full = RenderCache(library: library).cached(raw: raw, settings: shot(r), full: true) { return full.path }
        let u = sharpURL(raw: raw, settings: shot(r))
        return FileManager.default.fileExists(atPath: u.path) ? u.path : nil
    }

    private func sharpURL(raw: URL, settings: RecipeSettings) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FujiRecipes/sharp/\(RenderCache.rawKey(raw))/\(RenderCache.recipeKey(settings)).jpg")
    }

    /// Asks for one render's sharp version. One at a time, latest asked first, so the cards on screen and the photo
    /// opened big come before cards scrolled past.
    func wantSharp(_ r: Recipe) {
        guard let raw = studioRaw, studioRender(r) != nil, !FileManager.default.fileExists(atPath: sharpURL(raw: raw, settings: shot(r)).path) else { return }
        sharpWanted.removeAll { $0.slug == r.slug }
        sharpWanted.insert(r, at: 0)
        guard !sharpWorking else { return }
        sharpWorking = true
        Task { [weak self] in await self?.runSharp() }
    }

    private func runSharp() async {
        defer { sharpWorking = false }
        while !sharpWanted.isEmpty {
            let r = sharpWanted.removeFirst()
            guard let raw = studioRaw, let render = studioRender(r) else { continue }
            let out = sharpURL(raw: raw, settings: shot(r))
            if FileManager.default.fileExists(atPath: out.path) { continue }
            if studioDetail?.raw != raw {
                pruneSharp(keeping: out.deletingLastPathComponent())
                studioDetail = (raw, Task.detached(priority: .userInitiated) { RenderDetail.embeddedPreview(raw).flatMap { RenderDetail(preview: $0) } })
            }
            guard let detail = studioDetail?.detail else { continue }
            let made = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let d = await detail.value, let jpeg = try? Data(contentsOf: render), let sharp = d.apply(toRender: jpeg) else { return false }
                try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                return (try? RenderCache.tagged(sharp, orientation: RenderCache.orientation(raw)).write(to: out, options: .atomic)) != nil
            }.value
            if made { studioVersion += 1 }
        }
    }

    /// Every card of a RAW is ~2 MB here: only the three latest RAWs stay.
    private func pruneSharp(keeping folder: URL) {
        let root = folder.deletingLastPathComponent()
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let date = { (u: URL) in (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        for old in dirs.filter({ $0.lastPathComponent != folder.lastPathComponent }).sorted(by: { date($0) > date($1) }).dropFirst(2) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// A full-size render (~25 MB) kept at `side` px on its long side, in the sensor's orientation (the cache tags it).
    static func shrunk(_ jpeg: Data, to side: Int) -> Data {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: side] as CFDictionary) else { return jpeg }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return jpeg }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : jpeg
    }

    // Picks: the recipes you like for this photo, to decide later. Per RAW, in the library's studio/picks.json
    // (RAW key → recipe slugs), so they sync with the library and survive renders being cleared.

    private(set) var studioPicks: Set<String> = []

    private var picksFile: URL { library.root.appendingPathComponent("studio/picks.json") }

    private func loadStudioPicks() {
        guard let raw = studioRaw, let d = try? Data(contentsOf: picksFile),
              let all = try? JSONDecoder().decode([String: [String]].self, from: d) else { studioPicks = []; return }
        studioPicks = Set(all[RenderCache.rawKey(raw)] ?? [])
    }

    func togglePick(_ slug: String) {
        guard let raw = studioRaw else { return }
        var all = (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: picksFile))) ?? [:]
        if studioPicks.contains(slug) { studioPicks.remove(slug) } else { studioPicks.insert(slug) }
        all[RenderCache.rawKey(raw)] = studioPicks.sorted()
        try? FileManager.default.createDirectory(at: picksFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(all) { try? d.write(to: picksFile, options: .atomic) }
        if studioFilter == "picked", studioPicks.isEmpty { studioFilter = nil }
    }

    // MARK: Match a look: any photo in, the recipe that comes closest out

    enum StudioMode: String { case recipes, look }
    var studioMode: StudioMode = StudioMode(rawValue: UserDefaults.standard.string(forKey: "studioMode") ?? "") ?? .recipes {
        didSet { UserDefaults.standard.set(studioMode.rawValue, forKey: "studioMode") }
    }
    var lookReference: URL? {
        didSet { UserDefaults.standard.set(lookReference?.path, forKey: "lookReference"); lookResults = []; lookGuess = nil; analyseLook() }
    }
    var lookStats: LookStats?
    var lookGuess: (settings: RecipeSettings, notes: [String], neighbours: [LookMatch.Neighbour])?
    struct LookResult: Identifiable { var id: String { RenderCache.recipeKey(settings) }; var settings: RecipeSettings; var match: Int; var jpeg: URL }
    var lookResults: [LookResult] = []
    var lookSearching = false
    var lookProgress = (done: 0, budget: 0, stage: "", best: 0)
    var lookError: String?
    var lookAnalysing = false
    var lookSaved: [String: String] = [:]          // result id → saved recipe slug
    var lookBudget = 60
    private var lookTask: Task<Void, Never>?

    /// Uses a photo as the reference. iPhone / iPad: a picked file is only readable for a while, so it's copied into
    /// the library's studio/looks folder (as are photos from the Photos library, passed as data).
    func useLookReference(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        #if os(iOS)
        let dir = library.root.appendingPathComponent("studio/looks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: url, to: copy)
        lookReference = copy
        #else
        lookReference = url
        #endif
    }

    func useLookReference(data: Data, name: String) {
        let dir = library.root.appendingPathComponent("studio/looks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        do { try data.write(to: file, options: .atomic); lookReference = file } catch { lookError = "Couldn't keep that photo: \(error.localizedDescription)" }
    }

    /// Uses a RAW for the Studio. iPhone / iPad: a picked or pasted file is only readable for a while, so it's copied
    /// into the library's studio folder.
    func useStudioRaw(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        #if os(iOS)
        let dir = library.root.appendingPathComponent("studio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: url, to: copy) }
        studioRaw = copy
        #else
        studioRaw = url
        #endif
    }

    /// Paste in the Studio (⌘V on the Mac, the Paste button on iPhone / iPad): a copied .RAF becomes the Studio's RAW
    /// (in both modes: Match a look checks on it); a copied photo file, or an image copied from a browser or Photos,
    /// becomes the look to match. Returns false when the clipboard holds neither, so ⌘V falls through.
    @discardableResult
    func pasteIntoStudio(files: [URL], image: (data: Data, name: String)? = nil) -> Bool {
        if let raw = files.first(where: { $0.pathExtension.uppercased() == "RAF" }) {
            useStudioRaw(raw)
            say("Pasted \(raw.lastPathComponent): the Studio develops this RAW now.")
            return true
        }
        let imageExts: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "webp", "dng"]
        if let photo = files.first(where: { imageExts.contains($0.pathExtension.lowercased()) }) {
            studioMode = .look
            useLookReference(photo)
            say("Pasted \(photo.lastPathComponent) as the look to match.")
            return true
        }
        if let image {
            studioMode = .look
            useLookReference(data: image.data, name: image.name)
            say("Pasted a photo as the look to match.")
            return true
        }
        return false
    }

    /// A file name for an image pasted without one ("Pasted 2026-11-05 10-12-03.png").
    static func pastedName(ext: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Pasted \(f.string(from: Date())).\(ext)"
    }

    /// Measures the reference and makes the first guess from the library's sample photos (measured once, then kept in
    /// looks.json), off the main thread.
    func analyseLook() {
        guard let ref = lookReference else { lookStats = nil; return }
        lookError = nil
        lookAnalysing = true
        let lib = library
        Task.detached(priority: .userInitiated) {
            let result = Result { () throws -> (LookStats, (RecipeSettings, [String], [LookMatch.Neighbour])) in
                let stats = try LookStats.measure(file: ref)
                let index = LookIndex.load(lib)
                let g = LookMatch.firstGuess(stats, index: index, recipes: (try? lib.recipes()) ?? [])
                return (stats, (g.settings, g.notes, g.neighbours))
            }
            await MainActor.run {
                guard self.lookReference == ref else { return }
                self.lookAnalysing = false
                switch result {
                case .success(let (stats, g)): self.lookStats = stats; self.lookGuess = (g.0, g.1, g.2)
                case .failure(let e): self.lookError = "\(e)"; self.lookStats = nil
                }
            }
        }
    }

    /// The camera develops the Studio's RAW with candidate recipes and keeps the three whose look comes closest.
    func searchLook() {
        guard let raw = studioRaw, let stats = lookStats, let guess = lookGuess, !lookSearching, !studioRendering else { return }
        guard connected else { lookError = "Plug in the camera: it develops your RAW with each candidate."; return }
        guard !writing else { say("Writing to the camera; try in a moment"); return }
        lookError = nil
        lookSearching = true
        lookResults = []
        lookProgress = (0, lookBudget, "Sending the RAW to the camera", 0)
        let budget = lookBudget
        lookTask = Task { [weak self] in
            guard let self else { return }
            defer { self.lookSearching = false; self.busy = nil }
            do {
                guard let cam = await Cameras.shared.current() else { throw CameraError("The camera isn't connected.") }
                if self.studioBase == nil {
                    self.busy = "Sending the RAW to the camera…"
                    self.studioBase = try await cam.uploadRAF(try Data(contentsOf: raw))
                }
                let base = self.studioBase!
                let cache = RenderCache(library: self.library)
                let found = try await LookMatch.refine(reference: stats, start: guess.settings, budget: budget, render: { s in
                    if let hit = cache.cached(raw: raw, settings: s), let d = try? Data(contentsOf: hit) { return d }
                    let made = try await cam.render(s, base: base)
                    try cache.store(made.jpeg, raw: raw, settings: s)
                    return made.jpeg
                }, progress: { p in
                    self.lookProgress = (p.done, p.budget, p.stage, p.best?.match ?? 0)
                    self.busy = "Matching the look · \(p.done) of \(p.budget)"
                })
                self.lookResults = found.map { LookResult(settings: $0.settings, match: $0.match, jpeg: cache.url(raw: raw, settings: $0.settings)) }
                self.say(found.first.map { "Closest: \($0.match)% match" } ?? "No match found")
            } catch is CancellationError {
                self.say("Stopped")
            } catch {
                self.lookError = "\(error)"
            }
        }
    }

    /// Keeps a result (or the first guess, without the camera) as a to-try recipe named after the reference photo.
    func saveLook(_ settings: RecipeSettings, match: Int?, jpeg: URL?) {
        guard let ref = lookReference else { return }
        let name = "Look of " + ref.deletingPathExtension().lastPathComponent
        do {
            let saved = try library.saveMatched(settings, name: name, reference: ref, raw: jpeg == nil ? nil : studioRaw, match: match,
                                                render: jpeg.flatMap { try? Data(contentsOf: $0) }, notes: lookGuess?.notes ?? [])
            lookSaved[RenderCache.recipeKey(settings)] = saved.recipe.slug
            reload()
            say(saved.existing ? "Already in your library as \(saved.recipe.name)" : "Saved \(saved.recipe.name) · To try")
        } catch {
            lookError = "\(error)"
        }
    }

    func openRecipe(_ slug: String) { settingsFor = slug; sheet = .settings }

    // MARK: Slots: stage, review, write

    var slot: Slot? { slots.first { $0.id == selectedSlot } }

    func update(_ id: String? = nil, _ change: (inout Slot) -> Void) {
        guard let i = slots.firstIndex(where: { $0.id == (id ?? selectedSlot) }) else { return }
        change(&slots[i])
        slots[i].draft.normalize()
        if slots[i].changed { scheduleWrite(after: 0.8) }   // dial edits: once the dragging stops
    }

    /// Instant mode: write what changed after `seconds` of quiet (0 for a look dropped on a slot).
    func scheduleWrite(after seconds: Double) {
        guard !askBeforeWriting, connected else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.writeChanges()
        }
    }

    /// The Clarity switch. Turning it on goes through `confirmClarity` (it slows every shot); either way the slots
    /// follow: off puts every slot's Clarity at 0, on gives slots holding a recipe that recipe's Clarity back.
    func setClarity(_ on: Bool) {
        guard on != preferences.clarity else { return }
        var p = preferences; p.clarity = on
        do { try library.setPreferences(p) } catch { say("Couldn't save the setting: \(error.localizedDescription)"); return }
        preferences = p
        var touched: [String] = []
        for s in slots {
            let want = on ? (matchOnCamera(s.draft, dial: s.dial)?.recipe.settings.clarity ?? s.draft.clarity) : 0
            if want != s.draft.clarity { update(s.id) { $0.draft.clarity = want }; touched.append(s.id) }
        }
        let list = touched.joined(separator: ", ")
        let message = on
            ? (touched.isEmpty ? "Clarity on · shots take 1–3 s longer to store when a recipe uses it"
                               : "Clarity on · \(list) get their recipe's Clarity back · those shots take 1–3 s longer to store")
            : (touched.isEmpty ? "Clarity off · shots save without waiting" : "Clarity off · \(list) set to 0 · shots save without waiting")
        guard !touched.isEmpty, !askBeforeWriting, connected else {
            say(touched.isEmpty || !connected ? message : message + " · review to write")
            return
        }
        // Instant mode: write now and say what happened after the write's own message.
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            await self?.writeChanges()
            self?.say(message)
        }
    }

    /// Stage a recipe in a slot (drag onto it, or pick it). Nothing reaches the camera until Review & write.
    func put(_ r: Recipe, in slotID: String) {
        guard slots.contains(where: { $0.id == slotID }) else { return }
        update(slotID) { $0.draft = r.settings.forCamera(preferences); $0.name = PTPString.bankName(r.name.uppercased()) }
        selectedSlot = slotID
        if askBeforeWriting { say("\(r.name) → \(slotID) · not on the camera yet") } else { scheduleWrite(after: 0) }
    }

    func putBack(_ rec: SlotRecord) {
        update(rec.slot) { $0.draft = rec.settings.forCamera(preferences); $0.name = rec.name }
        if askBeforeWriting { say("\(rec.name.isEmpty ? rec.settings.film : rec.name) staged for \(rec.slot) · review to write") }
        else { scheduleWrite(after: 0) }
    }

    func revert(_ id: String) { update(id) { $0.draft = $0.cam; $0.name = $0.camName } }
    func revertAll() { for s in changes { revert(s.id) } }

    /// Mac / wide iPad: a slot's page opens over the looks (its photos, history, Put back, the dials).
    func openSlot(_ id: String, editing: Bool = false) {
        selectedSlot = id
        self.editing = editing
        sheet = .slot
    }

    /// The whole settings file as it was before an FS write: the way back if anything looks wrong.
    func saveSettingsFile(_ data: Data, model: String, reason: String) {
        let dir = library.root.appendingPathComponent("backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date().isoStamp.prefix(19).replacingOccurrences(of: ":", with: "")
        try? data.write(to: dir.appendingPathComponent("\(stamp)-\(Recipe.slugify(model))-settings-\(reason.lowercased()).dat"))
    }

    /// Other slots holding the same recipe as `slot` (empty slots don't count). FS positions are compared without the
    /// WB shift and B&W toning, which the settings file doesn't give reliably yet.
    func duplicates(of slot: Slot) -> [String] {
        guard !(slot.unused && !slot.changed) else { return [] }
        func key(_ s: RecipeSettings, loose: Bool) -> RecipeSettings {
            var k = s
            if loose { k.wbRed = 0; k.wbBlue = 0; k.monoWarmCool = nil; k.monoMagentaGreen = nil }
            k.normalize(); return k
        }
        return slots.filter { o in
            guard o.id != slot.id, !(o.unused && !o.changed) else { return false }
            let loose = o.dial || slot.dial
            return key(o.draft, loose: loose) == key(slot.draft, loose: loose)
        }.map(\.id)
    }

    static func sameAs(_ ids: [String]) -> String {
        ids.isEmpty ? "" : "Same recipe as " + ids.joined(separator: " and ")
    }

    func freeSlot() -> String? { slots.first { !$0.dial && $0.unused && !$0.changed }?.id ?? slots.first { !$0.dial }?.id }

    /// Each changed slot: back it up (read from the camera), write what differs, read back, record in history.
    /// Instant mode offers Undo, which writes the slots' previous contents back the same way.
    func writeChanges() async {
        if writing { writeAgain = true; return }
        let todo = changes
        guard !todo.isEmpty, let cam = await Cameras.shared.current() else { return }
        writing = true
        if sheet == .review { sheet = nil }
        busy = "Writing \(todo.map(\.id).joined(separator: ", "))…"
        let before = todo.map { (id: $0.id, settings: $0.cam, name: $0.camName) }
        do {
            let i = try await cam.deviceInfo()
            var old: [Bank] = []
            for s in todo where !s.dial { old.append(try await cam.readBank(s.index)) }
            if !old.isEmpty { _ = try library.saveBackup(Snapshot(date: Date().isoStamp, reason: "Before writing \(todo.map(\.id).joined(separator: ", "))", camera: i, banks: old)) }
            var problems: [String] = []
            var keptOnCamera: [String] = []
            // C slots first (properties), then FS1–FS3 (settings file, each in fresh sessions).
            for s in todo.sorted(by: { !$0.dial && $1.dial }) {
                if s.dial {
                    let (report, prior) = try await cam.writeDialSlot(s.index - 1, settings: s.draft)
                    saveSettingsFile(prior, model: i.model, reason: "before-\(s.id)")
                    library.recordWrite(i, slot: s.id, name: "", settings: report.after)
                    if let k = slots.firstIndex(where: { $0.id == s.id }) {
                        slots[k].cam = report.after
                        if slots[k].draft == s.draft { slots[k].draft = report.after }
                    }
                    if s.draft.wbRed != report.after.wbRed || s.draft.wbBlue != report.after.wbBlue { keptOnCamera.append("\(s.id) WB shift") }
                    if s.draft.isMonochrome && (s.draft.monoWarmCool != report.after.monoWarmCool || s.draft.monoMagentaGreen != report.after.monoMagentaGreen) { keptOnCamera.append("\(s.id) toning") }
                    if !report.ok { problems += report.mismatches.map { "\(s.id) \($0)" } + (report.unexpected > 0 ? ["\(s.id): \(report.unexpected) other bytes changed"] : []) }
                    continue
                }
                let report = try await cam.writeBank(s.index, settings: s.draft, name: s.name)
                library.recordWrite(i, slot: s.id, name: report.name, settings: report.after)
                if let k = slots.firstIndex(where: { $0.id == s.id }) {
                    slots[k].cam = report.after; slots[k].camName = report.name
                    // A newer edit made while this one was being written stays a draft (and is written next).
                    if slots[k].draft == s.draft { slots[k].draft = report.after }
                    if slots[k].name == s.name { slots[k].name = report.name }
                }
                if !report.ok {
                    let refusedFields = Set(report.refused.map(\.field))
                    problems += report.refused.map { AppModel.explain($0, slot: s.id) }
                    // Mismatches already explained by a refusal aren't repeated.
                    problems += report.mismatches.filter { m in !(refusedFields.contains("dynamicRange") && m.hasPrefix("Dynamic range")) && !(refusedFields.contains { $0.hasPrefix("mono") } && m.hasPrefix("Mono")) }.map { "\(s.id) \($0)" }
                }
            }
            refreshHistory()
            backupCount = library.backups().count
            let what = todo.map { "\(match($0.draft)?.name ?? ($0.name.isEmpty ? $0.draft.film : $0.name.capitalized)) in \($0.id)" }.joined(separator: ", ")
            let note = keptOnCamera.isEmpty ? "" : " · \(keptOnCamera.joined(separator: ", ")) stays as set on the camera"
            if !problems.isEmpty {
                say("Written · \(problems.joined(separator: " · "))")
            } else if askBeforeWriting {
                say("Wrote \(todo.map(\.id).joined(separator: ", ")) · read back OK · to shoot: dial on C, Q, pick the slot")
            } else {
                say("\(what) · on the camera\(note)", action: ToastAction(title: "Undo") { [weak self] in
                    guard let self else { return }
                    for b in before { self.update(b.id) { $0.draft = b.settings; $0.name = b.name } }
                    self.scheduleWrite(after: 0)
                })
            }
        } catch {
            say("Couldn't write: \(error)")
        }
        busy = nil
        writing = false
        if writeAgain {
            writeAgain = false
            await writeChanges()
        }
    }

    // MARK: Inbox

    var queuedCount: Int { inbox.filter { $0.status == .queued }.count }
    var toReview: [InboxItem] { inbox.filter { $0.status == .read } }

    func addToInbox(text: String, source: String = "paste") {
        do {
            let added = try library.addToInbox(text: text, source: source)
            reloadInbox()
            say(added.isEmpty ? "No new reel links in that" : "\(added.count) added to the inbox")
        } catch { say("\(error)") }
    }

    func addToInbox(file: URL) {
        let ext = file.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "webp"].contains(ext) {
            if (try? library.addToInbox(image: file, source: "drop")) != nil { reloadInbox(); say("Screenshot added to the inbox") }
        } else if let text = try? String(contentsOf: file, encoding: .utf8) {
            addToInbox(text: text, source: ext == "json" || ext == "html" ? "instagram-export" : "drop")
        }
    }

    func keep(_ item: InboxItem) {
        try? library.updateInbox(item.id, status: .kept)
        reloadInbox(); reload()
    }

    func skip(_ item: InboxItem) {
        if let slug = item.recipe, item.status == .read { _ = try? library.setStatus(slug, status: "rejected", note: "Skipped in the inbox") }
        try? library.updateInbox(item.id, status: .skipped)
        reloadInbox(); reload()
    }

    func say(_ text: String, action: ToastAction? = nil) {
        toast = text
        toastAction = action
        toastTask?.cancel()
        let seconds = UInt64(max(action == nil ? 3.5 : 8, Double(text.count) / 14) * 1_000_000_000)   // long messages stay longer
        toastTask = Task { try? await Task.sleep(nanoseconds: seconds); if !Task.isCancelled { toast = nil; toastAction = nil } }
    }
}


extension AppModel {
    /// For every Clarity switch: off right away, on only after `confirmClarity` (it slows every shot).
    var clarityBinding: Binding<Bool> {
        Binding(get: { self.clarityOn }, set: { on in if on { self.confirmClarity = true } else { self.setClarity(false) } })
    }
}

extension View {
    /// "Turn on Clarity?": the cost first, then Yes / No. Attached once at the root (Mac, iPhone, iPad).
    func clarityConfirmation() -> some View { modifier(ClarityConfirmation()) }
}

private struct ClarityConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        @Bindable var model = model
        content.alert("Turn on Clarity?", isPresented: $model.confirmClarity) {
            Button("Yes, Turn On") { model.setClarity(true) }
            Button("No", role: .cancel) {}
        } message: {
            Text("\(Preferences.clarityCost) Slots holding a recipe that uses it get its Clarity back.")
        }
    }
}
