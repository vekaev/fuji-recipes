import AppKit
import SwiftUI

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

/// Hands the hosting NSWindow to SwiftUI code once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    final class Probe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let v = Probe()
        v.onWindow = onWindow
        return v
    }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

/// One top bar, Photo Minimalist style: the window buttons sit in our 38 pt bar, centred on the tabs, instead of
/// a title-bar row of their own above it. The system lays the title bar out again on resize, so follow it.
@MainActor
enum TrafficLights {
    static let barHeight: CGFloat = 38
    private static var observed = Set<ObjectIdentifier>()

    static func attach(_ window: NSWindow) {
        place(in: window)
        guard observed.insert(ObjectIdentifier(window)).inserted else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                     NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
            center.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated { if let window { place(in: window) } }
            }
        }
        DispatchQueue.main.async { [weak window] in if let window { place(in: window) } }
    }

    static func place(in window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview,
              let contentHeight = container.superview?.frame.height else { return }
        var frame = container.frame
        if frame.height != barHeight || frame.maxY != contentHeight {
            frame.size.height = barHeight
            frame.origin.y = contentHeight - barHeight
            container.frame = frame
            titlebar.frame = container.bounds
        }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = window.standardWindowButton(kind) else { continue }
            let y = ((titlebar.frame.height - b.frame.height) / 2).rounded()
            if b.frame.origin.y != y { b.setFrameOrigin(NSPoint(x: b.frame.origin.x, y: y)) }
        }
    }
}
