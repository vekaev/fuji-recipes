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

/// ⌘V in the Studio: a .RAF copied in Finder becomes the Studio's RAW, a copied photo (a file, or an image copied from
/// a browser or Photos) the look to match (`AppModel.pasteIntoStudio`). Only while the Studio tab is showing and no
/// sheet is open; a text field being edited keeps its own Paste, and anything else on the clipboard falls through.
/// The key code catches ⌘V on any keyboard layout (Cyrillic "м" included).
@MainActor
enum StudioPaste {
    private static var monitor: Any?

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command, e.keyCode == 9 || e.charactersIgnoringModifiers?.lowercased() == "v",
                  model.tab == .studio, model.sheet == nil, model.preview == nil,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return e }
            return paste(into: model) ? nil : e
        }
    }

    static func paste(into model: AppModel) -> Bool {
        let pb = NSPasteboard.general
        let files = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        var image: (data: Data, name: String)?
        if files.isEmpty {
            if let d = pb.data(forType: .png) { image = (d, AppModel.pastedName(ext: "png")) }
            else if let d = pb.data(forType: .tiff), let png = NSBitmapImageRep(data: d)?.representation(using: .png, properties: [:]) {
                image = (png, AppModel.pastedName(ext: "png"))
            }
        }
        return model.pasteIntoStudio(files: files, image: image)
    }
}
