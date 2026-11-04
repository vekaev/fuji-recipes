import FujiKit
import Foundation
import Observation
import SwiftUI

/// Everything the window shows, on Mac, iPhone and iPad: the recipe library as looks, the camera's slots with staged
/// changes and their history, and the inbox. Camera I/O goes through FujiKit, like `fuji mcp`.
/// The only camera write path is `writeChanges()`: backup of every slot → write each changed slot → read back →
/// record in the slot history.
@MainActor @Observable
final class AppModel {
    enum Tab: String, CaseIterable, Identifiable { case looks, camera, inbox; var id: String { rawValue } }
    enum Sheet: String, Identifiable { case help, trouble, backups, review, settings; var id: String { rawValue } }

    struct Slot: Identifiable, Equatable {
        let id: String           // "C1" … "C7", "FS1" … "FS3"
        let index: Int
        let dial: Bool           // FS1–FS3: read only until ADR 0004's test
        var camName: String
        var cam: RecipeSettings
        var name: String
        var draft: RecipeSettings
        var changed: Bool { !dial && (draft != cam || name != camName) }
        var unused: Bool { cam == RecipeSettings.factory && camName.isEmpty }
    }

    struct Preview: Equatable { var title: String; var paths: [String]; var index: Int }

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
    var slots: [Slot] = []
    var selectedSlot = "C1"
    var editing = false
    var busy: String?
    var toast: String?
    var backupCount = 0
    var history: [String: [SlotRecord]] = [:]
    var connected: Bool { info != nil && !slots.isEmpty }
    var changes: [Slot] { slots.filter(\.changed) }

    // Inbox
    var inbox: [InboxItem] = []

    private var checking = false
    private var toastTask: Task<Void, Never>?

    init(library: Library = Library()) { self.library = library }

    // MARK: Start, detect, read

    func start() {
        reload()
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
            library.observe(i, slots: all.map { ($0.id, $0.camName, $0.cam) })
            info = i
            slots = all
            refreshHistory()
            backupCount = library.backups().count
            if !slots.contains(where: { $0.id == selectedSlot }) { selectedSlot = slots.first?.id ?? "C1" }
            say("\(i.model) · \(banks.count) slots and the dial read · backup saved")
        } catch {
            say("Couldn't read the camera: \(error)")
        }
    }

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
    func match(_ s: RecipeSettings) -> Recipe? { recipes.first { $0.settings == s } }
    func slotsHolding(_ r: Recipe) -> [String] { slots.filter { $0.cam == r.settings }.map(\.id) }

    /// "In C1 and FS1 · 39 of your photos · last used 11 Jul"
    func whereabouts(_ r: Recipe) -> String {
        var parts: [String] = []
        let held = slotsHolding(r)
        if !held.isEmpty { parts.append("in " + held.joined(separator: ", ")) }
        else if let staged = slots.first(where: { $0.changed && $0.draft == r.settings }) { parts.append("→ \(staged.id)") }
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

    func toggleFavorite(_ r: Recipe) {
        let next = r.status == "favorite" ? ((r.shots ?? 0) > 0 ? "mine" : "tried") : "favorite"
        _ = try? library.setStatus(r.slug, status: next, note: nil)
        reload()
    }

    func setTags(_ r: Recipe, _ tags: [String]) {
        var x = r; x.tags = tags.isEmpty ? nil : tags
        _ = try? library.save(x, allowDuplicate: true)
        reload()
    }

    func show(_ paths: [String], at i: Int, title: String) {
        guard !paths.isEmpty else { return }
        preview = Preview(title: title, paths: paths, index: max(0, min(paths.count - 1, i)))
    }

    // MARK: Slots: stage, review, write

    var slot: Slot? { slots.first { $0.id == selectedSlot } }

    func update(_ id: String? = nil, _ change: (inout Slot) -> Void) {
        guard let i = slots.firstIndex(where: { $0.id == (id ?? selectedSlot) }), !slots[i].dial else { return }
        change(&slots[i])
        slots[i].draft.normalize()
    }

    /// Stage a recipe in a slot (drag onto it, or pick it). Nothing reaches the camera until Review & write.
    func put(_ r: Recipe, in slotID: String) {
        guard let s = slots.first(where: { $0.id == slotID }) else { return }
        if s.dial { say("\(slotID) is set on the camera's dial; writing it comes after a test on your camera"); return }
        update(slotID) { $0.draft = r.settings; $0.name = PTPString.bankName(r.name.uppercased()) }
        selectedSlot = slotID
        say("\(r.name) → \(slotID) · not on the camera yet")
    }

    func putBack(_ rec: SlotRecord) {
        update(rec.slot) { $0.draft = rec.settings; $0.name = rec.name }
        say("\(rec.name.isEmpty ? rec.settings.film : rec.name) staged for \(rec.slot) · review to write")
    }

    func revert(_ id: String) { update(id) { $0.draft = $0.cam; $0.name = $0.camName } }
    func revertAll() { for s in changes { revert(s.id) } }

    func freeSlot() -> String? { slots.first { !$0.dial && $0.unused && !$0.changed }?.id ?? slots.first { !$0.dial }?.id }

    /// One backup, then each changed slot: write what differs, read back, record in history.
    func writeChanges() async {
        let todo = changes
        guard !todo.isEmpty, let cam = await Cameras.shared.current() else { return }
        sheet = nil
        busy = "Writing \(todo.map(\.id).joined(separator: ", "))…"
        defer { busy = nil }
        do {
            let i = try await cam.deviceInfo()
            let banks = try await cam.readAll()
            _ = try library.saveBackup(Snapshot(date: Date().isoStamp, reason: "Before writing \(todo.map(\.id).joined(separator: ", "))", camera: i, banks: banks))
            var problems: [String] = []
            for s in todo {
                let report = try await cam.writeBank(s.index, settings: s.draft, name: s.name)
                library.recordWrite(i, slot: s.id, name: report.name, settings: report.after)
                if let k = slots.firstIndex(where: { $0.id == s.id }) {
                    slots[k].cam = report.after; slots[k].draft = report.after
                    slots[k].camName = report.name; slots[k].name = report.name
                }
                if !report.ok { problems += report.refused.map { "\(s.id) \($0.field): \($0.response)" } + report.mismatches.map { "\(s.id) \($0)" } }
            }
            refreshHistory()
            backupCount = library.backups().count
            say(problems.isEmpty ? "Wrote \(todo.map(\.id).joined(separator: ", ")) · read back OK · to shoot: dial on C, Q, pick the slot"
                                 : "Written with differences: \(problems.joined(separator: "; "))")
        } catch {
            say("Couldn't write: \(error)")
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
