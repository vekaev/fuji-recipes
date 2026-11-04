import FujiKit
import SwiftUI

/// iPhone and iPad. The library is a folder the owner picks once in the Files picker (iCloud Drive ▸ Fuji Recipes,
/// shared with the Mac, Claude and /recipe); its security-scoped bookmark is kept, like Photo Minimalist's folders.
@main
struct FujiRecipesApp: App {
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system
    @State private var model = AppModel(library: LibraryBookmark.restore() ?? Library())

    var body: some Scene {
        WindowGroup {
            @Bindable var model = model
            RootView()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.ink)
                .task { model.start() }
                .fileImporter(isPresented: $model.pickingLibrary, allowedContentTypes: [.folder]) { result in
                    guard let url = try? result.get(), let lib = LibraryBookmark.save(url) else { return }
                    model.use(lib)
                    model.say("Library: \(url.lastPathComponent)")
                }
        }
    }
}

enum LibraryBookmark {
    private static let key = "libraryBookmark"

    static func save(_ url: URL) -> Library? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return Library(root: url)
    }

    static func restore() -> Library? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale { _ = save(url) }
        return Library(root: url)
    }
}
