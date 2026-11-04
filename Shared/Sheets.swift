import FujiKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// How the X-E5 picks a recipe: the film simulation dial wins; C1–C7 apply only on C (Fujifilm's manual).
/// docs/USING-SLOTS.md says the same.
struct SlotsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Shoot with C1–C7 and FS1–FS3").font(.system(size: 14, weight: .semibold))
            Text("Your X-E5 keeps recipes in ten places. The film simulation dial decides which one you shoot with.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 3)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 18) {
                        DialDrawing().sheetSize(170, 170)
                        VStack(alignment: .leading, spacing: 8) {
                            (Text("The dial wins. ").bold() + Text("On a film (PROVIA … ACROS) you shoot that film; on FS1–FS3 the recipe stored there. A custom setting's film applies ") + Text("only with the dial on C").bold() + Text(" (Fujifilm's manual)."))
                                .font(.system(size: 12)).padding(8).background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
                            numbered(["Turn the dial to **C**.", "Press **Q**: the first item is SELECT CUSTOM SETTING.", "Turn the rear command dial to **C1 … C7**."])
                        }
                    }
                    heading("Put a recipe in a slot")
                    Text("**From the app:** drop a look on a slot, or *Put in…*. It's written right away: the slot is saved first and read back after, and Undo puts the old one back. (Settings: *Ask before writing* brings back a review.)")
                    Text("**On the camera:** set the recipe's settings, then MENU/OK › IMAGE QUALITY SETTING › EDIT/SAVE CUSTOM SETTING › C3 › OK. Same screen: EDIT/CHECK, EDIT CUSTOM NAME, COPY, ERASE. Hold Q to jump there. Keep AUTO UPDATE CUSTOM SETTING on DISABLE so recipes stay exact.")
                    heading("FS1–FS3")
                    Text("IMAGE QUALITY SETTING › FILM SIMULATION DIAL SETTING › FS1–FS3: pick the film and turn FS RECIPE on. Then the dial position *is* the recipe. This app reads them; writing them comes later.")
                    Text("**Which to use:** three favourites you switch all the time → FS1–FS3. More, or a set per trip → C1–C7 with the dial on C. ISO and exposure aren't stored in either.")
                }
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            HStack { Spacer(); PillButton(title: "Done", primary: true) { dismiss() } }.padding(.top, 12)
        }
        .padding(20).sheetSize(560, 560)
    }

    private func heading(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(0.5).foregroundStyle(.secondary).padding(.top, 6)
    }

    private func numbered(_ items: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(i + 1).").foregroundStyle(.tertiary); Text(t) }
            }
        }
        .font(.system(size: 12.5))
    }
}

/// The X-E5's film simulation dial with C highlighted.
private struct DialDrawing: View {
    let positions = ["PROVIA", "Velvia", "ASTIA", "CC", "REALA", "ACROS", "FS1", "FS2", "FS3", "C"]
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r + 4, y: c.y - r + 4, width: 2 * r - 8, height: 2 * r - 8)), with: .color(.primary.opacity(0.15)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.52, y: c.y - r * 0.52, width: r * 1.04, height: r * 1.04)), with: .color(.primary.opacity(0.15)))
            var tick = Path(); tick.move(to: CGPoint(x: c.x, y: 0)); tick.addLine(to: CGPoint(x: c.x, y: 8))
            ctx.stroke(tick, with: .color(.primary), lineWidth: 2)
            for (i, t) in positions.enumerated() {
                let a = Double(i) / Double(positions.count) * 2 * .pi - .pi / 2
                let p = CGPoint(x: c.x + cos(a) * r * 0.74, y: c.y + sin(a) * r * 0.74)
                if t == "C" { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)), with: .color(.primary)) }
                ctx.draw(Text(t).font(.system(size: t.count > 3 ? 9 : 10.5, weight: t == "C" || t.hasPrefix("FS") ? .semibold : .regular))
                    .foregroundStyle(t == "C" ? Theme.paper : Color.primary), at: p)
            }
        }
    }
}

