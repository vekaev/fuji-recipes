import Foundation

/// Links and screenshots waiting to become recipes: `inbox/items.json` in the library. Things land here from the
/// share sheet, pasted or dropped links, Instagram's saved-posts export, or Claude; they're read on the Mac (the
/// /recipe skill through `fuji_inbox`), then kept (a recipe with status to-try) or skipped.
public struct InboxItem: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable, CaseIterable { case queued, read, kept, skipped, failed }
    public var id: String
    public var url: String?
    public var file: String?              // a screenshot or image, under inbox/files/
    public var addedAt: String
    public var source: String             // share, paste, instagram-export, claude, drop
    public var status: Status
    public var recipe: String?            // the recipe's slug once read
    public var note: String?              // "1 value to check", "same as Cine Night except WB", why it failed

    public init(url: String?, file: String? = nil, source: String) {
        id = String(UUID().uuidString.prefix(8)).lowercased()
        self.url = url; self.file = file; self.source = source
        addedAt = Date().isoStamp; status = .queued
    }
}

public extension Library {
    private var inboxURL: URL { root.appendingPathComponent("inbox/items.json") }

    func inbox() -> [InboxItem] {
        (try? JSONDecoder().decode([InboxItem].self, from: Data(contentsOf: inboxURL))) ?? []
    }

    private func saveInbox(_ items: [InboxItem]) throws {
        try FileManager.default.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try Library.encoder.encode(items); data.append(0x0A)
        try data.write(to: inboxURL, options: .atomic)
    }

    /// Queues every reel / post / video link found in `text` (pasted links, a note, an Instagram export's JSON or
    /// HTML), skipping ones already in the inbox. Returns how many were added.
    @discardableResult
    func addToInbox(text: String, source: String) throws -> [InboxItem] {
        var items = inbox()
        let known = Set(items.compactMap(\.url))
        var added: [InboxItem] = []
        for url in Self.links(in: text) where !known.contains(url) && !added.contains(where: { $0.url == url }) {
            added.append(InboxItem(url: url, source: source))
        }
        guard !added.isEmpty else { return [] }
        items.insert(contentsOf: added, at: 0)
        try saveInbox(items)
        return added
    }

    /// Queues an image (a screenshot of a recipe card) by copying it into the inbox.
    func addToInbox(image: URL, source: String) throws -> InboxItem {
        let dir = root.appendingPathComponent("inbox/files")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var item = InboxItem(url: nil, source: source)
        let dest = dir.appendingPathComponent("\(item.id).\(image.pathExtension.isEmpty ? "jpg" : image.pathExtension)")
        try FileManager.default.copyItem(at: image, to: dest)
        item.file = dest.path
        var items = inbox(); items.insert(item, at: 0)
        try saveInbox(items)
        return item
    }

    func updateInbox(_ id: String, status: InboxItem.Status, recipe: String? = nil, note: String? = nil) throws {
        var items = inbox()
        guard let i = items.firstIndex(where: { $0.id == id }) else { throw CameraError("No inbox item \(id).") }
        items[i].status = status
        if let recipe { items[i].recipe = recipe }
        if let note { items[i].note = note }
        try saveInbox(items)
    }

    /// Instagram reels and posts, TikTok and YouTube links in any text, normalised (no tracking query), in order.
    static func links(in text: String) -> [String] {
        let pattern = #"https?://(?:www\.)?(?:instagram\.com/(?:[A-Za-z0-9_.]+/)?(?:reel|reels|p|tv)/[A-Za-z0-9_-]+|tiktok\.com/@[A-Za-z0-9_.]+/video/\d+|vm\.tiktok\.com/[A-Za-z0-9]+|(?:youtube\.com/shorts/|youtu\.be/)[A-Za-z0-9_-]+)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let cleaned = text.replacingOccurrences(of: "\\/", with: "/")   // JSON exports escape slashes
        var out: [String] = []
        for m in re.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            guard let r = Range(m.range, in: cleaned) else { continue }
            var u = String(cleaned[r]).replacingOccurrences(of: "/reels/", with: "/reel/")
            if !u.hasSuffix("/") && u.contains("instagram.com") { u += "/" }
            if !out.contains(u) { out.append(u) }
        }
        return out
    }
}
