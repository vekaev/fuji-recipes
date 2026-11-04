import FujiKit
import SwiftUI

/// Mac and wide iPad: a 38 pt top bar (Looks · Camera · Inbox, status, ⋯) over the page.
/// iPhone and narrow iPad: the same three pages as tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    var regular: Bool { sizeClass == .regular }
    #else
    let regular = true
    #endif

    var body: some View {
        @Bindable var model = model
        Group {
            if regular {
                VStack(spacing: 0) {
                    TopBar()
                    page(model.tab).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                TabView(selection: $model.tab) {
                    page(.looks).tabItem { Label("Looks", systemImage: "square.grid.2x2") }.tag(AppModel.Tab.looks)
                    page(.camera).tabItem { Label(model.connected ? (model.info?.model ?? "Camera") : "Camera", systemImage: "camera") }.tag(AppModel.Tab.camera)
                    page(.inbox).tabItem { Label("Inbox", systemImage: "tray") }.tag(AppModel.Tab.inbox)
                        .badge(model.toReview.count)
                }
                .tint(Theme.ink)
            }
        }
        .environment(\.regularLayout, regular)
        .background(Theme.paper)
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                HStack(spacing: 12) {
                    Text(t).font(.system(size: 12.5)).foregroundStyle(.white).multilineTextAlignment(.center)
                    if let a = model.toastAction {
                        Button(a.title) { model.toast = nil; model.toastAction = nil; a.run() }
                            .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.onPhoto, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, regular ? 26 : 90).padding(.horizontal, 20).transition(.opacity)
            }
        }
        .overlay { if model.preview != nil { PreviewOverlay().transition(.opacity) } }
        .animation(.easeOut(duration: 0.18), value: model.toast)
        .animation(.easeOut(duration: 0.15), value: model.preview)
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .help: SlotsHelpSheet()
            case .trouble: TroubleSheet()
            case .backups: BackupsSheet()
            case .review: ReviewSheet()
            case .settings: RecipeSettingsSheet()
            }
        }
    }

    @ViewBuilder private func page(_ t: AppModel.Tab) -> some View {
        switch t {
        case .looks: LooksView()
        case .camera: CameraView()
        case .inbox: InboxView()
        }
    }
}

private struct RegularLayoutKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var regularLayout: Bool { get { self[RegularLayoutKey.self] } set { self[RegularLayoutKey.self] = newValue } }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            tab(.looks) { Text("Looks") }
            tab(.camera) {
                HStack(spacing: 6) {
                    Circle().frame(width: 6, height: 6).opacity(model.connected ? 0.9 : 0.25)
                    Text(model.connected ? (model.info?.model ?? "Camera") + (Cameras.shared.simulate ? " (simulated)" : "") : model.busy != nil ? "Reading…" : "Camera")
                }
            }
            tab(.inbox) {
                HStack(spacing: 4) {
                    Text("Inbox")
                    if model.toReview.count + model.queuedCount > 0 { Text("\(model.toReview.count + model.queuedCount)").foregroundStyle(.secondary).monospacedDigit() }
                }
            }
            Spacer(minLength: 8)
            Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).monospacedDigit()
            Menu {
                Button("How to Use C1–C7 and FS1–FS3…") { model.sheet = .help }
                Button("Connection Check…") { model.sheet = .trouble }
                Button("Backups (\(model.backupCount))…") { model.sheet = .backups }
                Divider()
                Toggle("Ask Before Writing to the Camera", isOn: Binding(get: { model.askBeforeWriting }, set: { model.askBeforeWriting = $0 }))
                Divider()
                Button("Try with a Simulated X-E5") { model.trySimulated() }.disabled(model.connected)
                Button("Reload Library") { model.reload() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 28, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary)
        }
        #if os(macOS)
        .padding(.leading, 78)   // clear of the window buttons
        #else
        .padding(.leading, 14)
        #endif
        .padding(.trailing, 10)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .background(WindowDragArea())
        #endif
        .background(Theme.paper)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private var status: String {
        if let b = model.busy { return b }
        let n = model.changes.count
        if n > 0 && model.askBeforeWriting { return "\(n) change\(n > 1 ? "s" : "") for the camera" }
        if model.connected { return "In sync with the camera" }
        return "\(model.recipes.count) recipes"
    }

    private func tab<L: View>(_ t: AppModel.Tab, @ViewBuilder label: () -> L) -> some View {
        let on = model.tab == t
        return Button { model.tab = t } label: {
            label().font(.system(size: 12, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Theme.ink : .secondary)
                .padding(.horizontal, 10).frame(height: 26)
                .background(on ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-window preview of a look's photos (click / tap any image). ← → or swipe between them; Esc, Space or tap
/// outside closes, like Quick Look in Photo Minimalist.
struct PreviewOverlay: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var drag: CGFloat = 0

    var body: some View {
        if let p = model.preview {
            ZStack {
                Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { model.preview = nil }
                VStack(spacing: 12) {
                    HStack {
                        Text(p.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text("\(p.index + 1) / \(p.paths.count)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                        Spacer()
                        Button { model.preview = nil } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(.white).frame(width: 36, height: 36) }
                            .buttonStyle(.plain).accessibilityLabel("Close").keyboardShortcut(.cancelAction)
                    }
                    // One photo at a time (no TabView: on the Mac it draws an empty tab bar). Swipe or ← → to move.
                    PhotoTile(path: p.paths[p.index], maxPixel: 2400, fit: true)
                        .id(p.index)
                        .offset(x: drag)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 20)
                            .onChanged { drag = $0.translation.width * 0.6 }
                            .onEnded { v in
                                let w = v.translation.width
                                if w < -60 { step(1) } else if w > 60 { step(-1) }
                                withAnimation(.easeOut(duration: 0.15)) { drag = 0 }
                            })
                        .transition(.opacity)
                    HStack(spacing: 18) {
                        Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.disabled(p.index == 0)
                        Text(URL(fileURLWithPath: p.paths[p.index]).lastPathComponent).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }.disabled(p.index == p.paths.count - 1)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white).font(.system(size: 17, weight: .medium))
                }
                .padding(24)
                #if os(iOS)
                .padding(.bottom, 56)   // clear of the floating tab bar
                #endif
            }
            .focusable().focusEffectDisabled().focused($focused)
            .onAppear { focused = true }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
            .onKeyPress(.escape) { model.preview = nil; return .handled }
            .onKeyPress(.space) { model.preview = nil; return .handled }
        }
    }

    private func step(_ d: Int) {
        guard let p = model.preview else { return }
        model.preview?.index = max(0, min(p.paths.count - 1, p.index + d))
    }
}
