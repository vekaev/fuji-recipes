import FujiKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The slot editor (E): name, load a recipe, every recipe field with segmented choices and tick dials, then
/// Revert / Write. Writing asks first, saves a backup of every slot, and reads the slot back (AppModel.write).
struct SlotEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.slot {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    TextField("Slot name", text: Binding(get: { s.name }, set: { v in model.update { $0.name = PTPString.bankName(v) } }))
                        .textFieldStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                    Button { model.editing = false } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Close (Esc)")
                }
                .padding(.horizontal, 14).frame(height: 38)
                .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        group("Load")
                        Menu("A recipe from your library…") {
                            ForEach(model.recipes, id: \.slug) { r in Button(r.name) { model.put(r, in: s.id) } }
                        }
                        .menuStyle(.borderlessButton).font(.system(size: 12))
                        .padding(.horizontal, 6).frame(height: 24).background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))

                        group("Film")
                        field("Simulation", "film") {
                            Picker("", selection: bind(\.film)) { ForEach(Film.all, id: \.self) { Text($0) } }.labelsHidden()
                        }
                        field("Grain", "grainRoughness") { Segments(options: ["Off", "Weak", "Strong"], value: bind(\.grainRoughness)) }
                        field("Grain size", "grainSize", off: s.draft.grainRoughness == "Off") { Segments(options: ["Small", "Large"], value: bind(\.grainSize)) }
                        field("Color chrome", "colorChrome") { Segments(options: ["Off", "Weak", "Strong"], value: bind(\.colorChrome)) }
                        field("FX Blue", "colorChromeFxBlue") { Segments(options: ["Off", "Weak", "Strong"], value: bind(\.colorChromeFxBlue)) }

                        group("White balance")
                        field("Mode", "wb") {
                            Picker("", selection: bind(\.wb)) { ForEach(Array(Values.wb.prefix(11)), id: \.self) { Text($0) } }.labelsHidden()
                        }
                        if s.draft.wb == "Kelvin" {
                            dial("Kelvin", "wbKelvin", value: Double(s.draft.wbKelvin ?? 5500), range: 2500...10000, step: 100, major: 10, unit: " K") { v in model.update { $0.draft.wbKelvin = Int(v) } }
                        }
                        dial("Shift red", "wbRed", value: Double(s.draft.wbRed), range: -9...9, step: 1, major: 3) { v in model.update { $0.draft.wbRed = Int(v) } }
                        dial("Shift blue", "wbBlue", value: Double(s.draft.wbBlue), range: -9...9, step: 1, major: 3) { v in model.update { $0.draft.wbBlue = Int(v) } }

                        group("Tone")
                        field("D-Range Priority", "dRangePriority") { Segments(options: ["Off", "Auto", "Weak", "Strong"], value: bind(\.dRangePriority)) }
                        let drp = s.draft.dRangePriority != "Off"
                        field("Dynamic range", "dynamicRange", off: drp) { Segments(options: ["Auto", "DR100", "DR200", "DR400"], value: bind(\.dynamicRange)) }
                        dial("Highlight", "highlight", value: s.draft.highlight, range: -2...4, step: 0.5, major: 2, off: drp) { v in model.update { $0.draft.highlight = v } }
                        dial("Shadow", "shadow", value: s.draft.shadow, range: -2...4, step: 0.5, major: 2, off: drp) { v in model.update { $0.draft.shadow = v } }
                        if s.draft.isMonochrome {
                            dial("Warm · cool", "monoWarmCool", value: Double(s.draft.monoWarmCool ?? 0), range: -9...9, step: 1, major: 3) { v in model.update { $0.draft.monoWarmCool = Int(v) } }
                            dial("Magenta · green", "monoMagentaGreen", value: Double(s.draft.monoMagentaGreen ?? 0), range: -9...9, step: 1, major: 3) { v in model.update { $0.draft.monoMagentaGreen = Int(v) } }
                        } else {
                            dial("Color", "color", value: Double(s.draft.color ?? 0), range: -4...4, step: 1, major: 2) { v in model.update { $0.draft.color = Int(v) } }
                        }

                        group("Detail")
                        dial("Sharpness", "sharpness", value: Double(s.draft.sharpness), range: -4...4, step: 1, major: 2) { v in model.update { $0.draft.sharpness = Int(v) } }
                        dial("High ISO NR", "highIsoNr", value: Double(s.draft.highIsoNr), range: -4...4, step: 1, major: 2) { v in model.update { $0.draft.highIsoNr = Int(v) } }
                        dial("Clarity", "clarity", value: Double(s.draft.clarity), range: -5...5, step: 1, major: 5) { v in model.update { $0.draft.clarity = Int(v) } }

                        Text("Drag a dial (⌥ for finer) · double-click resets · a dot marks what differs from the camera. DR400 needs ISO 640+ on the X-E5. ISO and exposure aren't stored in a slot.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                }

                HStack(spacing: 8) {
                    Text(model.askBeforeWriting ? (s.changed ? "Changed · not on the camera yet" : "Same as the camera")
                                                : (s.changed || model.busy != nil ? "Writing to the camera…" : "On the camera · changes are written as you go"))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    if model.askBeforeWriting {
                        PillButton(title: "Revert") { model.revert(s.id) }.disabled(!s.changed).opacity(s.changed ? 1 : 0.35)
                        PillButton(title: "Review", primary: true) { model.sheet = .review }.disabled(!s.changed).opacity(s.changed ? 1 : 0.35)
                    }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .overlay(alignment: .top) { Theme.line.frame(height: 1) }
            }
        }
    }

    private func bind(_ kp: WritableKeyPath<RecipeSettings, String>) -> Binding<String> {
        Binding(get: { model.slot?.draft[keyPath: kp] ?? "" }, set: { v in model.update { $0.draft[keyPath: kp] = v } })
    }

    private func changed(_ key: String) -> Bool {
        guard let s = model.slot else { return false }
        let a = Mirror(reflecting: s.draft).children.first { $0.label == key }.map { "\($0.value)" }
        let b = Mirror(reflecting: s.cam).children.first { $0.label == key }.map { "\($0.value)" }
        return a != b
    }

    private func group(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(0.5).foregroundStyle(.secondary)
            .padding(.top, 14).padding(.bottom, 4)
    }

    private func label(_ title: String, _ key: String, value: String? = nil) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            if changed(key) { Circle().frame(width: 5, height: 5) }
            Spacer()
            if let value { Text(value).fontWeight(.medium).monospacedDigit() }
        }
        .font(.system(size: 12))
    }

    private func field<C: View>(_ title: String, _ key: String, off: Bool = false, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) { label(title, key); control() }
            .padding(.vertical, 5).opacity(off ? 0.35 : 1).disabled(off)
    }

    private func dial(_ title: String, _ key: String, value: Double, range: ClosedRange<Double>, step: Double, major: Int,
                      unit: String = "", off: Bool = false, set: @escaping (Double) -> Void) -> some View {
        let shown = unit.isEmpty ? (step < 1 ? signed(value) : signed(Int(value))) : "\(Int(value))\(unit)"
        return VStack(alignment: .leading, spacing: 0) {
            label(title, key, value: shown)
            FineDial(value: value, range: range, step: step, major: major, unsigned: !unit.isEmpty, set: set,
                     reset: { set(unit.isEmpty ? 0 : 5500) })
        }
        .padding(.vertical, 4).opacity(off ? 0.35 : 1).disabled(off)
    }
}

