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

    var body: some View {
        let recipes = model.studioRecipes
        let _ = model.studioVersion   // re-read the cache when a render lands
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
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "RAF") ?? .rawImage, .rawImage]) { result in
            guard let url = try? result.get() else { return }
            useRaw(url)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first(where: { $0.pathExtension.uppercased() == "RAF" }) else { return false }
            useRaw(u); return true
        } isTargeted: { dropTargeted = $0 }
    }

    /// iPhone / iPad: a picked file is only readable for a while, so it's copied into the library's Studio folder.
    private func useRaw(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        #if os(iOS)
        let dir = model.library.root.appendingPathComponent("studio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: url, to: copy) }
        model.studioRaw = copy
        #else
        model.studioRaw = url
        #endif
    }

    private var rawRow: some View {
        HStack(spacing: 14) {
            if let raw = model.studioRaw {
                PhotoCell(path: raw.path, ratio: 3 / 2, maxPixel: 400, radius: 8)
                    .frame(width: regular ? 120 : 90)
                VStack(alignment: .leading, spacing: 3) {
                    Text(raw.lastPathComponent).font(.system(size: 15, weight: .semibold)).accessibilityIdentifier("studio.rawName")
                    Text("As shot. Drop or choose another RAW from this camera.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            } else {
                Text(regular ? "Drop a .RAF from your X-E5 here, or choose one." : "Choose a .RAF from your X-E5.")
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            PillButton(title: model.studioRaw == nil ? "Choose a RAW…" : "Change…") { picking = true }
                .accessibilityIdentifier("studio.choose")
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
                Pill(title: "Render \(missing) recipe\(missing == 1 ? "" : "s")") { model.renderStudio() }
                    .accessibilityIdentifier("studio.render")
                Text(model.connected ? "About 2 s each on the camera." : "Plug in the camera to render.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                Text("All \(recipes.count) rendered.").font(.system(size: 13)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("studio.allRendered")
            }
        }
    }

    private func grid(_ recipes: [Recipe]) -> some View {
        let rendered = recipes.compactMap { r in model.studioRender(r).map { (r, $0) } }
        let paths = [model.studioRaw!.path] + rendered.map(\.1.path)
        let titles = ["As shot"] + rendered.map(\.0.name)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: regular ? 4 : 2), spacing: 14) {
            tile(title: "As shot", path: model.studioRaw!.path, recipe: nil) { model.show(paths, at: 0, title: "As shot", titles: titles) }
            ForEach(recipes, id: \.slug) { r in
                let path = model.studioRender(r)?.path
                tile(title: r.name, path: path, recipe: r) {
                    if let path, let i = paths.firstIndex(of: path) { model.show(paths, at: i, title: r.name, titles: titles) }
                }
            }
        }
    }

    private func tile(title: String, path: String?, recipe: Recipe?, open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let path {
                    PhotoCell(path: path, ratio: 3 / 2, maxPixel: 700, radius: 8).onTapGesture(perform: open)
                } else {
                    Shimmer().aspectRatio(3 / 2, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .opacity(model.studioRendering ? 1 : 0.35)
                }
            }
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let r = recipe {
                    Button { model.toggleFavorite(r) } label: {
                        Image(systemName: r.status == "favorite" ? "heart.fill" : "heart").font(.system(size: 13))
                    }
                    .buttonStyle(.plain).pointer().foregroundStyle(r.status == "favorite" ? Theme.ink : Color.secondary)
                    .accessibilityLabel(r.status == "favorite" ? "Remove \(r.name) from favorites" : "Favorite \(r.name)")
                }
            }
            if let r = recipe, let notes = model.studioNotes[r.slug] {
                Text(notes.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.tile.\(title)")
    }
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
            guard let url = try? result.get() else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            #if os(iOS)
            let dir = model.library.root.appendingPathComponent("studio")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let copy = dir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: url, to: copy) }
            model.studioRaw = copy
            #else
            model.studioRaw = url
            #endif
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
            if u.pathExtension.uppercased() == "RAF" { model.studioRaw = u } else { model.useLookReference(u) }
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
                    Text("The look to match. Drop or choose another photo.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            } else {
                Text(regular ? "Drop a photo whose look you want, or choose one." : "Choose a photo whose look you want.")
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
