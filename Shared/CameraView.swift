import FujiKit
import SwiftUI

/// Design F as a page: the camera's slots with their looks; the selected slot big (its photos, since when, last used,
/// looks to swap in, its history with Put back). Settings and the editor only behind "Settings ›".
/// No camera ready: the connect guide with the live check.
struct CameraView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular

    var body: some View {
        if !model.connected {
            SetupView()
        } else if regular {
            HStack(spacing: 0) {
                SlotList().frame(width: 300).background(Theme.card).overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
                SlotDetail().frame(maxWidth: .infinity)
                if model.editing, model.slot != nil {
                    SlotEditor().frame(width: 290).background(Theme.card)
                        .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.editing)
            .focusable().focusEffectDisabled()
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.escape) { if model.editing { model.editing = false; return .handled }; return .ignored }
        } else {
            NavigationStack {
                SlotList()
                    .navigationDestination(for: String.self) { id in
                        SlotDetail().onAppear { model.selectedSlot = id }
                    }
            }
        }
    }

    private func move(_ d: Int) {
        guard let i = model.slots.firstIndex(where: { $0.id == model.selectedSlot }) else { return }
        model.selectedSlot = model.slots[max(0, min(model.slots.count - 1, i + d))].id
    }
}

private struct SlotList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                InkHeadline(text: (model.info?.model.lowercased() ?? "camera") + ".", size: regular ? 30 : 34).padding(.bottom, 2)
                Text("Dial on C, then Q to pick C1–C7. FS1–FS3 are the dial.").font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.bottom, 6)
                ForEach(model.slots.filter { !$0.dial }) { row($0) }
                if model.slots.contains(where: \.dial) {
                    SectionTitle(text: "Film simulation dial").padding(.top, 10)
                    ForEach(model.slots.filter(\.dial)) { row($0) }
                }
                if model.askBeforeWriting && !model.changes.isEmpty {
                    Pill(title: "Review \(model.changes.count) change\(model.changes.count > 1 ? "s" : "")", wide: true) { model.sheet = .review }.padding(.top, 10)
                }
                Toggle("Ask before writing", isOn: Binding(get: { model.askBeforeWriting }, set: { model.askBeforeWriting = $0 }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.top, 14).padding(.horizontal, 6)
            }
            .padding(.horizontal, 14).padding(.vertical, regular ? 22 : 12)
        }
        .background(regular ? Theme.card : Theme.paper)
    }

    @ViewBuilder private func row(_ s: AppModel.Slot) -> some View {
        if regular {
            content(s)
                .background(model.selectedSlot == s.id ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { model.selectedSlot = s.id }
                .pointer()
                .dropDestination(for: String.self) { items, _ in
                    guard let r = model.recipe(items.first) else { return false }
                    model.put(r, in: s.id); return true
                }
        } else {
            NavigationLink(value: s.id) { content(s).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).pointer()
        }
    }

    private func content(_ s: AppModel.Slot) -> some View {
        let r = model.match(s.draft)
        let empty = s.unused && !s.changed
        return HStack(spacing: 10) {
            ZStack {
                if let p = r.flatMap({ model.photos($0).first }) { PhotoTile(path: p, maxPixel: 160) }
                else { Theme.raised.overlay(Text(s.id).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)) }
            }
            .frame(width: 58, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(s.id).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Text(empty ? "Empty" : (r?.name ?? (s.name.isEmpty ? s.draft.film : s.name.capitalized)))
                        .font(.system(size: 14, weight: empty ? .regular : .semibold)).foregroundStyle(empty ? .secondary : .primary).lineLimit(1)
                    if s.changed { Text("● new").font(.system(size: 11, weight: .semibold)) }
                }
                let dupes = model.duplicates(of: s)
                Text(empty ? "Provia defaults" : s.draft.film + (r == nil ? " · not in your recipes" : "") + (dupes.isEmpty ? "" : " · also in " + dupes.joined(separator: ", ")))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
    }
}

