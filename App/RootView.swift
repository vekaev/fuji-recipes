import FujiKit
import SwiftUI

/// The window: Photo Minimalist's 38 pt top bar (window buttons, sidebar toggle, tabs, status, ⋯), then the camera
/// or the recipes. The camera is a tab, like a memory card in Photo Minimalist.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch model.tab {
                case .camera: if model.connected { SlotsView() } else { SetupView() }
                case .recipes: RecipesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.ground)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t).font(.system(size: 12)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.onPhoto, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 26).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.toast)
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .help: SlotsHelpSheet()
            case .trouble: TroubleSheet()
            case .backups: BackupsSheet()
            }
        }
    }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            Button { model.showSidebar.toggle() } label: {
                Image(systemName: "sidebar.left").font(.system(size: 13))
                    .frame(width: 28, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Show or hide the sidebar (⌃⌘S)")
            Theme.line.frame(width: 1, height: 16).padding(.horizontal, 8)
            tab(.camera) {
                HStack(spacing: 6) {
                    Circle().frame(width: 6, height: 6).opacity(model.connected ? 0.85 : 0.25)
                    Text(model.connected ? (model.info?.model ?? "Camera") + (model.simulated ? " (simulated)" : "") : model.busy != nil ? "Reading…" : "No camera")
                }
            }
            Theme.line.frame(width: 1, height: 14)
            tab(.recipes) { Text("Recipes") }
            Spacer(minLength: 8)
            Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .monospacedDigit().padding(.trailing, 4)
            Menu {
                Button("Check Connection") { Task { await model.check() } }
                Button("How to Use C1–C7 and FS1–FS3…") { model.sheet = .help }
                Button("Connection Troubleshooting…") { model.sheet = .trouble }
                Button("Backups (\(model.backupCount))…") { model.sheet = .backups }
                Divider()
                Button("Try with a Simulated X-E5") { model.trySimulated() }.disabled(model.connected)
                Button("Reload Recipes") { model.reloadLibrary() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 28, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 78)   // clear of the window buttons
        .padding(.trailing, 10)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(WindowDragArea())
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private var status: String {
        if let b = model.busy { return b }
        if model.connected {
            let changed = model.slots.filter(\.changed).count
            return changed > 0 ? "\(changed) slot\(changed > 1 ? "s" : "") changed · ⌘↵ to write" : "In sync with the camera"
        }
        let shots = model.recipes.filter { $0.status == "mine" }.reduce(0) { $0 + ($1.shots ?? 0) }
        return "\(model.recipes.count) recipes" + (shots > 0 ? " · \(shots) of your photos" : "")
    }

    private func tab<L: View>(_ t: AppModel.Tab, @ViewBuilder label: () -> L) -> some View {
        let on = model.tab == t
        return Button { model.tab = t } label: {
            label().font(.system(size: 12, weight: on ? .medium : .regular))
                .foregroundStyle(on ? .primary : .secondary)
                .padding(.horizontal, 10).frame(height: 26)
                .background(on ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
