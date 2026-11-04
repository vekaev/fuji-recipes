import FujiKit
import SwiftUI

/// Camera connected: slots on the left (C1–C7, then the film simulation dial, read only), the selected slot in the
/// pane (a photo of the matching recipe, a chip, the info card), and the 280 pt editor on the right (E).
struct SlotsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            if model.showSidebar {
                SlotList().frame(width: 320).background(Theme.panel)
                    .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
            }
            SlotPane()
            if model.editing, let s = model.slot, !s.dial {
                SlotEditor().frame(width: 280).background(Theme.panel)
                    .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.editing)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.escape) { if model.editing { model.editing = false; return .handled }; return .ignored }
    }

    private func move(_ d: Int) {
        guard let i = model.slots.firstIndex(where: { $0.id == model.selectedSlot }) else { return }
        let j = max(0, min(model.slots.count - 1, i + d))
        model.selectedSlot = model.slots[j].id
        if model.slots[j].dial { model.editing = false }
    }
}

private struct SlotList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                tabLabel("Slots", model.slots.filter { !$0.dial }.count, on: true)
                tabLabel("Changed", model.slots.filter(\.changed).count, on: false)
                Button { model.sheet = .backups } label: { tabLabel("Backups", model.backupCount, on: false) }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.leading, 16).frame(height: 32)
            .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.slots.filter { !$0.dial }) { row($0) }
                        if model.slots.contains(where: \.dial) {
                            Text("FILM SIMULATION DIAL · READ ONLY").font(.system(size: 10.5, weight: .medium)).tracking(0.5)
                                .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
                            ForEach(model.slots.filter(\.dial)) { row($0) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selectedSlot) { _, id in withAnimation { proxy.scrollTo(id) } }
            }
        }
    }

    private func tabLabel(_ t: String, _ n: Int, on: Bool) -> some View {
        HStack(spacing: 3) {
            Text(t).fontWeight(on ? .semibold : .regular)
            Text("\(n)").foregroundStyle(.tertiary).monospacedDigit()
        }
        .font(.system(size: 12.5)).foregroundStyle(on ? .primary : .secondary)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(on ? Color.primary : .clear).frame(height: 1.5) }
    }

    private func row(_ s: AppModel.Slot) -> some View {
        let r = model.match(s.draft)
        let selected = model.selectedSlot == s.id
        return HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                if let p = r?.samples?.first { SampleImage(path: p) } else {
                    Theme.raised.overlay(Text(s.id).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary))
                }
                if r?.samples?.first != nil {
                    Text(s.id).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                        .padding(.horizontal, 3).background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 2)).padding(3)
                }
            }
            .frame(width: 58, height: 40).clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if s.unused && !s.changed { Text("Unused").foregroundStyle(.tertiary) } else {
                        Text(s.name.isEmpty ? (r?.name ?? s.draft.film) : s.name).lineLimit(1)
                    }
                    if s.changed { Circle().frame(width: 5, height: 5).help("Changed, not written yet") }
                }
                .font(.system(size: 12.5))
                Text(s.unused && !s.changed ? "Provia defaults" : s.draft.film + (r.map { " · \($0.name)" } ?? " · not in your recipes"))
                    .font(.system(size: 11)).foregroundStyle(r != nil ? .primary : .secondary).lineLimit(1)
                Text(s.unused && !s.changed ? " " : s.draft.summary.replacingOccurrences(of: s.draft.film + " · ", with: ""))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(selected ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedSlot = s.id
            if s.dial { model.editing = false }
            if NSApp.currentEvent?.clickCount == 2, !s.dial { model.editing = true }
        }
        .id(s.id)
    }
}

