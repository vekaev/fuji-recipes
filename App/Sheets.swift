import FujiKit
import SwiftUI

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
                        DialDrawing().frame(width: 170, height: 170)
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
        .padding(20).frame(width: 560, height: 560)
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
                    .foregroundStyle(t == "C" ? Theme.ground : Color.primary), at: p)
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
        .padding(20).frame(width: 600)
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
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    .buttonStyle(.link).font(.system(size: 12))
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
        .padding(20).frame(width: 520)
    }
}
