import FujiKit
import SwiftUI

@main
struct FujiRecipesApp: App {
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system
    @State private var model = AppModel()

    var body: some Scene {
        Window("Fuji Recipes", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.ink)
                .task { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Looks") { model.tab = .looks }.keyboardShortcut("1")
                Button("Camera") { model.tab = .camera }.keyboardShortcut("2")
                Button("Inbox") { model.tab = .inbox }.keyboardShortcut("3")
            }
            CommandMenu("Camera") {
                Button("Check Connection") { Task { await model.check() } }.keyboardShortcut("r")
                Button("Settings of This Slot") { model.tab = .camera; model.editing.toggle() }.keyboardShortcut("e", modifiers: [])
                    .disabled(!model.connected || model.slot?.dial != false)
                Button("Review Changes…") { model.sheet = .review }.keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.changes.isEmpty)
                Button("Undo All Changes") { model.revertAll() }.disabled(model.changes.isEmpty)
                Divider()
                Button("Backups…") { model.sheet = .backups }
                Button("Try with a Simulated X-E5") { model.trySimulated() }.disabled(model.connected)
            }
            CommandGroup(replacing: .help) {
                Button("How to Use C1–C7 and FS1–FS3") { model.sheet = .help }
                Button("Connection Check") { model.sheet = .trouble }
                Link("Fuji Recipes on GitHub", destination: URL(string: "https://github.com/vekaev/fuji-recipes")!)
            }
        }

        Settings {
            Form {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Recipe library", value: model.library.root.path)
                Text(model.library.root.path.contains("Mobile Documents") ? "In iCloud Drive: your iPhone and iPad see the same library."
                     : "To see it on your iPhone and iPad: turn on iCloud Drive (System Settings ▸ Apple Account ▸ iCloud), then move this folder to iCloud Drive and name it Fuji Recipes. The app, Claude and /recipe follow it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .frame(width: 480)
        }
    }
}