/// The five checks of `fuji doctor` and what to do when each fails (docs/CONNECT.md).
struct TroubleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [(String, String, String)] = [
        ("1 USB", "The Mac doesn't see a Fujifilm", "Camera on? Try another cable: charge-only cables look the same. USB POWER SUPPLY/COMM SETTING › AUTO. Plug straight into the Mac."),
        ("2 Camera", "On USB, but not offered as a camera", "Unplug, wait 3 s, plug in. Quit photo apps. Does Image Capture list it?"),
        ("3 Session", "Listed, but doesn't answer", "Another app holds it: Preview, Photos, Image Capture, X RAW Studio, Fujifilm Tether, Lightroom. Quit them; camera off → on."),
        ("4 Mode", "Answers as a card reader / webcam", "CONNECTION MODE › USB RAW CONV./BACKUP RESTORE, then camera off → plug in → on. The mode is picked when the cable goes in."),
        ("5 Slots", "Right mode, no slots", "X-T3, X-T30 and older bodies don't expose them. Otherwise: camera off → on."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connection check").font(.system(size: 14, weight: .semibold))
            Text("The app checks these five steps in order (like `fuji doctor` in Terminal) and shows the fix for the first one that fails.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 3).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 0) {
                ForEach(rows, id: \.0) { r in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text(r.0).fontWeight(.medium)
                        Text(r.1).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                        Text(r.2)
                    }
                    .padding(.vertical, 6)
                }
            }
            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            Text("Seen on a real X-E5: as a card reader it still answers, but offers only 5 settings and refuses the slots; Preview offers to import. After switching the mode and reconnecting with the camera off: 61 settings, C1–C7 readable.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); PillButton(title: "Done", primary: true) { dismiss() } }.padding(.top, 14)
        }
        .padding(20).sheetSize(600)
    }
}

/// Snapshots of every slot, saved on connect and before each write (in the library's backups folder).
struct BackupsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Backups").font(.system(size: 14, weight: .semibold))
            Text("Every slot is saved when the camera connects and before each write. Restoring is a write: ask Claude “restore my camera from the latest backup” for now (you'll see the changes first).")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 3).fixedSize(horizontal: false, vertical: true)
            let files = model.library.backups()
            if files.isEmpty {
                Text("No backups yet: plug in the camera.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(files, id: \.self) { url in
                            HStack {
                                Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 12, design: .monospaced))
                                Spacer()
                                #if os(macOS)
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    .buttonStyle(.plain).underline().font(.system(size: 12))
                                #endif
                            }
                            .padding(.vertical, 6)
                            .overlay(alignment: .top) { Theme.line.frame(height: 1) }
                        }
                    }
                }
                .frame(maxHeight: 300).padding(.top, 10)
            }
            HStack { Spacer(); PillButton(title: "Done", primary: true) { dismiss() } }.padding(.top, 14)
        }
        .padding(20).sheetSize(520)
    }
}

/// Before anything reaches the camera: each changed slot, what it holds now → what it will hold, field by field.
/// Write = one backup of every slot, then each slot written and read back (AppModel.writeChanges).
struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InkHeadline(text: "review.", size: 32)
            Text("A backup of every slot is saved first, and each slot is read back after writing.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.changes) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(s.id) ← \(model.match(s.draft)?.name ?? (s.name.isEmpty ? s.draft.film : s.name.capitalized))")
                                    .font(.system(size: 16, weight: .bold))
                                Spacer()
                                Button("Undo") { model.revert(s.id) }.buttonStyle(.plain).font(.system(size: 12.5))
                            }
                            let diffs = (s.name != s.camName ? ["Name: \(s.camName.isEmpty ? "—" : s.camName) → \(s.name)"] : []) + s.cam.differences(to: s.draft)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(diffs, id: \.self) { d in
                                    let parts = d.components(separatedBy: ": ")
                                    let values = parts.dropFirst().joined(separator: ": ").components(separatedBy: " → ")
                                    HStack {
                                        Text(parts.first ?? d).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                                        Text(values.first ?? "").foregroundStyle(.secondary)
                                        Text("→").foregroundStyle(.tertiary)
                                        Text(values.dropFirst().joined()).fontWeight(.semibold)
                                        Spacer()
                                    }
                                    .font(.system(size: 13)).padding(.vertical, 5)
                                    .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.plain)
                Spacer()
                Pill(title: "Write \(model.changes.count) change\(model.changes.count == 1 ? "" : "s")") { Task { await model.writeChanges() } }
                    .disabled(model.changes.isEmpty)
            }
        }
        .padding(24).sheetSize(560, 600)
        .background(Theme.paper)
    }
}

