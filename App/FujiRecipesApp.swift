import FujiKit
import SwiftUI

@main
struct FujiRecipesApp: App {
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system
    @State private var model = AppModel(library: AppModel.uiTestLibrary() ?? Library())

    init() { _ = Updater.shared }   // Sparkle: a daily check against the latest GitHub release

    var body: some Scene {
        Window("Fuji Recipes", id: "main") {
            RootView()
                .background(WindowAccessor { TrafficLights.attach($0) })
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.ink)
                .task { model.start(); StudioPaste.install(model) }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { n in
                    if let v = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL { model.cardMounted(v) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) { CheckForUpdatesButton() }
            CommandGroup(after: .sidebar) {
                Button("Recipes") { model.tab = .looks }.keyboardShortcut("1")
                Button("Studio") { model.tab = .studio }.keyboardShortcut("2")
                Button("Add Recipes") { model.tab = .inbox }.keyboardShortcut("3")
            }
            CommandMenu("Camera") {
                Button("Check Connection") { Task { await model.check() } }.keyboardShortcut("r")
                Button("How to Connect…") { model.sheet = .connect }.disabled(model.connected)
                Button("Settings of This Slot") { model.openSlot(model.selectedSlot, editing: true) }.keyboardShortcut("e", modifiers: [])
                    .disabled(!model.connected || model.slot == nil)
                Toggle("Ask Before Writing", isOn: $model.askBeforeWriting)
                Toggle("Clarity (Slower Saving)", isOn: model.clarityBinding)
                Button("Add the Camera's Recipes to the Library") { model.syncSlotsToLibrary() }.disabled(!model.connected || model.syncingSlots)
                Toggle("Add Them When the Camera Connects", isOn: $model.syncSlots)
                Button("Review Changes…") { model.sheet = .review }.keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.changes.isEmpty || !model.askBeforeWriting)
                Button("Undo All Changes") { model.revertAll() }.disabled(model.changes.isEmpty || !model.askBeforeWriting)
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
                UpdatePreferences()
                Section {
                    Toggle("Ask before writing to the camera", isOn: $model.askBeforeWriting)
                Text("Off: a recipe you put in a slot is written right away. Each write saves that slot first, reads it back, and the message offers Undo.")
                    .font(.caption).foregroundStyle(.secondary)
                ClaritySetting(model: model)
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Recipe library", value: model.library.root.path)
                Text(model.library.root.path.contains("Mobile Documents") ? "In iCloud Drive: your iPhone and iPad see the same library."
                     : "To see it on your iPhone and iPad: turn on iCloud Drive (System Settings ▸ Apple Account ▸ iCloud), then move this folder to iCloud Drive and name it Fuji Recipes. The app, Claude and /recipe follow it.")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 480)
        }
    }
}

/// Settings ▸ Clarity: its own Yes / No, because this window isn't the one the main alert is attached to.
private struct ClaritySetting: View {
    let model: AppModel
    @State private var asking = false
    var body: some View {
        Toggle("Clarity (slower saving)", isOn: Binding(get: { model.clarityOn }, set: { on in if on { asking = true } else { model.setClarity(false) } }))
            .alert("Turn on Clarity?", isPresented: $asking) {
                Button("Yes, Turn On") { model.setClarity(true) }
                Button("No", role: .cancel) {}
            } message: { Text("\(Preferences.clarityCost) Slots holding a recipe that uses it get its Clarity back.") }
        Text("Off: slots and Studio renders get Clarity 0, so the camera doesn't stop to store each shot. Recipes keep their own Clarity for when it's on.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
