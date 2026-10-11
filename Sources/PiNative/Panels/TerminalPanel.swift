import SwiftUI
import SwiftTerm
import PiKit

struct TerminalPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let ws = model.workspace
        VStack(spacing: 0) {
            if ws.terminals.isEmpty {
                VStack(spacing: 12) {
                    EmptyState(icon: "terminal", title: "No terminal", text: ws.cwd.map { "Open a shell in \(SidebarModel.folderName($0))." } ?? "Open a project first.")
                    if ws.cwd != nil { Button("New Terminal") { Task { await ws.newTerminal() } }.controlSize(.regular) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 4) {
                    ForEach(ws.terminals) { t in
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").font(.system(size: 10.5))
                            Text(t.title).font(.system(size: 12)).lineLimit(1)
                            Button { ws.closeTerminal(t.id) } label: { Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 9).frame(height: 24)
                        .background(Capsule().fill(ws.activeTerminal == t.id ? Color.primary.opacity(0.10) : .clear))
                        .contentShape(Capsule()).onTapGesture { ws.activeTerminal = t.id }
                    }
                    Button { Task { await ws.newTerminal() } } label: { Image(systemName: "plus").font(.system(size: 11)) }.buttonStyle(HoverButtonStyle(size: 24))
                    Spacer()
                }.padding(.horizontal, 8).frame(height: 32)
                Divider().opacity(0.6)
                ZStack {
                    ForEach(ws.terminals) { t in
                        SwiftTermView(session: t).opacity(ws.activeTerminal == t.id ? 1 : 0).allowsHitTesting(ws.activeTerminal == t.id)
                    }
                }
            }
        }
        .task(id: ws.cwd) { if ws.terminals.isEmpty, ws.cwd != nil, ws.tab == .terminal { await ws.newTerminal() } }
    }
}

struct SwiftTermView: NSViewRepresentable {
    let session: TerminalSession
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(session) }

    func makeNSView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: .zero)
        tv.terminalDelegate = context.coordinator
        tv.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        context.coordinator.view = tv
        applyColors(tv)
        session.setOutputHandler { [weak tv] s in tv?.feed(text: s) }
        session.attach()
        return tv
    }

    func updateNSView(_ tv: TerminalView, context: Context) { applyColors(tv) }

    private func applyColors(_ tv: TerminalView) {
        let dark = scheme == .dark
        tv.nativeBackgroundColor = dark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1) : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        tv.nativeForegroundColor = dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.12, alpha: 1)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let session: TerminalSession
        weak var view: TerminalView?
        init(_ s: TerminalSession) { session = s }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { session.resize(cols: newCols, rows: newRows) }
        func setTerminalTitle(source: TerminalView, title: String) { Task { @MainActor in if !title.isEmpty { self.session.title = title } } }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) { session.send(String(decoding: data, as: UTF8.self)) }
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) { if let u = URL(string: link) { NSWorkspace.shared.open(u) } }
        func clipboardCopy(source: TerminalView, content: Data) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding: content, as: UTF8.self), forType: .string) }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
