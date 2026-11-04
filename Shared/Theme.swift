import ImageIO
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The owner's taste (bootstrap design-taste.md): paper, white cards, pure black ink, bold lowercase headlines ending
/// in a period, one black pill per screen, hairlines; dark: black paper, #1C1C1C cards, white ink.
enum Theme {
    #if os(macOS)
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    #else
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    #endif
    #if os(macOS)
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
    #else
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    #endif

    static let paper = dynamic(rgb(0.965, 0.961, 0.949), rgb(0, 0, 0))
    static let card = dynamic(rgb(1, 1, 1), rgb(0.11, 0.11, 0.11))
    static let raised = dynamic(rgb(0.91, 0.906, 0.89), rgb(0.18, 0.18, 0.18))
    /// Explicit ink: the Mac's .primary is an 85% black that looks grey next to the paper.
    static let ink = dynamic(rgb(0, 0, 0), rgb(1, 1, 1))
    static let line = dynamic(rgb(0, 0, 0, 0.09), rgb(1, 1, 1, 0.12))
    static let onPhoto = Color(white: 0.11).opacity(0.84)
    static let mono = Font.system(size: 11, design: .monospaced)
}

/// Light / dark / follow the system, chosen in Settings.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

/// One per screen: big, bold, lowercase, ending in a period.
struct InkHeadline: View {
    let text: String
    var size: CGFloat = 40
    var body: some View {
        Text(text).font(.system(size: size, weight: .bold)).tracking(-size * 0.025)
            .foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
    }
}

struct InkPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The black pill (primary) or a hairline-outlined pill (secondary).
struct Pill: View {
    let title: String
    var primary = true
    var wide = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 22)
                .frame(minWidth: wide ? nil : 150, maxWidth: wide ? .infinity : nil, minHeight: 46)
                .foregroundStyle(primary ? Theme.paper : Theme.ink)
                .background(primary ? Theme.ink : .clear, in: Capsule())
                .overlay { if !primary { Capsule().stroke(Theme.line, lineWidth: 1) } }
                .contentShape(Capsule())
        }
        .buttonStyle(InkPress())
    }
}

/// A filter or tag capsule: black when on, outlined when off.
struct Chip: View {
    let title: String
    var on = false
    var small = false
    var action: (() -> Void)? = nil
    var body: some View {
        let label = Text(title).font(.system(size: small ? 11 : 12.5, weight: on ? .medium : .regular))
            .padding(.horizontal, small ? 7 : 11).padding(.vertical, small ? 1 : 4)
            .foregroundStyle(on ? Theme.paper : Theme.ink)
            .background(on ? Theme.ink : .clear, in: Capsule())
            .overlay { if !on { Capsule().stroke(Color.primary.opacity(0.16), lineWidth: 1) } }
        if let action { Button(action: action) { label }.buttonStyle(.plain) } else { label }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink.opacity(0.45))
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

/// Wraps its children onto new lines.
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

/// A photo from disk, downsampled off the main thread and cached; a quiet tile while loading or when missing.
struct PhotoTile: View {
    let path: String?
    var maxPixel = 480
    var fit = false
    var fitPortrait = false
    var placeholder = "not rendered yet"
    @State private var image: CGImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            if let image {
                // Never let the photo size the tile: it always takes exactly the space it's given.
                // Portrait photos fit inside (whole photo, narrower) instead of being cut to the tile.
                let portrait = image.height > image.width
                Image(decorative: image, scale: 1).resizable()
                    .aspectRatio(contentMode: fit || (portrait && fitPortrait) ? .fit : .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Theme.raised.overlay {
                    if path == nil || missing {
                        Text(placeholder).font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(4)
                    }
                }
            }
        }
        .task(id: "\(path ?? "")#\(maxPixel)") {
            image = nil; missing = false
            guard let path else { return }
            image = await ThumbCache.shared.image(path, maxPixel: maxPixel)
            missing = image == nil
        }
    }
}

/// Thumbnails for tiles and the preview. Memory first, then a small JPEG on disk (Caches/thumbs, keyed by path, file
/// size, modification date and pixel size, so an edited photo gets a new one), else decoded from the photo and saved.
/// Decoding runs in parallel off the actor (it used to run one photo at a time), and a photo asked for twice at once
/// is decoded once.
actor ThumbCache {
    static let shared = ThumbCache()
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []
    private var inflight: [String: Task<CGImage?, Never>] = [:]

    func image(_ path: String, maxPixel: Int) async -> CGImage? {
        let key = "\(path)#\(maxPixel)"
        if let hit = cache[key] { return hit }
        if let running = inflight[key] { return await running.value }
        let task = Task.detached(priority: .userInitiated) { ThumbCache.load(path, maxPixel: maxPixel) }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image {
            cache[key] = image; order.append(key)
            if order.count > 400 { cache[order.removeFirst()] = nil }   // ~400 thumbnails in memory at most
        }
        return image
    }

    nonisolated static let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.fujirecipes").appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated static func load(_ path: String, maxPixel: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let date = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let cached = folder.appendingPathComponent(String(format: "%016llx", fnv("\(path)|\(size)|\(Int(date))|\(maxPixel)")) + ".jpg")
        if let src = CGImageSourceCreateWithURL(cached as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return cg
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                   kCGImageSourceCreateThumbnailWithTransform: true,
                                                                   kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary)
        else { return nil }
        if let dest = CGImageDestinationCreateWithURL(cached as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
        return cg
    }

    nonisolated static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}

func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : v < 0 ? "−\(-v)" : "0" }
func signed(_ v: Double) -> String {
    let a = abs(v), s = a == a.rounded() ? String(Int(a)) : String(a)
    return v > 0 ? "+\(s)" : v < 0 ? "−\(s)" : "0"
}

/// Copy text on either platform.
func copyToPasteboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

/// A compact text button for toolbars and sheets: raised grey, or ink for the primary action.
struct PillButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: primary ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .foregroundStyle(primary ? Theme.paper : Theme.ink)
                .background(primary ? Theme.ink : Theme.raised, in: Capsule())
        }
        .buttonStyle(InkPress())
    }
}

extension View {
    /// Mac sheets get a fixed size; on iPhone and iPad they size themselves.
    @ViewBuilder func sheetSize(_ w: CGFloat, _ h: CGFloat? = nil) -> some View {
        #if os(macOS)
        self.frame(width: w, height: h)
        #else
        self
        #endif
    }
}

/// A photo cropped to a fixed shape (fills it, never spills out), rounded.
/// A photo in a fixed-ratio tile: the tile's size comes from the width it's offered and `ratio` only, never from the
/// photo. Every photo fills it (portrait ones are cropped to the tile; the preview shows them whole).
struct PhotoCell: View {
    let path: String?
    var ratio: CGFloat = 1
    var maxPixel = 480
    var radius: CGFloat = 8
    var fitPortrait = false
    var placeholder = "not rendered yet"
    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { PhotoTile(path: path, maxPixel: maxPixel, fitPortrait: fitPortrait, placeholder: placeholder) }
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(Rectangle())
    }
}
