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
                    Text("**From the Mac:** select a recipe, *Put in a slot*, check the changes, Write. A backup of every slot is saved first and the slot is read back.")
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
struct RecipeSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        let r = model.recipe(model.settingsFor)
        let settings = r?.settings ?? model.slot?.draft ?? RecipeSettings()
        let title = r?.name ?? model.slot?.id ?? "Settings"
        VStack(alignment: .leading, spacing: 14) {
            InkHeadline(text: title.lowercased() + ".", size: 30)
            if let r {
                Text(model.whereabouts(r)).font(.system(size: 13)).foregroundStyle(.secondary)
                SectionTitle(text: "Tags")
                FlowLayout(spacing: 6) {
                    let tags = r.tags ?? []
                    ForEach(Array(Set(model.allTags + ["Leica style", "Warm", "Cool", "B&W", "Bright day", "Night", "Film", "Punchy", "Soft"] + tags)).sorted(), id: \.self) { t in
                        Chip(title: t, on: tags.contains(t)) { model.setTags(r, tags.contains(t) ? tags.filter { $0 != t } : tags + [t]) }
                    }
                }
                HStack {
                    TextField("New tag", text: $newTag).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                        .onSubmit { addTag(r) }
                    Button("Add") { addTag(r) }.buttonStyle(.plain).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            SectionTitle(text: "Settings")
            ScrollView {
                Text(settings.text).font(.system(size: 13, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if let s = r?.shooting, !s.isEmpty {
                    Text(s.sorted { $0.key < $1.key }.map { "\($0.key.replacingOccurrences(of: "_", with: " ").capitalized): \($0.value)" }.joined(separator: "\n"))
                        .font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                if let src = r?.source, let url = src.url.flatMap(URL.init(string:)) {
                    Link("\(src.creator ?? "Source"): \(url.host() ?? url.absoluteString)", destination: url).font(.system(size: 13)).padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Button("Copy as text") { copyToPasteboard("\(title)\n\(settings.text)"); model.say("Copied as text") }.buttonStyle(.plain)
                Spacer()
                PillButton(title: "Done", primary: true) { dismiss() }
            }
        }
        .padding(24).sheetSize(520, 640)
        .background(Theme.paper)
    }

    private func addTag(_ r: Recipe) {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        model.setTags(r, (r.tags ?? []) + [t]); newTag = ""
    }
}
