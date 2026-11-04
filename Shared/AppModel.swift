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
    enum Sheet: String, Identifiable { case help, trouble, backups, review, settings, slot, connect; var id: String { rawValue } }

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
    /// Off (the default): a look put in a slot, Put back or a dial edit is written right away (a backup of that slot
    /// first, read back after, Undo in the toast). On: changes wait for the review sheet.
    var askBeforeWriting = UserDefaults.standard.bool(forKey: "askBeforeWriting") {
        didSet { UserDefaults.standard.set(askBeforeWriting, forKey: "askBeforeWriting") }
    }
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
            slots = all
            refreshHistory()
            backupCount = library.backups().count
            if !slots.contains(where: { $0.id == selectedSlot }) { selectedSlot = slots.first?.id ?? "C1" }
            if sheet == .connect { sheet = nil }
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

    /// Stage a recipe in a slot (drag onto it, or pick it). Nothing reaches the camera until Review & write.
    func put(_ r: Recipe, in slotID: String) {
        guard let s = slots.first(where: { $0.id == slotID }) else { return }
        if s.dial { say("\(slotID) is set on the camera's dial; writing it comes after a test on your camera"); return }
        update(slotID) { $0.draft = r.settings; $0.name = PTPString.bankName(r.name.uppercased()) }
        selectedSlot = slotID
        if askBeforeWriting { say("\(r.name) → \(slotID) · not on the camera yet") } else { scheduleWrite(after: 0) }
    }

    func putBack(_ rec: SlotRecord) {
        update(rec.slot) { $0.draft = rec.settings; $0.name = rec.name }
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
            for s in todo { old.append(try await cam.readBank(s.index)) }
            _ = try library.saveBackup(Snapshot(date: Date().isoStamp, reason: "Before writing \(todo.map(\.id).joined(separator: ", "))", camera: i, banks: old))
            var problems: [String] = []
            for s in todo {
                let report = try await cam.writeBank(s.index, settings: s.draft, name: s.name)
                library.recordWrite(i, slot: s.id, name: report.name, settings: report.after)
                if let k = slots.firstIndex(where: { $0.id == s.id }) {
                    slots[k].cam = report.after; slots[k].camName = report.name
                    // A newer edit made while this one was being written stays a draft (and is written next).
                    if slots[k].draft == s.draft { slots[k].draft = report.after }
                    if slots[k].name == s.name { slots[k].name = report.name }
                }
                if !report.ok { problems += report.refused.map { "\(s.id) \($0.field): \($0.response)" } + report.mismatches.map { "\(s.id) \($0)" } }
            }
            refreshHistory()
            backupCount = library.backups().count
            let what = todo.map { "\(match($0.draft)?.name ?? ($0.name.isEmpty ? $0.draft.film : $0.name.capitalized)) in \($0.id)" }.joined(separator: ", ")
            if !problems.isEmpty {
                say("Written with differences: \(problems.joined(separator: "; "))")
            } else if askBeforeWriting {
                say("Wrote \(todo.map(\.id).joined(separator: ", ")) · read back OK · to shoot: dial on C, Q, pick the slot")
            } else {
                say("\(what) · on the camera", action: ToastAction(title: "Undo") { [weak self] in
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
        let seconds: UInt64 = action == nil ? 3_500_000_000 : 8_000_000_000
        toastTask = Task { try? await Task.sleep(nanoseconds: seconds); if !Task.isCancelled { toast = nil; toastAction = nil } }
    }
}

extension RecipeSettings {
    /// A slot nobody has set: Provia, everything at 0 / Off / Auto.
    static var factory: RecipeSettings { var s = RecipeSettings(); s.normalize(); return s }
}
