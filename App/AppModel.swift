import AppKit
import FujiKit
import Foundation
import Observation

/// Everything the window shows: the camera (found live over USB, checked with Doctor), its slots with unsaved
/// drafts, the recipe library, and what's selected. All camera I/O goes through FujiKit, like the CLI and MCP server.
@MainActor @Observable
final class AppModel {
    enum Tab { case camera, recipes }
    enum Sheet: String, Identifiable { case help, trouble, backups; var id: String { rawValue } }
    enum RecipeFilter: String, CaseIterable { case all, mine, toTry, favorites }

    struct Slot: Identifiable, Equatable {
        let id: String           // "C1" … "C7", "FS1" … "FS3"
        let index: Int           // 1-based
        let dial: Bool           // film simulation dial: read only
        var camName: String      // what the camera holds
        var cam: RecipeSettings
        var name: String         // the draft
        var draft: RecipeSettings
        var changed: Bool { !dial && (draft != cam || name != camName) }
        var unused: Bool { cam == RecipeSettings.factory && camName.isEmpty }
    }

    var tab: Tab = .camera
    var sheet: Sheet?
    var showSidebar = true
    var library = Library()
    var recipes: [Recipe] = []
    var recipeFilter: RecipeFilter = .all
    var selectedRecipe: String?

    // Camera
    var steps: [Doctor.Step] = []
    var appsHolding: [String] = []
    var info: DeviceInfo?
    var slots: [Slot] = []
    var selectedSlot = "C1"
    var editing = false
    var confirmingWrite = false
    var busy: String?
    var toast: String?
    var backupCount = 0
    var connected: Bool { info != nil && !slots.isEmpty }
    var simulated: Bool { Cameras.shared.simulate }

    private var checking = false
    private var toastTask: Task<Void, Never>?

    // MARK: Start, detect, read

    func start() {
        reloadLibrary()
        CameraBrowser.shared.onChange = { [weak self] _, _ in Task { @MainActor in await self?.check() } }
        CameraBrowser.shared.start()
        Task { await check() }
        // Changing the USB mode needs a reconnect, and some bodies come and go: look again every few seconds
        // while no camera is ready.
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                if !self.connected { await self.check() }
            }
        }
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
        if !ready, connected || info != nil {
            info = nil; slots = []; editing = false
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
            info = i
            slots = all
            backupCount = library.backups().count
            if !slots.contains(where: { $0.id == selectedSlot }) { selectedSlot = slots.first?.id ?? "C1" }
            say("\(i.model) · \(banks.count) slots read · backup saved")
        } catch {
            say("Couldn't read the camera: \(error)")
        }
    }

    func trySimulated() {
        Cameras.shared.simulate = true
        Task { await check() }
    }

    // MARK: Slots

    var slot: Slot? { slots.first { $0.id == selectedSlot } }

    func update(_ change: (inout Slot) -> Void) {
        guard let i = slots.firstIndex(where: { $0.id == selectedSlot }), !slots[i].dial else { return }
        change(&slots[i])
        slots[i].draft.normalize()
    }

    func load(_ recipe: Recipe) {
        update { $0.draft = recipe.settings; $0.name = PTPString.bankName(recipe.name.uppercased()) }
        say("Loaded “\(recipe.name)” into \(selectedSlot) · not written yet")
    }

    func revert() { update { $0.draft = $0.cam; $0.name = $0.camName } }

    /// Backup of every slot, write what differs, read back. The only place the app writes to the camera.
    func write() async {
        guard let s = slot, s.changed, let cam = await Cameras.shared.current() else { return }
        confirmingWrite = false
        busy = "Writing \(s.id)…"
        defer { busy = nil }
        do {
            let i = try await cam.deviceInfo()
            let banks = try await cam.readAll()
            _ = try library.saveBackup(Snapshot(date: Date().isoStamp, reason: "Before writing \(s.id)", camera: i, banks: banks))
            let report = try await cam.writeBank(s.index, settings: s.draft, name: s.name)
            if let k = slots.firstIndex(where: { $0.id == s.id }) {
                slots[k].cam = report.after; slots[k].draft = report.after
                slots[k].camName = report.name; slots[k].name = report.name
            }
            backupCount = library.backups().count
            if report.ok {
                say("Wrote \(s.id) · read back OK · to shoot: unplug, dial on C, Q, \(s.id)")
            } else {
                let problems = report.refused.map { "\($0.field): \($0.response)" } + report.mismatches
                say("\(s.id) written with differences: \(problems.joined(separator: "; "))")
            }
        } catch {
            say("Couldn't write \(s.id): \(error)")
        }
    }

    func putIn(_ recipe: Recipe) {
        guard connected else { say("Plug in the camera first"); return }
        let target = slots.first { !$0.dial && $0.unused && !$0.changed } ?? slots.first { !$0.dial }
        guard let target else { return }
        tab = .camera
        selectedSlot = target.id
        load(recipe)
        editing = true
        confirmingWrite = true
    }

    func saveAsRecipe(_ s: Slot) {
        if let twin = library.match(s.cam) { say("Already in your recipes as “\(twin.name)”"); return }
        var r = Recipe(slug: "", name: s.camName.isEmpty ? "\(s.id) \(s.cam.film)" : s.camName.capitalized, status: "tried", settings: s.cam)
        r.source = .init(kind: "camera", dateAdded: Date().day)
        r.notes = "Read from \(s.id) of the \(info?.model ?? "camera")."
        do { let saved = try library.save(r); reloadLibrary(); say("Saved “\(saved.name)” to your recipes") }
        catch { say("\(error)") }
    }

    func copyText(_ settings: RecipeSettings, name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(name)\n\(settings.text)", forType: .string)
        say("Copied as text")
    }

    // MARK: Recipes

    func reloadLibrary() {
        recipes = ((try? library.recipes()) ?? []).sorted { ($0.shots ?? 0, $1.name) > ($1.shots ?? 0, $0.name) }
        if selectedRecipe == nil { selectedRecipe = recipes.first?.slug }
    }

    var filteredRecipes: [Recipe] { recipes(in: recipeFilter) }

    func recipes(in filter: RecipeFilter) -> [Recipe] {
        recipes.filter { r in
            switch filter {
            case .all: return true
            case .mine: return r.status == "mine"
            case .toTry: return r.status == "to-try"
            case .favorites: return r.status == "favorite"
            }
        }
    }

    func count(_ f: RecipeFilter) -> Int { recipes(in: f).count }

    var recipe: Recipe? { recipes.first { $0.slug == selectedRecipe } }

    func toggleFavorite(_ r: Recipe) {
        let next = r.status == "favorite" ? ((r.shots ?? 0) > 0 ? "mine" : "tried") : "favorite"
        _ = try? library.setStatus(r.slug, status: next, note: nil)
        reloadLibrary()
    }

    func match(_ s: RecipeSettings) -> Recipe? { recipes.first { $0.settings == s } }

    /// Slots on the connected camera that hold exactly this recipe.
    func slotsHolding(_ r: Recipe) -> [String] { slots.filter { $0.cam == r.settings }.map(\.id) }

    func say(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if !Task.isCancelled { toast = nil } }
    }
}

extension RecipeSettings {
    /// A slot nobody has set: Provia, everything at 0 / Off / Auto.
    static var factory: RecipeSettings { var s = RecipeSettings(); s.normalize(); return s }
}
