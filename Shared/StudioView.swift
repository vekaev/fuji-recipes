import FujiKit
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
                    Text("Your RAW photo, developed by your camera with each recipe. Compare, then keep the ones you like.")
                        .font(regular ? .title3 : .body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
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
