import AppKit
import SwiftUI

/// Photo Minimalist's palette (its App/Support.swift): white page, warm-grey panel, raised grey for selection,
/// 9% hairlines; primary is the only accent. Light and dark follow the system.
enum Theme {
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    private static func gray(_ w: CGFloat) -> NSColor { NSColor(white: w, alpha: 1) }

    static let ground = dynamic(gray(1.0), gray(0.098))
    static let panel = dynamic(NSColor(red: 0.969, green: 0.969, blue: 0.961, alpha: 1), gray(0.125))
    static let raised = dynamic(gray(0.925), gray(0.18))
    static let stage = dynamic(NSColor(red: 0.949, green: 0.949, blue: 0.941, alpha: 1), gray(0.078))
    static let line = Color.primary.opacity(0.09)
    /// Chips and cards drawn on top of photos.
    static let onPhoto = Color(white: 0.11).opacity(0.84)
}

/// Light / dark / follow the system, chosen in Settings.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

/// The empty part of the top bar moves the window; a double-click zooms (Photo Minimalist's WindowDragArea).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// A small text button in the house style: raised grey, or black for the primary action.
struct PillButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: primary ? .medium : .regular))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundStyle(primary ? Theme.ground : Color.primary)
                .background(primary ? Color.primary : Theme.raised, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

/// Menu path on the camera, e.g. MENU/OK › network/USB › CONNECTION MODE.
struct Crumbs: View {
    let parts: [String]
    var body: some View {
        FlowLayout(spacing: 3) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                if i > 0 { Text("›").font(.system(size: 11)).foregroundStyle(.tertiary) }
                Text(p).font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}

/// Wraps its children onto new lines (Photo Minimalist's FlowRow).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height); maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}
