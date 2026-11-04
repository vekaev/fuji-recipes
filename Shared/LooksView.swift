import FujiKit
import SwiftUI

/// Design D, the look book: each recipe is its name, then how it looks (the same scenes in every recipe when
/// rendered, else your photos and the creator's frames), then tags; settings only behind "Settings ›".
/// Mac / wide iPad: drag a look onto a slot in the right column. iPhone: "Put in a slot" picks one.
struct LooksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        InkHeadline(text: "recipes.", size: regular ? 40 : 34)
                        Text(model.recipes.isEmpty ? "Your recipes appear here. Add some in Add recipes, or ask Claude to find the ones in your photos."
                                                   : regular ? "How each recipe looks. Click a photo to see it big, drag a recipe onto a slot." : "How each recipe looks. Tap a photo to see it big.")
                            .font(regular ? .title3 : .body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        #if os(iOS)
                        Button(model.recipes.isEmpty ? "Choose your Fuji Recipes folder" : "Library: \(model.library.root.lastPathComponent)") { model.pickingLibrary = true }
                            .buttonStyle(.plain).pointer().font(.system(size: 14, weight: .semibold)).padding(.top, 2)
                        #endif
                    }
                    filters
                    LazyVStack(spacing: 12) {
                        ForEach(model.visibleRecipes, id: \.slug) { LookCard(recipe: $0) }
                    }
                }
                .padding(.horizontal, regular ? 34 : 18).padding(.vertical, regular ? 26 : 16)
                .frame(maxWidth: 1100, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            if regular { SlotColumn().frame(width: 290) }
        }
        .background(Theme.paper)
    }

    private var filters: some View {
        @Bindable var model = model
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "All \(model.recipes.count)", on: model.tagFilter == nil) { model.tagFilter = nil }
                ForEach(model.allTags, id: \.self) { t in Chip(title: t, on: model.tagFilter == t) { model.tagFilter = model.tagFilter == t ? nil : t } }
                Chip(title: "Shot with", on: model.tagFilter == "status:mine") { model.tagFilter = model.tagFilter == "status:mine" ? nil : "status:mine" }
                Chip(title: "To try", on: model.tagFilter == "status:to-try") { model.tagFilter = model.tagFilter == "status:to-try" ? nil : "status:to-try" }
                Chip(title: "♡", on: model.tagFilter == "status:favorite") { model.tagFilter = model.tagFilter == "status:favorite" ? nil : "status:favorite" }
            }
        }
    }
}

