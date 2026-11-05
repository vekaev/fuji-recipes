import FujiKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The Studio: one of your RAW photos, developed by the camera itself with each recipe (as X RAW Studio does), side by
/// side. The first tile is the photo as shot. Renders are cached in the library, so a sheet opens instantly and works
/// without the camera; only new recipes need it. Tap a tile to see it big and step through the recipes.
struct StudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular
    @State private var picking = false
    @State private var dropTargeted = false
    @State private var gridWidth: CGFloat = 900
    @FocusState private var gridFocused: Bool

    var body: some View {
        let recipes = model.studioRecipes
        let _ = model.studioVersion   // re-read the cache when a render lands
        let items = studioItems(recipes)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    InkHeadline(text: "studio.", size: regular ? 40 : 34)
                    Text(model.studioMode == .recipes
                         ? "Your RAW photo, developed by your camera with each recipe. Compare, then keep the ones you like."
                         : "Any photo you love, a Leica shot, a film scan, a post: find the recipe that gets your camera closest.")
                        .font(regular ? .title3 : .body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Chip(title: "Try recipes", on: model.studioMode == .recipes) { model.studioMode = .recipes }
                        .accessibilityIdentifier("studio.mode.recipes")
                    Chip(title: "Match a look", on: model.studioMode == .look) { model.studioMode = .look }
                        .accessibilityIdentifier("studio.mode.look")
                }
                if model.studioMode == .look {
                    MatchLookView()
                } else {
                rawRow
                if model.studioRaw != nil {
                    filters
                    controls(recipes)
                    if let e = model.studioError {
                        Text(e).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("studio.error")
                    }
                    grid(recipes)
                }
                }
            }
            .padding(.horizontal, regular ? 34 : 18).padding(.vertical, regular ? 26 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)   // the whole window: big cards (owner, 2026-11-05)
        }
        .background(Theme.paper)
        // Keys (Mac, iPad keyboard): arrows move the selection (↑↓ by a row), Space / ↵ opens it big, P picks it for
        // this photo, F favorites the recipe. The big view's own keys take over while it's open.
        .modifier(StudioKeys(enabled: regular && model.studioMode == .recipes && model.studioRaw != nil, focused: $gridFocused,
                             move: { d in move(d, items.count, proxy: proxy, items: items) },
                             open: { open(items, at: model.studioSelected) },
                             pick: { if let r = items[safe: model.studioSelected]?.recipe { model.togglePick(r.slug) } },
                             favorite: { if let r = items[safe: model.studioSelected]?.recipe { model.toggleFavorite(r) } }))
        .onChange(of: model.preview?.index) { _, _ in   // stepping in the big view moves the selection with it
            guard let p = model.preview, let rs = p.recipes else { return }
            let id = rs[p.index] ?? "as-shot"
            if let i = items.firstIndex(where: { $0.id == id }) { model.studioSelected = i; proxy.scrollTo(id) }
        }
        .onChange(of: model.preview == nil) { _, closed in if closed { gridFocused = true } }
        }
        // Renders by itself when a RAW is here and the camera is connected (and again when either changes).
        .task(id: "\(model.studioRaw?.path ?? "")|\(model.studioFilter ?? "")|\(model.connected)|\(model.studioMode)|\(model.recipes.count)") {
            model.autoRenderStudio()
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "RAF") ?? .rawImage, .rawImage]) { result in
            guard let url = try? result.get() else { return }
            model.useStudioRaw(url)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first(where: { $0.pathExtension.uppercased() == "RAF" }) else { return false }
            model.useStudioRaw(u); return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var rawRow: some View {
        HStack(spacing: 14) {
            if let raw = model.studioRaw {
                PhotoCell(path: raw.path, ratio: 3 / 2, maxPixel: 400, radius: 8)
                    .frame(width: regular ? 120 : 90)
                VStack(alignment: .leading, spacing: 3) {
                    Text(raw.lastPathComponent).font(.system(size: 15, weight: .semibold)).accessibilityIdentifier("studio.rawName")
                    Text(pasteHint("As shot. Drop, paste or choose another RAW from this camera.")).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            } else {
                Text(regular ? "Drop or paste a .RAF from your X-E5, or choose one." : "Choose or paste a .RAF from your X-E5.")
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                PillButton(title: model.studioRaw == nil ? "Choose a RAW…" : "Change…") { picking = true }
                    .accessibilityIdentifier("studio.choose")
                StudioPasteButton()
            }
        }
        .padding(14)
        .background(dropTargeted ? Theme.raised : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(dropTargeted ? 0.8 : 0.12), style: StrokeStyle(lineWidth: 1, dash: model.studioRaw == nil ? [5, 4] : [])))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Favorites & to try", nil)
                chip("All \(model.recipes.count)", "all")
                chip("♡", "status:favorite")
                chip("To try", "status:to-try")
                if !model.studioPicks.isEmpty { chip("Picked \(model.studioPicks.count)", "picked") }
                if !model.allTags.isEmpty { Theme.line.frame(width: 1, height: 16).padding(.horizontal, 4) }
                ForEach(model.allTags, id: \.self) { chip($0, $0) }
            }
        }
    }

    private func chip(_ title: String, _ key: String?) -> some View {
        Chip(title: title, on: model.studioFilter == key) { model.studioFilter = key }
    }

    private func controls(_ recipes: [Recipe]) -> some View {
        let missing = recipes.filter { model.studioRender($0) == nil }.count
        return HStack(spacing: 12) {
            if model.studioRendering {
                ProgressView(value: Double(model.studioProgress.done), total: Double(max(1, model.studioProgress.total)))
                    .frame(maxWidth: 220).tint(Theme.ink)
                Text("\(model.studioProgress.done) of \(model.studioProgress.total)").font(.system(size: 12.5)).foregroundStyle(.secondary).monospacedDigit()
                PillButton(title: "Stop") { model.stopStudio() }
            } else if missing > 0 {
                Pill(title: "Render \(missing) recipe\(missing == 1 ? "" : "s")") { model.studioStopped = false; model.renderStudio() }
                    .accessibilityIdentifier("studio.render")
                Text(model.connected ? (model.studioStopped ? "Stopped. About 2 s each on the camera." : "About 2 s each on the camera.")
                                     : "Plug in the camera: it develops the RAW itself, then this starts on its own.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                Text("All \(recipes.count) rendered.").font(.system(size: 13)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("studio.allRendered")
            }
        }
    }

    /// The grid's cells: the photo as shot, then each recipe (rendered or not yet).
    struct Item: Identifiable { let id: String; let title: String; let path: String?; let recipe: Recipe? }

    private func studioItems(_ recipes: [Recipe]) -> [Item] {
        guard let raw = model.studioRaw else { return [] }
        return [Item(id: "as-shot", title: "As shot", path: raw.path, recipe: nil)]
            + recipes.map { Item(id: $0.slug, title: $0.name, path: model.studioRender($0)?.path, recipe: $0) }
    }

    /// Columns from the width: cards at least 340 pt wide on the Mac / iPad (3 in a 1200 pt window, 5 on a wide
    /// screen), one per row on an iPhone held upright.
    private func columns(_ width: CGFloat) -> Int {
        let minimum: CGFloat = regular ? 340 : 280, gap: CGFloat = regular ? 18 : 12
        return max(1, Int((width + gap) / (minimum + gap)))
    }

    /// A vertical shot gets vertical cards (the camera's previews are 4:3 with bars; filling 2:3 or 3:2 hides them).
    private var ratio: CGFloat {
        guard let raw = model.studioRaw else { return 3 / 2 }
        return (5...8).contains(RenderCache.orientation(raw)) ? 2 / 3 : 3 / 2
    }

    private func grid(_ recipes: [Recipe]) -> some View {
        let items = studioItems(recipes)
        let n = columns(gridWidth)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: regular ? 18 : 12), count: n), spacing: regular ? 22 : 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                tile(item, selected: regular && i == model.studioSelected) {
                    model.studioSelected = i; gridFocused = true
                    open(items, at: i)
                }
                .id(item.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    private func open(_ items: [Item], at i: Int) {
        guard let item = items[safe: i], item.path != nil else { return }
        let shown = items.filter { $0.path != nil }
        guard let at = shown.firstIndex(where: { $0.id == item.id }) else { return }
        model.show(shown.map { $0.path! }, at: at, title: item.title, titles: shown.map(\.title),
                   recipes: shown.map { $0.recipe?.slug })
    }

    private func move(_ d: StudioKeys.Move, _ count: Int, proxy: ScrollViewProxy, items: [Item]) {
        guard count > 0 else { return }
        let n = columns(gridWidth)
        let step: Int = switch d { case .left: -1; case .right: 1; case .up: -n; case .down: n }
        let next = model.studioSelected + step
        guard next >= 0, next < count else { return }
        model.studioSelected = next
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(items[next].id) }
    }

    private func tile(_ item: Item, selected: Bool, open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                if let path = item.path {
                    PhotoCell(path: path, ratio: ratio, maxPixel: 1000, radius: 10).onTapGesture(perform: open)
                } else {
                    Shimmer().aspectRatio(ratio, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(model.studioRendering ? 1 : 0.35)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.ink, lineWidth: selected ? 2.5 : 0).padding(-4))
            .overlay(alignment: .topTrailing) {
                if let r = item.recipe, model.studioPicks.contains(r.slug) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, Theme.ink)
                        .padding(8).accessibilityHidden(true)
                }
            }
            HStack(spacing: 10) {
                Text(item.title).font(.system(size: regular ? 15 : 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let r = item.recipe {
                    let picked = model.studioPicks.contains(r.slug)
                    Button { model.togglePick(r.slug) } label: {
                        Image(systemName: picked ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: 15))
                    }
                    .buttonStyle(.plain).pointer().foregroundStyle(picked ? Theme.ink : Color.secondary)
                    .help("Pick for this photo (P)")
                    .accessibilityLabel(picked ? "Unpick \(r.name) for this photo" : "Pick \(r.name) for this photo")
                    .accessibilityIdentifier("studio.pick.\(r.name)")
                    Button { model.toggleFavorite(r) } label: {
                        Image(systemName: r.status == "favorite" ? "heart.fill" : "heart").font(.system(size: 14))
                    }
                    .buttonStyle(.plain).pointer().foregroundStyle(r.status == "favorite" ? Theme.ink : Color.secondary)
                    .help("Favorite recipe (F)")
                    .accessibilityLabel(r.status == "favorite" ? "Remove \(r.name) from favorites" : "Favorite \(r.name)")
                }
            }
            if let r = item.recipe, let notes = model.studioNotes[r.slug] {
                Text(notes.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.tile.\(item.title)")
    }
}

/// The Studio grid's keys, only while it can take them (Mac, iPad with a keyboard).
struct StudioKeys: ViewModifier {
    enum Move { case left, right, up, down }
    let enabled: Bool
    var focused: FocusState<Bool>.Binding
    let move: (Move) -> Void
    let open: () -> Void
    let pick: () -> Void
    let favorite: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if enabled {
            content
                .focusable().focusEffectDisabled().focused(focused)
                .onAppear { focused.wrappedValue = true }
                .onKeyPress(.leftArrow) { move(.left); return .handled }
                .onKeyPress(.rightArrow) { move(.right); return .handled }
                .onKeyPress(.upArrow) { move(.up); return .handled }
                .onKeyPress(.downArrow) { move(.down); return .handled }
                .onKeyPress(.space) { open(); return .handled }
                .onKeyPress(.return) { open(); return .handled }
                // P / F, also where a Cyrillic layout puts them (з / а).
                .onKeyPress(characters: CharacterSet(charactersIn: "pPзЗ"), phases: .down) { _ in pick(); return .handled }
                .onKeyPress(characters: CharacterSet(charactersIn: "fFаА"), phases: .down) { _ in favorite(); return .handled }
        } else {
            content
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Match a look: a reference photo, what it looks like in the library, a first guess, then the camera's search on your
/// RAW, and the three closest looks next to the reference to compare and keep.
struct MatchLookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.regularLayout) private var regular
    @State private var pickingFile = false
    @State private var pickingRaw = false
    @State private var photoItem: PhotosPickerItem?
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            referenceRow
            if model.lookAnalysing {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading the photo's look…").font(.system(size: 13)).foregroundStyle(.secondary) }
            }
            if let e = model.lookError {
                Text(e).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("look.error")
            }
            if let guess = model.lookGuess, model.lookReference != nil {
                if !guess.neighbours.isEmpty { looksLike(guess.neighbours) }
                guessCard(guess.settings, notes: guess.notes)
                cameraRow
                if !model.lookResults.isEmpty || model.lookSearching { results }
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.image]) { result in
            if let url = try? result.get() { model.useLookReference(url) }
        }
        .fileImporter(isPresented: $pickingRaw, allowedContentTypes: [UTType(filenameExtension: "RAF") ?? .rawImage, .rawImage]) { result in
            if let url = try? result.get() { model.useStudioRaw(url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.useLookReference(data: data, name: "Photo \(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")).jpg")
                }
                photoItem = nil
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            if u.pathExtension.uppercased() == "RAF" { model.useStudioRaw(u) } else { model.useLookReference(u) }
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var referenceRow: some View {
        HStack(spacing: 14) {
            if let ref = model.lookReference {
                PhotoCell(path: ref.path, ratio: 3 / 2, maxPixel: 500, radius: 8)
                    .frame(width: regular ? 150 : 100)
                    .onTapGesture { model.show([ref.path], at: 0, title: "Your photo") }
                VStack(alignment: .leading, spacing: 3) {
                    Text(ref.lastPathComponent).font(.system(size: 15, weight: .semibold)).lineLimit(1).accessibilityIdentifier("look.referenceName")
                    Text(pasteHint("The look to match. Drop, paste or choose another photo.")).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            } else {
                Text(regular ? "Drop or paste a photo whose look you want, or choose one." : "Choose or paste a photo whose look you want.")
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                PillButton(title: model.lookReference == nil ? "Choose a photo…" : "Change…") { pickingFile = true }
                    .accessibilityIdentifier("look.choose")
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("From Photos").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).pointer()
                StudioPasteButton()
            }
        }
        .padding(14)
        .background(dropTargeted ? Theme.raised : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(dropTargeted ? 0.8 : 0.12), style: StrokeStyle(lineWidth: 1, dash: model.lookReference == nil ? [5, 4] : [])))
    }

    private func looksLike(_ nn: [LookMatch.Neighbour]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Looks like, in your library")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(nn.prefix(3).enumerated()), id: \.offset) { i, n in
                        Button { model.openRecipe(n.recipe.slug) } label: {
                            HStack(spacing: 8) {
                                PhotoCell(path: n.file, ratio: 1, maxPixel: 160, radius: 6).frame(width: 40)
                                Text(n.recipe.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                            }
                            .padding(.trailing, 10).padding(4)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain).pointer()
                        .accessibilityIdentifier("look.like.\(i)")
                    }
                }
            }
        }
    }

    private func guessCard(_ s: RecipeSettings, notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "First guess, from the photo alone")
                Spacer()
                saveButton(s, match: nil, jpeg: nil, id: "look.saveGuess")
            }
            Text(s.summary).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("look.guess")
            ForEach(notes, id: \.self) { Text($0).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cameraRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let raw = model.studioRaw {
                    PhotoCell(path: raw.path, ratio: 3 / 2, maxPixel: 300, radius: 6).frame(width: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check on your camera").font(.system(size: 13.5, weight: .semibold))
                        Text("\(raw.lastPathComponent): up to \(model.lookBudget) tries, about 2 s each. A RAW with light like the photo's works best.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("To check on the camera, choose one of your RAW photos (.RAF) with similar light.")
                        .font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PillButton(title: model.studioRaw == nil ? "Choose a RAW…" : "Change…") { pickingRaw = true }
            }
            HStack(spacing: 12) {
                if model.lookSearching {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: Double(model.lookProgress.done), total: Double(max(1, model.lookProgress.budget)))
                            .frame(maxWidth: 260).tint(Theme.ink)
                        Text("\(model.lookProgress.stage) · best so far \(model.lookProgress.best)%").font(.system(size: 12)).foregroundStyle(.secondary)
                            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    PillButton(title: "Stop") { model.stopStudio() }
                } else if model.studioRaw != nil {
                    Pill(title: model.lookResults.isEmpty ? "Find the closest recipe" : "Search again") { model.searchLook() }
                        .accessibilityIdentifier("look.refine")
                    Text(model.connected ? "Nothing on the camera changes." : "Plug in the camera to search.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var results: some View {
        let ref = model.lookReference!.path
        let paths = [ref] + model.lookResults.map(\.jpeg.path)
        let titles = ["Your photo"] + model.lookResults.map { "\($0.match)% · \($0.settings.film)" }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: model.lookSearching ? "Searching…" : "Closest on your camera")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: regular ? 4 : 2), spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    PhotoCell(path: ref, ratio: 3 / 2, maxPixel: 700, radius: 8)
                        .onTapGesture { model.show(paths, at: 0, title: "Your photo", titles: titles) }
                    Text("Your photo").font(.system(size: 13.5, weight: .semibold))
                }
                ForEach(Array(model.lookResults.enumerated()), id: \.element.id) { i, r in
                    VStack(alignment: .leading, spacing: 6) {
                        PhotoCell(path: r.jpeg.path, ratio: 3 / 2, maxPixel: 700, radius: 8)
                            .onTapGesture { model.show(paths, at: i + 1, title: titles[i + 1], titles: titles) }
                        HStack {
                            Text("\(r.match)% match").font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                            Spacer(minLength: 4)
                            saveButton(r.settings, match: r.match, jpeg: r.jpeg, id: "look.save.\(i)")
                        }
                        Text(r.settings.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("look.result.\(i)")
                }
                if model.lookSearching && model.lookResults.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        Shimmer().aspectRatio(3 / 2, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func saveButton(_ s: RecipeSettings, match: Int?, jpeg: URL?, id: String) -> some View {
        if let slug = model.lookSaved[RenderCache.recipeKey(s)] {
            Button { model.openRecipe(slug) } label: { Text("Saved ›").font(.system(size: 12.5)).foregroundStyle(.secondary) }
                .buttonStyle(.plain).pointer().accessibilityIdentifier(id + ".done")
        } else {
            PillButton(title: "Save", primary: jpeg != nil) { model.saveLook(s, match: match, jpeg: jpeg) }
                .accessibilityIdentifier(id)
        }
    }
}

/// The Mac says "⌘V" in the hint; iPhone / iPad have the Paste button instead.
private func pasteHint(_ text: String) -> String {
    #if os(macOS)
    return text.replacingOccurrences(of: "paste", with: "paste (⌘V)")
    #else
    return text
    #endif
}

/// iPhone / iPad: the system Paste button reads what was copied (a RAF or a photo in Files, an image from Safari or
/// Photos) without iOS asking for permission each time. On the Mac ⌘V does this (`StudioPaste` in App/MacSupport.swift).
struct StudioPasteButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        #if os(iOS)
        PasteButton(supportedContentTypes: [UTType(filenameExtension: "RAF") ?? .rawImage, .rawImage, .image]) { providers in
            Task { await paste(providers) }
        }
        .labelStyle(.titleOnly)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(Theme.ink)
        .accessibilityIdentifier("studio.paste")
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    /// A file (RAF or photo) comes as a temporary copy that disappears when the callback returns, so it's copied first;
    /// an image without a file (copied from Safari or Photos) comes as data.
    private func paste(_ providers: [NSItemProvider]) async {
        let raf = UTType(filenameExtension: "RAF")
        var files: [URL] = []
        var image: (data: Data, name: String)?
        for p in providers {
            let type = p.registeredContentTypes.first { t in (raf.map { t.conforms(to: $0) } ?? false) || t.conforms(to: .rawImage) }
                ?? p.registeredContentTypes.first { $0.conforms(to: .image) }
            guard let type else { continue }
            if let url = await Self.fileCopy(p, type) { files.append(url); continue }
            if image == nil, let data = await withCheckedContinuation({ (done: CheckedContinuation<Data?, Never>) in
                _ = p.loadDataRepresentation(for: type) { d, _ in done.resume(returning: d) }
            }) {
                image = (data, AppModel.pastedName(ext: type.preferredFilenameExtension ?? "jpg"))
            }
        }
        await MainActor.run {
            if !model.pasteIntoStudio(files: files, image: image) { model.say("Nothing to paste: copy a .RAF or a photo first.") }
        }
    }

    private static func fileCopy(_ p: NSItemProvider, _ type: UTType) async -> URL? {
        await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
            _ = p.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { done.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "dat") : url.pathExtension
                // Files gives the original name; an image copied from Safari or Photos has none (its temp file is a hash).
                let name = p.suggestedName.map { n in (n as NSString).pathExtension.isEmpty ? n + "." + ext : n }
                    ?? AppModel.pastedName(ext: ext)
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paste-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let copy = dir.appendingPathComponent(name)
                done.resume(returning: (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? copy : nil)
            }
        }
    }
    #endif
}