struct SlotDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular

    var body: some View {
        if let s = model.slot {
            let r = model.match(s.draft)
            let photos = r.map { model.photos($0) } ?? []
            let hist = model.history[s.id] ?? []
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        if !photos.isEmpty {
                            PhotoTile(path: photos.first, maxPixel: 700)
                                .frame(width: regular ? 190 : 96, height: regular ? 127 : 96)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture { model.show(photos, at: 0, title: r?.name ?? s.id) }.pointer()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            InkHeadline(text: "\(s.id.lowercased()): \((s.unused && !s.changed) ? "empty" : (r?.name ?? (s.name.isEmpty ? s.draft.film : s.name)).lowercased()).", size: regular ? 34 : 28)
                            Text(subtitle(s, r, hist)).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 14) {
                                Button(model.editing ? "Hide settings" : "Settings ›") { model.editing.toggle() }.buttonStyle(.plain).pointer()
                                if s.changed && model.askBeforeWriting { Button("Revert") { model.revert(s.id) }.buttonStyle(.plain).pointer() }
                                Button("How to shoot with it") { model.sheet = .help }.buttonStyle(.plain).pointer().foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13, weight: .medium)).padding(.top, 2)
                        }
                    }
                    if photos.count > 1 {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: regular ? 6 : 3), spacing: 6) {
                            ForEach(Array(photos.prefix(regular ? 12 : 9).enumerated()), id: \.offset) { i, p in
                                PhotoCell(path: p, ratio: 3 / 2, maxPixel: 360, radius: 6).onTapGesture { model.show(photos, at: i, title: r?.name ?? s.id) }
                            }
                        }
                    }
                    if s.dial {
                        Text("Turn the dial to \(s.id) to shoot with it. Written through the camera's settings file; its WB shift and B&W toning stay as set on the camera for now.")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Group {
                        SectionTitle(text: "Swap in · \(model.askBeforeWriting ? "" : "written right away · ")what's there now moves to \(s.id)'s history")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: regular ? 4 : 2), spacing: 12) {
                            ForEach(model.recipes.filter { $0.settings != s.draft }.prefix(regular ? 8 : 6), id: \.slug) { pick($0, slot: s) }
                        }
                    }
                    if hist.count > 1 || (hist.count == 1 && !(s.unused && !s.changed)) {
                        SectionTitle(text: "\(s.id)'s history")
                        VStack(spacing: 0) {
                            ForEach(hist) { rec in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.match(rec.settings)?.name ?? (rec.name.isEmpty ? rec.settings.film : rec.name.capitalized)).font(.system(size: 14, weight: .semibold))
                                        Text(span(rec)).font(.system(size: 12.5)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if rec.to != nil { Pill(title: "Put back", primary: false) { model.putBack(rec) }.fixedSize().scaleEffect(0.85) }
                                }
                                .padding(.vertical, 6)
                                .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                            }
                        }
                    }
                    if model.askBeforeWriting && !model.changes.isEmpty && !regular {
                        Pill(title: "Review \(model.changes.count) change\(model.changes.count > 1 ? "s" : "")", wide: true) { model.sheet = .review }
                    }
                }
                .padding(.horizontal, regular ? 32 : 18).padding(.vertical, regular ? 26 : 16)
                .frame(maxWidth: 980, alignment: .leading)
            }
            .background(Theme.paper)
            #if os(iOS)
            .sheet(isPresented: Binding(get: { model.editing && !regular }, set: { model.editing = $0 })) { SlotEditor().presentationDetents([.large]) }
            #endif
        }
    }

    private func subtitle(_ s: AppModel.Slot, _ r: Recipe?, _ hist: [SlotRecord]) -> String {
        if s.unused && !s.changed { return "Nothing here yet. Drop or pick a recipe below." }
        var p: [String] = []
        if s.changed { p.append(model.askBeforeWriting ? "changed, not on the camera yet" : "writing…") }
        let dupes = model.duplicates(of: s)
        if !dupes.isEmpty { p.append("same recipe as " + dupes.joined(separator: " and ")) }
        if let from = hist.first?.from { p.append("since \(AppModel.short(from))") }
        if let r {
            if let last = r.lastShot { p.append("last used \(AppModel.short(last))") }
            if let n = r.shots, n > 0 { p.append("\(n) photos with it") }
        } else { p.append("not in your recipes") }
        return p.joined(separator: " · ")
    }

    private func span(_ r: SlotRecord) -> String {
        let from = r.from.map(AppModel.short) ?? "before tracking"
        return r.to == nil ? "now · since \(from)" : "\(from) – \(AppModel.short(r.to!))\(r.how == "on the camera" ? " · set on the camera" : "")"
    }

    private func pick(_ r: Recipe, slot: AppModel.Slot) -> some View {
        Button { model.put(r, in: slot.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                PhotoCell(path: model.photos(r).first, ratio: 3 / 2, maxPixel: 400)
                Text(r.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(model.whereabouts(r)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain).pointer()
    }
}

/// Mac / wide iPad: a slot's page over the looks (click a slot in the column). Its settings dials open beside it.
struct SlotSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            SlotDetail()
            if model.editing, model.slot != nil {
                SlotEditor().frame(width: 290).background(Theme.card)
                    .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { model.closeSheet() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30)
            }
            .buttonStyle(.plain).pointer().foregroundStyle(.secondary).padding(8).help("Close (Esc)")
            .opacity(model.editing ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.18), value: model.editing)
        .sheetSize(model.editing ? 940 : 680, 640)
        .onDisappear { model.editing = false }
    }
}
