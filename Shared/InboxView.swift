import FujiKit
import SwiftUI
import UniformTypeIdentifiers

/// Design E: everything waiting to become a recipe. Paste or drop links (many at once), screenshots, or Instagram's
/// saved-posts export; reels are read on the Mac by Claude / the /recipe skill (fuji_inbox), then kept or skipped here.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular
    @State private var pasted = ""
    @State private var importing = false
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    InkHeadline(text: "inbox.", size: regular ? 40 : 34)
                    Text("Reels you saved, read on your Mac. Keep the ones you want to try.")
                        .font(regular ? .title3 : .body).foregroundStyle(.secondary)
                }
                addBox
                if model.queuedCount > 0 {
                    HStack(spacing: 10) {
                        Text("\(model.queuedCount) waiting to be read").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        PillButton(title: "Copy “read my inbox” for Claude") {
                            copyToPasteboard("Read my Fuji Recipes inbox: use fuji_inbox to list the queued reels, read each with the /recipe skill, save them with fuji_save_recipe (status to-try, credit the creator, add tags), and mark each with fuji_inbox_resolve.")
                            model.say("Copied: paste it into Claude")
                        }
                    }
                    .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                let review = model.toReview
                if !review.isEmpty {
                    SectionTitle(text: "Ready to review · \(review.count)")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: regular ? 3 : 1), spacing: 14) {
                        ForEach(review) { ReadCard(item: $0) }
                    }
                }
                let waiting = model.inbox.filter { $0.status == .queued || $0.status == .failed }
                if !waiting.isEmpty {
                    SectionTitle(text: "Waiting")
                    VStack(spacing: 0) {
                        ForEach(waiting.prefix(60)) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.file != nil ? "photo" : "link").foregroundStyle(.secondary).frame(width: 18)
                                Text(item.url ?? URL(fileURLWithPath: item.file ?? "").lastPathComponent)
                                    .font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(item.status == .failed ? (item.note ?? "couldn't read") : item.source.replacingOccurrences(of: "-", with: " "))
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8).overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                        }
                        if waiting.count > 60 { Text("and \(waiting.count - 60) more").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                let done = model.inbox.filter { $0.status == .kept || $0.status == .skipped }
                if !done.isEmpty {
                    Text("\(done.filter { $0.status == .kept }.count) kept · \(done.filter { $0.status == .skipped }.count) skipped")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, regular ? 34 : 18).padding(.vertical, regular ? 26 : 16)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .html, .plainText, .image], allowsMultipleSelection: true) { result in
            for url in (try? result.get()) ?? [] {
                let ok = url.startAccessingSecurityScopedResource()
                model.addToInbox(file: url)
                if ok { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private var addBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste or drop links, screenshots, or your Instagram export").font(.system(size: 15, weight: .semibold))
            Text("Many at once is fine. Instagram ▸ Accounts Center ▸ Your information and permissions ▸ Download your information ▸ Saved: drop the file here and every saved reel is queued.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            let field = TextField(text: $pasted, axis: .vertical) { Text(verbatim: "https://www.instagram.com/reel/…") }
                .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)).lineLimit(1...4)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never).keyboardType(.URL)
                #endif
                .padding(9).background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            let buttons = Group {
                PillButton(title: "Add", primary: true) { model.addToInbox(text: pasted); pasted = "" }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                PillButton(title: "Import file…") { importing = true }
            }
            if regular {
                HStack(alignment: .top, spacing: 8) { field; buttons }
            } else {
                field
                HStack(spacing: 8) { buttons }
            }
        }
        .padding(16)
        .background(dropTargeted ? Theme.raised : Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(dropTargeted ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            for u in urls { if u.isFileURL { model.addToInbox(file: u) } else { model.addToInbox(text: u.absoluteString, source: "drop") } }
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }
}

private struct ReadCard: View {
    @Environment(AppModel.self) private var model
    let item: InboxItem

    var body: some View {
        let r = model.recipe(item.recipe)
        let photos = r.map { model.photos($0) } ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    PhotoCell(path: i < photos.count ? photos[i] : nil, ratio: 1, maxPixel: 360, radius: 6, placeholder: "")
                        .onTapGesture { if i < photos.count { model.show(photos, at: i, title: r?.name ?? "Reel") } }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(r?.name ?? "Read").font(.system(size: 16, weight: .bold)).lineLimit(1)
                Spacer()
                Text(r?.source?.creator ?? "").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text([r?.settings.film, item.note].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 6) {
                Pill(title: "Keep", wide: true) { model.keep(item) }
                Pill(title: "Skip", primary: false) { model.skip(item) }.fixedSize()
            }
            .scaleEffect(0.86, anchor: .leading)
            Button("Settings ›") { model.settingsFor = item.recipe; model.sheet = .settings }.buttonStyle(.plain).font(.system(size: 12))
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }
}