/// Text choices in a row, the current one on a raised square (Photo Minimalist's List | Grid switcher, as text).
struct Segments: View {
    let options: [String]
    @Binding var value: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Button { value = o } label: {
                    Text(o).font(.system(size: 11.5, weight: value == o ? .medium : .regular))
                        .foregroundStyle(value == o ? .primary : .secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .background(value == o ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 3))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A tick ruler like Photo Minimalist's level ruler and Light dials: drag left/right, ⌥ for 10× finer movement,
/// double-click resets. Values snap to `step`.
struct FineDial: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let major: Int
    var unsigned = false
    let set: (Double) -> Void
    let reset: () -> Void
    @State private var start: Double?
    private var pointsPerStep: CGFloat { unsigned ? 6 : step < 1 ? 12 : 11 }

    var body: some View {
        Canvas { ctx, size in
            let mid = size.width / 2
            let lo = Int((range.lowerBound / step).rounded()), hi = Int((range.upperBound / step).rounded())
            for i in lo...hi {
                let v = Double(i) * step
                let x = mid + CGFloat((v - value) / step) * pointsPerStep
                guard x > -12, x < size.width + 12 else { continue }
                let isMajor = i % major == 0
                let h: CGFloat = isMajor ? 13 : 5
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height - h)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.primary.opacity(isMajor ? 0.55 : 0.22)), lineWidth: isMajor ? 1 : 0.5)
                if isMajor {
                    let text = v == 0 ? "0" : unsigned ? String(Int(v)) : (step < 1 ? signed(v) : signed(Int(v)))
                    ctx.draw(Text(text).font(.system(size: 9, design: .monospaced)).foregroundStyle(.primary.opacity(v == 0 ? 0.75 : 0.4)),
                             at: CGPoint(x: x, y: size.height - h - 7))
                }
            }
            var m = Path(); m.move(to: CGPoint(x: mid, y: 2)); m.addLine(to: CGPoint(x: mid, y: size.height))
            ctx.stroke(m, with: .color(.primary), lineWidth: 1.5)
        }
        .frame(height: 34)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                     .init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                #if os(macOS)
                if NSApp.currentEvent?.clickCount == 2 { return }
                #endif
                let base = start ?? value
                if start == nil { start = value }
                #if os(macOS)
                let fine = NSEvent.modifierFlags.contains(.option) ? 0.1 : 1
                #else
                let fine = 1.0
                #endif
                let next = base - Double(g.translation.width / pointsPerStep) * step * fine
                let snapped = (next / step).rounded() * step
                let v = min(max(snapped, range.lowerBound), range.upperBound)
                if v != value { set(v) }
            }
            .onEnded { _ in start = nil })
        .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        #if os(macOS)
        .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
        #endif
        .help("Drag left or right. Hold Option for finer. Double-click to reset.")
    }
}