struct LookCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular
    let recipe: Recipe
    @State private var hovering = false

    var body: some View {
        let photos = model.photos(recipe)
        let three = (0..<3).map { $0 < photos.count ? photos[$0] : nil }
        Group {
            if regular {
                HStack(alignment: .top, spacing: 12) {
                    info.frame(width: 220, alignment: .leading).frame(maxHeight: .infinity, alignment: .top)
                    ForEach(0..<3, id: \.self) { i in tile(three[i], i, photos, ratio: 3 / 2) }
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(recipe.name).font(.system(size: 19, weight: .bold)).tracking(-0.3)
                        Spacer()
                        favorite
                        more
                    }
                    description
                    HStack(spacing: 5) { ForEach(0..<3, id: \.self) { i in tile(three[i], i, photos, ratio: 1) } }
                    tags
                    Text(model.whereabouts(recipe)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: regular ? 16 : 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: regular ? 16 : 20, style: .continuous).stroke(Theme.line, lineWidth: regular ? 1 : 0))
        // The whole card opens the recipe page; photos (preview), the heart and ⋯ keep their own taps.
        .contentShape(RoundedRectangle(cornerRadius: regular ? 16 : 20, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { edit() }
        .pointer()
        .draggable(recipe.slug) {
            HStack(spacing: 8) {
                PhotoTile(path: photos.first, maxPixel: 160).frame(width: 54, height: 36).clipShape(RoundedRectangle(cornerRadius: 5))
                Text(recipe.name).font(.system(size: 13, weight: .bold))
            }
            .padding(8).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        }
        .contextMenu { menuItems }
    }

    private var info: some View {
        // Fills the card's height: name and description at the top, tags and whereabouts level with the photos' bottom.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(recipe.name).font(.system(size: 19, weight: .bold)).tracking(-0.3).lineLimit(2)
                    .help("Edit name, description and tags")
                Spacer(minLength: 4)
                // Mac: shown on hover (a favorite keeps its filled heart); touch: always.
                let show = hovering || !regular
                favorite.opacity(show || recipe.status == "favorite" ? 1 : 0)
                more.opacity(show ? 1 : 0)
            }
            description
            Spacer(minLength: 8)
            tags
            Text(model.whereabouts(recipe)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var description: some View {
        if let d = recipe.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            Text(d).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func edit() { model.settingsFor = recipe.slug; model.sheet = .settings }

    private var favorite: some View {
        Button { model.toggleFavorite(recipe) } label: {
            Image(systemName: recipe.status == "favorite" ? "heart.fill" : "heart").font(.system(size: regular ? 16 : 18, weight: .medium))
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointer().foregroundStyle(recipe.status == "favorite" ? Theme.ink : Color.secondary)
        .accessibilityLabel(recipe.status == "favorite" ? "Remove from favorites" : "Favorite")
    }

    private var tags: some View {
        FlowLayout(spacing: 4) {
            if recipe.status == "to-try" { Chip(title: "To try", small: true).opacity(0.6) }
            ForEach(recipe.tags ?? [], id: \.self) { Chip(title: $0, small: true) }
            if recipe.settings.isMonochrome && !(recipe.tags ?? []).contains("B&W") { Chip(title: "B&W", small: true) }
        }
    }

    /// One small, light ⋯ beside the heart: everything else a card can do (the card itself opens the recipe page).
    private var more: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Theme.raised.opacity(0.7), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().pointer()
        .accessibilityLabel("More for \(recipe.name)")
    }

    @ViewBuilder private var menuItems: some View {
        Menu("Put in") {
            if model.connected {
                ForEach(model.slots.filter { !$0.dial }) { s in
                    Button(s.id + (s.unused && !s.changed ? " (empty)" : " · " + (s.name.isEmpty ? s.draft.film : s.name))) { model.put(recipe, in: s.id) }
                }
            } else {
                Text("Plug in your camera first")
            }
        }
        if recipe.status == "to-try" {
            Button("Tried It") { model.setStatus(recipe, "tried") }
        } else if recipe.status == "tried" || recipe.status == "rejected" {
            Button("Back to To Try") { model.setStatus(recipe, "to-try") }
        }
        Button(recipe.status == "favorite" ? "Remove from Favorites" : "Favorite") { model.toggleFavorite(recipe) }
        if recipe.status != "rejected" { Button("Not for Me") { model.setStatus(recipe, "rejected") } }
        Divider()
        Button("Edit…") { edit() }
        Button("Copy as Text") { copyToPasteboard("\(recipe.name)\n\(recipe.settings.text)"); model.say("Copied as text") }
    }

    private func tile(_ path: String?, _ i: Int, _ all: [String], ratio: CGFloat) -> some View {
        PhotoCell(path: path, ratio: ratio, maxPixel: 600)
            .onTapGesture { if path != nil { model.show(all, at: i, title: recipe.name) } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(path == nil ? "No photo yet" : "Photo \(i + 1) of \(recipe.name)")
    }
}

/// The camera's slots beside the looks (Mac, wide iPad): drop a look on a slot to stage it, then Review & write.
struct SlotColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InkHeadline(text: model.connected ? (model.info?.model.lowercased() ?? "camera") + "." : "camera.", size: 30)
            if model.connected {
                Text("Drop a recipe on a slot, click one for its history and settings. On the camera: dial on C, then Q.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.slots.filter { !$0.dial }) { SlotDropRow(slot: $0) }
                        if model.slots.contains(where: \.dial) {
                            HStack { SectionTitle(text: "Film simulation dial · read only"); Spacer() }.padding(.top, 6)
                            ForEach(model.slots.filter(\.dial)) { SlotDropRow(slot: $0) }
                        }
                    }
                }
                if model.askBeforeWriting && !model.changes.isEmpty {
                    Pill(title: "Review \(model.changes.count) change\(model.changes.count > 1 ? "s" : "")", wide: true) { model.sheet = .review }
                }
            } else {
                Text("Plug in your Fujifilm to drop recipes on its slots.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Button("How to connect") { model.sheet = .connect }.buttonStyle(.plain).pointer().font(.system(size: 13, weight: .semibold)).padding(.top, 4)
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card)
        .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
    }
}

struct SlotDropRow: View {
    @Environment(AppModel.self) private var model
    let slot: AppModel.Slot
    @State private var targeted = false

    var body: some View {
        let r = model.match(slot.draft)
        let empty = slot.unused && !slot.changed
        HStack(spacing: 10) {
            Text(slot.id).font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 28, alignment: .leading)
            if let p = r.flatMap({ model.photos($0).first }) {
                PhotoTile(path: p, maxPixel: 120).frame(width: 44, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(empty ? (targeted ? "Drop here" : "Empty") : (slot.name.isEmpty ? (r?.name ?? slot.draft.film) : (r?.name ?? slot.name)))
                .font(.system(size: 13.5, weight: empty ? .regular : .semibold))
                .foregroundStyle(empty ? .secondary : .primary).lineLimit(1)
            Spacer(minLength: 0)
            if slot.changed { Text("● new").font(.system(size: 11, weight: .semibold)) }
        }
        .padding(.horizontal, 8).frame(minHeight: 44)
        .background(targeted ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(slot.changed || targeted ? Theme.ink : (empty ? Color.primary.opacity(0.22) : Theme.line),
                        style: StrokeStyle(lineWidth: slot.changed || targeted ? 2 : 1, dash: empty && !targeted ? [4, 3] : []))
        }
        .opacity(slot.dial ? 0.7 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.openSlot(slot.id) }
        .pointer()
        .dropDestination(for: String.self) { items, _ in
            guard !slot.dial, let slug = items.first, let r = model.recipe(slug) else { return false }
            model.put(r, in: slot.id)
            return true
        } isTargeted: { targeted = $0 && !slot.dial }
    }
}
