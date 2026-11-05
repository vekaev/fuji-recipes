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
                #if os(macOS)
                .ignoresSafeArea(.container, edges: .top)   // the bar takes the title bar's place (window buttons inside)
                #endif
            } else {
                TabView(selection: $model.tab) {
                    page(.looks).tabItem { Label("Recipes", systemImage: "square.grid.2x2") }.tag(AppModel.Tab.looks)
                    page(.camera).tabItem { Label(model.connected ? (model.info?.model ?? "Camera") : "Camera", systemImage: "camera") }.tag(AppModel.Tab.camera)
                    page(.studio).tabItem { Label("Studio", systemImage: "square.stack.3d.down.right") }.tag(AppModel.Tab.studio)
                    page(.inbox).tabItem { Label("Add", systemImage: "plus.square.on.square") }.tag(AppModel.Tab.inbox)
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
                        .accessibilityIdentifier("toast")
                    if let a = model.toastAction {
                        Button(a.title) { model.toast = nil; model.toastAction = nil; a.run() }
                            .buttonStyle(.plain).pointer().font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
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
        #if os(macOS)
        // Mac: our own modal, so a click outside or Esc closes it (a system sheet ignores both).
        .overlay {
            if let sheet = model.sheet {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeSheet() }
                    sheetView(sheet)
                        .background(Theme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
                        .padding(.vertical, 40)
                    Button("") { model.closeSheet() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.sheet)
        #else
        .sheet(item: $model.sheet, onDismiss: {
            let hook = model.sheetWillClose
            model.sheetWillClose = nil
            hook?()
        }) { sheetView($0) }
        #endif
    }

    @ViewBuilder private func sheetView(_ sheet: AppModel.Sheet) -> some View {
        switch sheet {
        case .help: SlotsHelpSheet()
        case .trouble: TroubleSheet()
        case .backups: BackupsSheet()
        case .review: ReviewSheet()
        case .settings: RecipeSettingsSheet()
        case .slot: SlotSheet()
        case .connect: SetupView().sheetSize(920, 640)
        }
    }

    @ViewBuilder private func page(_ t: AppModel.Tab) -> some View {
        switch t {
        case .looks: LooksView()
        case .camera: if regular { LooksView() } else { CameraView() }   // Mac / iPad: slots live beside the looks
        case .studio: StudioView()
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
            tab(.looks) { Text("Recipes") }
            tab(.studio) { Text("Studio") }
            tab(.inbox) {
                HStack(spacing: 4) {
                    Text("Add recipes")
                    if model.toReview.count + model.queuedCount > 0 { Text("\(model.toReview.count + model.queuedCount)").foregroundStyle(.secondary).monospacedDigit() }
                }
            }
            Spacer(minLength: 8)
            if let s = status {
                Text(s).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).monospacedDigit()
                    .padding(.trailing, 6)
            }
            CameraStatus()
            Theme.line.frame(width: 1, height: 16).padding(.horizontal, 6)
            Menu {
                Button("How to Use C1–C7 and FS1–FS3…") { model.sheet = .help }
                Button("Connection Check…") { model.sheet = .trouble }
                Button("Backups (\(model.backupCount))…") { model.sheet = .backups }
                Divider()
                Toggle("Ask Before Writing to the Camera", isOn: Binding(get: { model.askBeforeWriting }, set: { model.askBeforeWriting = $0 }))
                Button("Add the Camera's Recipes to the Library") { model.syncSlotsToLibrary() }.disabled(!model.connected || model.syncingSlots)
                Toggle("Add Them When the Camera Connects", isOn: Binding(get: { model.syncSlots }, set: { model.syncSlots = $0 }))
                Divider()
                Button("Try with a Simulated X-E5") { model.trySimulated() }.disabled(model.connected)
                Button("Reload Library") { model.reload() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 28, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).pointer()
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

    /// Only while something is happening: a write, a read, or changes waiting for review.
    private var status: String? {
        if let b = model.busy { return b }
        let n = model.changes.count
        if n > 0 && model.askBeforeWriting { return "\(n) change\(n > 1 ? "s" : "") for the camera" }
        return nil
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
        .buttonStyle(.plain).pointer()
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
            let _ = model.studioVersion   // a full-size render landed
            let slug = p.recipes?[p.index] ?? nil
            let base = p.paths[p.index]
            let full = slug.flatMap { model.studioFull($0)?.path }
            let sharp = full == nil ? slug.flatMap { model.studioSharp($0)?.path } : nil
            let better = full ?? sharp
            let recipe = slug.flatMap { s in model.recipes.first { $0.slug == s } }
            ZStack {
                Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { model.preview = nil }
                VStack(spacing: 12) {
                    HStack {
                        Text(p.titles.map { $0[min(p.index, $0.count - 1)] } ?? p.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text("\(p.index + 1) / \(p.paths.count)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                        if let slug, model.studioFullLoading == slug {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Developing at full size…").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        if let r = recipe {
                            let picked = model.studioPicks.contains(r.slug)
                            Button { model.togglePick(r.slug) } label: {
                                Label(picked ? "Picked" : "Pick", systemImage: picked ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            }
                            .buttonStyle(.plain).pointer().help("Pick for this photo (P)").accessibilityIdentifier("preview.pick")
                            Button { model.toggleFavorite(r) } label: {
                                Image(systemName: r.status == "favorite" ? "heart.fill" : "heart").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain).pointer().help("Favorite recipe (F)")
                            .accessibilityLabel(r.status == "favorite" ? "Remove from favorites" : "Favorite")
                        }
                        Button { model.preview = nil } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(.white).frame(width: 36, height: 36) }
                            .buttonStyle(.plain).pointer().accessibilityLabel("Close").keyboardShortcut(.cancelAction)
                    }
                    // One photo at a time (no TabView: on the Mac it draws an empty tab bar). Swipe or ← → to move.
                    ZStack {
                        PhotoTile(path: base, maxPixel: 3000, fit: true).id(base)
                        if let better { PhotoTile(path: better, maxPixel: 3000, fit: true, quiet: true).id(better) }   // over the blurry one, no flash
                    }
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
                        Text(quality(slug: slug, full: full != nil, sharp: sharp != nil, name: URL(fileURLWithPath: base).lastPathComponent))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).accessibilityIdentifier("preview.quality")
                        Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }.disabled(p.index == p.paths.count - 1)
                    }
                    .buttonStyle(.plain).pointer().foregroundStyle(.white).font(.system(size: 17, weight: .medium))
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
            .onKeyPress(characters: CharacterSet(charactersIn: "pPзЗ"), phases: .down) { _ in
                if let r = recipe { model.togglePick(r.slug) }; return recipe == nil ? .ignored : .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "fFаА"), phases: .down) { _ in
                if let r = recipe { model.toggleFavorite(r) }; return recipe == nil ? .ignored : .handled
            }
            // The Studio's photo shown big is developed again at full size (the grid has the camera's 640-px previews).
            .task(id: "\(slug ?? "")|\(model.connected)") { model.loadStudioFull(slug) }   // the camera came back: full size now
            .onDisappear { model.loadStudioFull(nil) }
        }
    }

    /// Says what's on screen, so a soft picture is never a mystery.
    private func quality(slug: String?, full: Bool, sharp: Bool, name: String) -> String {
        guard slug != nil else { return name }
        if full { return "Full size" }
        let what = sharp ? "Detail from the RAW" : "Camera preview, 640 px"
        return model.connected ? what : what + " · full size needs the camera"
    }

    private func step(_ d: Int) {
        guard let p = model.preview else { return }
        model.preview?.index = max(0, min(p.paths.count - 1, p.index + d))
    }
}

/// The camera in the top bar: a green dot and its name when it's connected, a grey "No camera" (click: how to
/// connect) when not. Hover says since when.
struct CameraStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { if !model.connected { model.sheet = .connect } } label: {
            HStack(spacing: 6) {
                Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                Text(model.connected ? (model.info?.model ?? "Camera") + (Cameras.shared.simulate ? " (simulated)" : "")
                     : model.busy != nil ? "Reading…" : "No camera")
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(model.connected ? Theme.ink : .secondary)
            .padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointer()
        .help(help)
        .accessibilityLabel(help)
    }

    private var help: String {
        guard model.connected, let i = model.info else { return "Not connected · click for how to connect" }
        let since = model.connectedAt.map { " since \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "Connected\(since) · \(i.model), firmware \(i.firmware)"
    }
}