private struct SlotPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.slot {
            let r = model.match(s.draft)
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(s.id + (s.name.isEmpty ? "" : " · " + s.name)).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text(s.unused && !s.changed ? "Unused" : s.draft.film).font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 6)
                    Spacer()
                    if !s.dial {
                        icon("slider.horizontal.3", "Edit slot (E)", on: model.editing) { model.editing.toggle() }
                    }
                    icon("doc.on.doc", "Copy as text") { model.copyText(s.draft, name: s.name.isEmpty ? s.id : s.name) }
                    icon("bookmark", "Save as a recipe") { model.saveAsRecipe(s) }
                    icon("clock", "Backups") { model.sheet = .backups }
                    icon("questionmark", "How to shoot with a slot") { model.sheet = .help }
                }
                .padding(.leading, 16).padding(.trailing, 8).frame(height: 38)
                .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }

                ZStack {
                    Theme.stage
                    if let p = r?.samples?.first {
                        SampleImage(path: p, fit: true, maxPixel: 1600).padding(32)
                    } else {
                        VStack(spacing: 6) {
                            Text(s.id).font(.system(size: 34, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)
                            Text(s.unused && !s.changed ? "Unused slot · Provia defaults\nLoad a recipe in the editor (E)" : "No photo for these settings yet")
                                .multilineTextAlignment(.center).font(.system(size: 12)).foregroundStyle(.secondary)
                            Button(hint(s)) { model.sheet = .help }.buttonStyle(.link).font(.system(size: 12))
                        }
                    }
                }
                .overlay(alignment: .topTrailing) { chip(s, r).padding(18) }
                .overlay(alignment: .bottomLeading) {
                    if !(s.unused && !s.changed) { InfoCard(settings: s.draft, footer: [r?.name, hint(s)].compactMap { $0 }).padding(18) }
                }
            }
        } else {
            Theme.stage
        }
    }

    private func hint(_ s: AppModel.Slot) -> String { s.dial ? "To shoot: turn the dial to \(s.id)" : "To shoot: dial on C · Q · \(s.id)" }

    @ViewBuilder private func chip(_ s: AppModel.Slot, _ r: Recipe?) -> some View {
        HStack(spacing: 8) {
            if s.dial { Text("Set on the camera's dial") }
            else if s.changed {
                Text("Changed"); Text("·").opacity(0.4)
                Button("Write \(s.id)") { model.editing = true; model.confirmingWrite = true }.buttonStyle(.plain).fontWeight(.semibold)
            } else if let r { Text(r.name); Text("·").opacity(0.4); Text("on the camera") }
            else if s.unused { Text("Empty") }
            else { Text("Not in your recipes"); Text("·").opacity(0.4); Button("Save") { model.saveAsRecipe(s) }.buttonStyle(.plain).fontWeight(.semibold) }
        }
        .font(.system(size: 12)).foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.onPhoto, in: RoundedRectangle(cornerRadius: 6))
    }

    private func icon(_ name: String, _ help: String, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13)).frame(width: 28, height: 26)
                .background(on ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(on ? .primary : .secondary).help(help)
    }
}

/// The dark card in the photo's corner (Photo Minimalist's Info card): the recipe in the camera's menu order.
struct InfoCard: View {
    let settings: RecipeSettings
    var footer: [String] = []

    var body: some View {
        let s = settings
        VStack(alignment: .leading, spacing: 2) {
            row("Film", s.film)
            row("Grain", s.grainRoughness == "Off" ? "Off" : "\(s.grainRoughness), \(s.grainSize)")
            row("Color chrome", "\(s.colorChrome) · FX Blue \(s.colorChromeFxBlue)")
            row("White balance", "\(s.wb == "Kelvin" ? "\(s.wbKelvin ?? 0) K" : s.wb), R \(signed(s.wbRed)) B \(signed(s.wbBlue))")
            row("Tone", s.dRangePriority != "Off" ? "D-Range Priority \(s.dRangePriority)" : "\(s.dynamicRange) · H \(signed(s.highlight)) · S \(signed(s.shadow))")
            if let c = s.color { row("Color", signed(c)) } else { row("Toning", "WC \(signed(s.monoWarmCool ?? 0)) · MG \(signed(s.monoMagentaGreen ?? 0))") }
            row("Sharp · NR · Clar.", "\(signed(s.sharpness)) · \(signed(s.highIsoNr)) · \(signed(s.clarity))")
            ForEach(footer, id: \.self) { Text($0).opacity(0.6).padding(.top, 2) }
        }
        .font(.system(size: 11.5)).foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.onPhoto, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(k).opacity(0.55).frame(width: 108, alignment: .leading)
            Text(v)
        }
    }
}

func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : v < 0 ? "−\(-v)" : "0" }
func signed(_ v: Double) -> String {
    let a = abs(v), s = a == a.rounded() ? String(Int(a)) : String(a)
    return v > 0 ? "+\(s)" : v < 0 ? "−\(s)" : "0"
}
