import SwiftUI

@main
struct FujiRecipesApp: App {
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system
    @State private var model = AppModel()

    var body: some Scene {
        Window("Fuji Recipes", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(appearance.colorScheme)
                .task { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Camera") { model.tab = .camera }.keyboardShortcut("1")
                Button("Recipes") { model.tab = .recipes }.keyboardShortcut("2")
                Divider()
                Button(model.showSidebar ? "Hide Sidebar" : "Show Sidebar") { model.showSidebar.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandMenu("Camera") {
                Button("Check Connection") { Task { await model.check() } }.keyboardShortcut("r")
                Button("Edit Slot") { model.editing.toggle() }.keyboardShortcut("e", modifiers: [])
                    .disabled(!model.connected || model.slot?.dial != false)
                Button("Write Slot…") { model.editing = true; model.confirmingWrite = true }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.slot?.changed != true)
                Divider()
                Button("Backups…") { model.sheet = .backups }
                Button("Try with a Simulated X-E5") { model.trySimulated() }.disabled(model.connected)
            }
            CommandGroup(replacing: .help) {
                Button("How to Use C1–C7 and FS1–FS3") { model.sheet = .help }
                Button("Connection Troubleshooting") { model.sheet = .trouble }
                Link("Fuji Recipes on GitHub", destination: URL(string: "https://github.com/vekaev/fuji-recipes")!)
            }
        }

        Settings {
            Form {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Recipe library", value: model.library.root.path)
            }
            .formStyle(.grouped)
            .frame(width: 460)
        }
    }
}
