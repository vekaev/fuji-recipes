import FujiKit
import ImageIO
import SwiftUI

/// The recipe library (~/Documents/FujiRecipes, shared with the CLI, the MCP server and the /recipe skill):
/// filter tabs + List | Grid on the left, the selected recipe's photo with its card on the right.
struct RecipesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("recipes.grid") private var grid = false

    var body: some View {
        HStack(spacing: 0) {
            if model.showSidebar {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        if grid {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                                ForEach(model.filteredRecipes, id: \.slug) { tile($0) }
                            }
                        } else {
                            LazyVStack(spacing: 0) { ForEach(model.filteredRecipes, id: \.slug) { row($0) } }.padding(6)
                        }
                    }
                    .overlay {
                        if model.filteredRecipes.isEmpty {
                            Text(model.recipes.isEmpty ? "No recipes yet.\nAsk Claude “find the recipes in my photos”,\nor send /recipe a reel." : "Nothing here yet.")
                                .multilineTextAlignment(.center).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 320).background(Theme.panel)
                .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }
            }
            pane
        }
        .focusable().focusEffectDisabled()
        .onKeyPress(.upArrow) { move(grid ? -3 : -1); return .handled }
        .onKeyPress(.downArrow) { move(grid ? 3 : 1); return .handled }
        .onKeyPress("f") { if let r = model.recipe { model.toggleFavorite(r) }; return .handled }
    }

    private func move(_ d: Int) {
        let list = model.filteredRecipes
        guard let i = list.firstIndex(where: { $0.slug == model.selectedRecipe }) else { model.selectedRecipe = list.first?.slug; return }
        model.selectedRecipe = list[max(0, min(list.count - 1, i + d))].slug
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 14) {
            ForEach(AppModel.RecipeFilter.allCases, id: \.self) { f in
                let on = model.recipeFilter == f
                Button { model.recipeFilter = f } label: {
                    HStack(spacing: 3) {
                        if f == .favorites { Image(systemName: on ? "heart.fill" : "heart") } else {
                            Text(["all": "All", "mine": "Shot with", "toTry": "To try"][f.rawValue] ?? "")
                        }
                        Text("\(model.count(f))").foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .font(.system(size: 12.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? .primary : .secondary)
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Rectangle().fill(on ? Color.primary : .clear).frame(height: 1.5) }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 0) {
                ForEach([false, true], id: \.self) { g in
                    Button { grid = g } label: {
                        Image(systemName: g ? "square.grid.2x2" : "list.bullet").font(.system(size: 11, weight: .medium))
                            .frame(width: 20, height: 18).foregroundStyle(grid == g ? .primary : .tertiary)
                            .background(grid == g ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 16).padding(.trailing, 6).frame(height: 32)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private func row(_ r: Recipe) -> some View {
        let held = model.slotsHolding(r)
        return HStack(spacing: 10) {
            thumb(r).frame(width: 58, height: 40).clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(r.name).lineLimit(1)
                    if r.status == "favorite" { Image(systemName: "heart.fill").font(.system(size: 9)) }
                }
                .font(.system(size: 12.5))
                Text(r.settings.film + " · " + (held.isEmpty ? (r.status == "mine" ? "\(r.shots ?? 0) shots" : r.status.replacingOccurrences(of: "-", with: " ")) : "in " + held.joined(separator: ", ")))
                    .font(.system(size: 11)).foregroundStyle(held.isEmpty ? .secondary : .primary).lineLimit(1)
                Text(r.settings.summary.replacingOccurrences(of: r.settings.film + " · ", with: ""))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(model.selectedRecipe == r.slug ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedRecipe = r.slug }
    }

    private func tile(_ r: Recipe) -> some View {
        thumb(r).aspectRatio(1, contentMode: .fill).clipped()
            .overlay(alignment: .topTrailing) {
                if let s = model.slotsHolding(r).first { pill(s, light: true) }
                else if r.status == "mine" { pill("\(r.shots ?? 0)", light: false) }
            }
            .overlay { if model.selectedRecipe == r.slug { Rectangle().stroke(Color.primary, lineWidth: 3) } }
            .contentShape(Rectangle())
            .onTapGesture { model.selectedRecipe = r.slug }
            .help(r.name)
    }

    private func pill(_ t: String, light: Bool) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(light ? .black : .white)
            .background(light ? Color.white.opacity(0.92) : Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4)).padding(5)
    }

    @ViewBuilder private func thumb(_ r: Recipe) -> some View {
        if let p = r.samples?.first { SampleImage(path: p) } else {
            Theme.raised.overlay(Text(String(r.settings.film.prefix(2))).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary))
        }
    }

    @ViewBuilder private var pane: some View {
        if let r = model.recipe {
            let held = model.slotsHolding(r)
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(r.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text(source(r)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 6)
                    Spacer()
                    iconButton(r.status == "favorite" ? "heart.fill" : "heart", "Favorite (F)") { model.toggleFavorite(r) }
                    iconButton("camera", "Put in a slot") { model.putIn(r) }
                    iconButton("doc.on.doc", "Copy as text") { model.copyText(r.settings, name: r.name) }
                }
                .padding(.leading, 16).padding(.trailing, 8).frame(height: 38)
                .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                ZStack {
                    Theme.stage
                    if let p = r.samples?.first { SampleImage(path: p, fit: true, maxPixel: 1600).padding(32) }
                    else { Text("No photo yet: shoot with it, then ask Claude to find your recipes in your photos.").font(.system(size: 12)).foregroundStyle(.secondary) }
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        if !model.connected { Text("Plug in the camera to put it in a slot") }
                        else if !held.isEmpty { Text("In \(held.joined(separator: ", "))") }
                        else {
                            Text("Not on the camera"); Text("·").opacity(0.4)
                            Button("Put in a slot") { model.putIn(r) }.buttonStyle(.plain).fontWeight(.semibold)
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.onPhoto, in: RoundedRectangle(cornerRadius: 6)).padding(18)
                }
                .overlay(alignment: .bottomLeading) {
                    InfoCard(settings: r.settings, footer: footer(r)).padding(18)
                }
            }
        } else {
            Theme.stage
        }
    }

    private func source(_ r: Recipe) -> String {
        if r.status == "mine" { return "\(r.shots ?? 0) of your photos" + ((r.cameras ?? []).isEmpty ? "" : " · " + (r.cameras ?? []).joined(separator: ", ")) }
        return [r.source?.creator, r.source?.kind].compactMap { $0 }.first ?? ""
    }

    private func footer(_ r: Recipe) -> [String] {
        var f: [String] = []
        if let iso = r.shooting?["iso"] { f.append("ISO \(iso)") }
        if let ev = r.shooting?["exposure_compensation"] { f.append("Exposure \(ev)") }
        if let first = r.firstShot, let last = r.lastShot { f.append(first == last ? "Shot \(first)" : "Shot \(first) – \(last)") }
        return f
    }

    private func iconButton(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 13)).frame(width: 28, height: 26).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }
}

/// A photo from disk, downsampled off the main thread and cached.
struct SampleImage: View {
    let path: String
    var fit = false
    var maxPixel = 240
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
            } else {
                Theme.raised
            }
        }
        .task(id: "\(path)#\(maxPixel)") { image = await ThumbCache.shared.image(path, maxPixel: maxPixel) }
    }
}

actor ThumbCache {
    static let shared = ThumbCache()
    private var cache: [String: NSImage] = [:]

    func image(_ path: String, maxPixel: Int) async -> NSImage? {
        let key = "\(path)#\(maxPixel)"
        if let hit = cache[key] { return hit }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                   kCGImageSourceCreateThumbnailWithTransform: true,
                                                                   kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary)
        else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[key] = img
        return img
    }
}
