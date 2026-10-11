import SwiftUI
import PiKit

struct RightPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        let ws = model.workspace
        VStack(spacing: 0) {
            PanelTabBar()
            Divider().opacity(0.6)
            ZStack {
                switch ws.tab {
                case .review: ReviewPanel()
                case .files: FilesPanel()
                case .terminal: TerminalPanel()
                case .browser: BrowserPanel()
                case .file(let p):
                    if let f = ws.openFiles.first(where: { $0.path == p }) { FileViewerView(file: f).id(p) } else { FilesPanel() }
                case .subagent(let id): SubagentViewer(sessionId: id)
                }
            }
        }
        .background(Theme.background)
    }
}

struct PanelTabBar: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        let ws = model.workspace
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    PanelTabButton(icon: "plusminus.circle", title: "Review", active: ws.tab == .review, badge: ws.git.files.isEmpty ? nil : "\(ws.git.files.count)") { ws.tab = .review }
                    if ui.filePlacement == .panel { PanelTabButton(icon: "folder", title: "Files", active: ws.tab == .files) { ws.tab = .files } }
                    PanelTabButton(icon: "terminal", title: "Terminal", active: ws.tab == .terminal) { ws.tab = .terminal }
                    PanelTabButton(icon: "globe", title: "Browser", active: ws.tab == .browser) { ws.tab = .browser }
                    if !ws.openFiles.isEmpty { Rectangle().fill(Theme.separator).frame(width: 1, height: 16).padding(.horizontal, 4) }
                    ForEach(ws.openFiles) { f in
                        PanelTabButton(icon: nil, title: f.name, active: ws.tab == .file(f.path), file: f.path, onClose: { ws.close(f.path) }) { ws.tab = .file(f.path) }
                    }
                    if case .subagent(let id) = ws.tab {
                        PanelTabButton(icon: "person.2", title: "Subagent \(id.prefix(6))", active: true) {}
                    }
                }.padding(.horizontal, 8)
            }
            Button { withAnimation(.snappy(duration: 0.22)) { ui.rightPanelVisible = false } } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(HoverButtonStyle(size: 24)).padding(.trailing, 8).help("Close panel")
        }.frame(height: 40)
    }
}

struct PanelTabButton: View {
    let icon: String?
    let title: String
    let active: Bool
    var badge: String?
    var file: String?
    var onClose: (() -> Void)?
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 5) {
            if let file { FileIcon(path: file) } else if let icon { Image(systemName: icon).font(.system(size: 12)) }
            Text(title).font(.system(size: 12.5, weight: active ? .semibold : .medium)).lineLimit(1).frame(maxWidth: 160)
            if let badge { Text(badge).font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.primary.opacity(0.18))).foregroundStyle(Color.primary) }
            if let onClose, hover || active { Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.tertiary) }
        }
        .foregroundStyle(active ? Color.primary : Color.secondary)
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(active ? Color.primary.opacity(0.09) : (hover ? Color.primary.opacity(0.05) : .clear)))
        .contentShape(Capsule()).onHover { hover = $0 }.onTapGesture(perform: action)
    }
}

/// Read-only transcript of a subagent's session.
struct SubagentViewer: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    var body: some View {
        if let store = model.store(for: sessionId) {
            MessageList(store: store).task { await store.load(); await store.refreshState() }
        } else { EmptyState(icon: "person.2", title: "Subagent", text: "Not available.") }
    }
}
