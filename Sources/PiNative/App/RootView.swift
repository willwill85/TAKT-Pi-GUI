import SwiftUI
import PiKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
            switch model.sidecar.state {
            case .idle, .starting:
                StartupView(message: startingMessage)
            case .failed(let msg):
                FailureView(message: msg)
            case .ready:
                if model.sessionsLoaded { MainView() } else { StartupView(message: "Loading threads…") }
            }
        }
        .background(WindowConfigurator())
    }

    private var startingMessage: String {
        if case .starting(let m) = model.sidecar.state { return m }
        return "Starting…"
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        HStack(spacing: 0) {
            if ui.sidebarVisible {
                SidebarView()
                    .frame(width: ui.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                SidebarResizer(width: $ui.sidebarWidth)
            }
            ZStack(alignment: .top) {
                Theme.background
                DetailView()
            }
            if ui.rightPanelVisible {
                Rectangle().fill(Theme.separator).frame(width: 1)
                RightPanelView().frame(width: ui.rightPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $ui.searchOpen) { SearchPalette() }
        .overlay(alignment: .bottom) { ToastView() }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.selection {
        case .thread(let id):
            if let store = model.store(for: id) { ThreadScreen(store: store).id(id) } else { Color.clear }
        case .newThread:
            NewThreadScreen()
        }
    }
}

struct SidebarResizer: View {
    @Binding var width: CGFloat
    @State private var start: CGFloat?
    var body: some View {
        Rectangle().fill(Theme.separator).frame(width: 1)
            .overlay(Color.clear.frame(width: 8).contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        if start == nil { start = width }
                        width = min(420, max(220, (start ?? width) + v.translation.width))
                    }
                    .onEnded { _ in start = nil }))
    }
}

struct StartupView: View {
    let message: String
    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 14) {
                ProgressView().controlSize(.small)
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            WindowDragArea().frame(height: 40).frame(maxHeight: .infinity, alignment: .top)
        }.ignoresSafeArea()
    }
}

struct FailureView: View {
    @Environment(AppModel.self) private var model
    let message: String
    var body: some View {
        ZStack {
            Theme.background
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(.orange)
                Text("Can't start the Pi server").font(.title2.weight(.semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Retry") { model.restart(mode: PiNativeApp.connectionMode(), serverOverride: UserDefaults.standard.string(forKey: "serverDirectory")) }
                    Button("Open Log") { NSWorkspace.shared.open(model.sidecar.logURL) }
                }
            }.frame(maxWidth: 520).padding(40)
            WindowDragArea().frame(height: 40).frame(maxHeight: .infinity, alignment: .top)
        }.ignoresSafeArea()
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast {
            Text(t).font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.regularMaterial)).overlay(Capsule().strokeBorder(Theme.separator))
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t) { try? await Task.sleep(for: .seconds(3)); model.toast = nil }
        }
    }
}

/// Makes the window chrome match Codex: transparent title bar, full-size content.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = false
            w.setFrameAutosaveName("PiNativeMainWindow")
            w.tabbingMode = .disallowed
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