/// A recipe's settings, tags and source, behind "Settings ›" (ADR 0001: settings are on request).
/// A recipe's page: its name, description, status, tags and source are editable (Save writes the recipe file;
/// the slug, and so its photos, stay the same). The camera settings come last, read only.
/// Without a recipe (a slot that isn't one) it shows just the settings.
struct RecipeSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Recipe?
    @State private var newTag = ""

    static let statuses: [(String, String)] = [("to-try", "To try"), ("tried", "Tried"), ("mine", "Shot with"), ("favorite", "♡ Favorite"), ("rejected", "Not for me")]

    var body: some View {
        let original = model.recipe(model.settingsFor)
        let settings = original?.settings ?? model.slot?.draft ?? RecipeSettings()
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let r = draft {
                        TextField("Name", text: bind(\.name)).textFieldStyle(.plain)
                            .font(.system(size: 28, weight: .heavy)).tracking(-0.6)
                        Text(model.whereabouts(r)).font(.system(size: 13)).foregroundStyle(.secondary)
                        field("Description") {
                            TextField("What it looks like, when you use it…", text: bind(\.notes, ""), axis: .vertical)
                                .lineLimit(2...8)
                        }
                        field("Status") {
                            FlowLayout(spacing: 6) {
                                ForEach(Self.statuses, id: \.0) { key, label in
                                    Chip(title: label, on: r.status == key) { draft?.status = key }
                                }
                            }
                        }
                        field("Tags") {
                            VStack(alignment: .leading, spacing: 8) {
                                FlowLayout(spacing: 6) {
                                    let tags = r.tags ?? []
                                    ForEach(Array(Set(model.allTags + ["Leica style", "Warm", "Cool", "B&W", "Bright day", "Night", "Film", "Punchy", "Soft"] + tags)).sorted(), id: \.self) { t in
                                        Chip(title: t, on: tags.contains(t)) { toggle(t) }
                                    }
                                }
                                HStack {
                                    TextField("New tag", text: $newTag).textFieldStyle(.roundedBorder).frame(maxWidth: 200).onSubmit(addTag)
                                    Button("Add", action: addTag).buttonStyle(.plain).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                        field("Source") {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Creator", text: sourceBind(\.creator)).textFieldStyle(.roundedBorder)
                                TextField("Link", text: sourceBind(\.url)).textFieldStyle(.roundedBorder)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never).keyboardType(.URL)
                                    #endif
                                if let u = r.source?.url.flatMap(URL.init(string:)), u.scheme?.hasPrefix("http") == true {
                                    Link("Open \(u.host() ?? "link")", destination: u).font(.system(size: 12))
                                }
                            }
                        }
                    } else {
                        InkHeadline(text: (model.slot?.id ?? "settings").lowercased() + ".", size: 30)
                    }
                    field("Settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.text).font(.system(size: 13, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            if let s = original?.shooting, !s.isEmpty {
                                Text(s.sorted { $0.key < $1.key }.map { "\($0.key.replacingOccurrences(of: "_", with: " ").capitalized): \($0.value)" }.joined(separator: "\n"))
                                    .font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .textFieldStyle(.plain)
                .padding(24)
            }
            HStack {
                Button("Copy as text") { copyToPasteboard("\(draft?.name ?? model.slot?.id ?? "")\n\(settings.text)"); model.say("Copied as text") }.buttonStyle(.plain)
                Spacer()
                if draft != nil && draft != original {
                    Button("Cancel") { dismiss() }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    PillButton(title: "Save", primary: true) { save() }.keyboardShortcut(.defaultAction)
                } else {
                    PillButton(title: "Done", primary: true) { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .overlay(alignment: .top) { Theme.line.frame(height: 1) }
        }
        .sheetSize(540, 680)
        .background(Theme.paper)
        .onAppear { draft = original }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: title)
            content()
        }
        .padding(.top, 4)
    }

    private func bind(_ key: WritableKeyPath<Recipe, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0 })
    }

    private func bind(_ key: WritableKeyPath<Recipe, String?>, _ empty: String) -> Binding<String> {
        Binding(get: { draft?[keyPath: key] ?? empty }, set: { draft?[keyPath: key] = $0.isEmpty ? nil : $0 })
    }

    private func sourceBind(_ key: WritableKeyPath<Recipe.Source, String?>) -> Binding<String> {
        Binding(get: { draft?.source?[keyPath: key] ?? "" },
                set: { v in
                    if draft?.source == nil { draft?.source = Recipe.Source(kind: "manual") }
                    draft?.source?[keyPath: key] = v.isEmpty ? nil : v
                })
    }

    private func toggle(_ t: String) {
        var tags = draft?.tags ?? []
        if tags.contains(t) { tags.removeAll { $0 == t } } else { tags.append(t) }
        draft?.tags = tags.isEmpty ? nil : tags
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !(draft?.tags ?? []).contains(t) { draft?.tags = (draft?.tags ?? []) + [t] }
        newTag = ""
    }

    private func save() {
        guard var r = draft else { return }
        r.name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.name.isEmpty else { model.say("A recipe needs a name"); return }
        if model.update(r) { dismiss() }
    }
}
