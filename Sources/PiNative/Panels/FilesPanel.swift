import SwiftUI
import PiKit

struct FilesPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var query = ""
    @State private var results: [String] = []
    @State private var index: [String] = []
    @State private var indexCwd: String?
    var compact = false

    var body: some View {
        let ws = model.workspace
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                TextField("Search files", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain) }
                Menu {
                    Toggle("Show hidden & ignored", isOn: Binding(get: { ws.showHidden }, set: { ws.showHidden = $0 }))
                    Button("Refresh") { Task { await ws.reloadTree() } }
                    Button("Upload files…") { upload() }
                    if let cwd = ws.cwd { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)]) } }
                } label: { Image(systemName: "ellipsis").font(.system(size: 12)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface)).padding(.horizontal, 10).padding(.vertical, 8)

            if let cwd = ws.cwd {
                if !query.isEmpty {
                    List(results, id: \.self) { rel in
                        HStack(spacing: 8) {
                            FileIcon(path: rel).frame(width: 16)
                            Text((rel as NSString).lastPathComponent).font(.system(size: 13)).lineLimit(1)
                            Text((rel as NSString).deletingLastPathComponent).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle()).onTapGesture { ui.openFile((cwd as NSString).appendingPathComponent(rel)) }
                    }.listStyle(.plain)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if let e = ws.treeError { Text(e).font(.system(size: 12)).foregroundStyle(.secondary).padding(12) }
                            TreeRows(dir: cwd, depth: 0)
                        }.padding(.horizontal, 6).padding(.bottom, 10)
                    }
                }
            } else {
                Text("No project").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: ws.cwd) { await loadIndex() }
        .onChange(of: query) { _, q in search(q) }
    }

    private func loadIndex() async {
        guard let cwd = model.workspace.cwd, let client = model.client, indexCwd != cwd else { return }
        indexCwd = cwd
        if let d = try? await client.get("/api/file-index", query: ["cwd": cwd]) { index = (d["files"]?.array ?? []).compactMap(\.string) }
    }

    private func search(_ q: String) {
        let s = q.lowercased()
        guard !s.isEmpty else { results = []; return }
        func score(_ p: String) -> Int? {
            let name = (p as NSString).lastPathComponent.lowercased(), full = p.lowercased()
            if name == s { return 0 }
            if name.hasPrefix(s) { return 1 }
            if name.contains(s) { return 2 }
            if full.contains(s) { return 3 }
            // subsequence
            var it = full.makeIterator(); var ok = true
            for ch in s { var found = false; while let c = it.next() { if c == ch { found = true; break } }; if !found { ok = false; break } }
            return ok ? 4 : nil
        }
        results = index.compactMap { p in score(p).map { (p, $0) } }.sorted { ($0.1, $0.0.count) < ($1.1, $1.0.count) }.prefix(60).map(\.0)
    }

    private func upload() {
        guard let cwd = model.workspace.cwd, let f = model.files else { return }
        let p = NSOpenPanel(); p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        Task { try? await f.upload(p.urls, to: cwd); await model.workspace.loadDir(cwd) }
    }
}

struct TreeRows: View {
    let dir: String
    let depth: Int
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        let ws = model.workspace
        ForEach(ws.entries[dir] ?? []) { e in
            TreeRow(entry: e, depth: depth, open: e.isDir && ws.expanded.contains(e.path), selected: ws.tab == .file(e.path))
                .onTapGesture {
                    if e.isDir { withAnimation(.snappy(duration: 0.15)) { ws.toggle(e.path) } } else { ui.openFile(e.path) }
                }
                .contextMenu {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)]) }
                    Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(e.path, forType: .string) }
                    if let cwd = ws.cwd, e.path.hasPrefix(cwd) { Button("Copy Relative Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(e.path.dropFirst(cwd.count + 1)), forType: .string) } }
                    if !e.isDir { Button("Open with Default App") { NSWorkspace.shared.open(URL(fileURLWithPath: e.path)) } }
                    Button("Attach to Message") { ui.attachMention(e.path) }
                }
            if e.isDir && ws.expanded.contains(e.path) { TreeRows(dir: e.path, depth: depth + 1) }
        }
    }
}

struct TreeRow: View {
    let entry: FileEntry
    let depth: Int
    let open: Bool
    let selected: Bool
    @State private var hover = false
    var body: some View {
        HStack(spacing: 5) {
            if entry.isDir { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary).rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12) }
            else { Color.clear.frame(width: 12) }
            if entry.isDir { Image(systemName: open ? "folder.fill" : "folder").font(.system(size: 12.5)).foregroundStyle(Color.accentColor.opacity(0.85)).frame(width: 16) }
            else { FileIcon(path: entry.path).frame(width: 16) }
            Text(entry.name).font(.system(size: 13)).lineLimit(1).foregroundStyle(entry.hidden != nil ? .secondary : .primary)
            if entry.linkTarget != nil { Image(systemName: "arrow.turn.up.right").font(.system(size: 9)).foregroundStyle(.tertiary) }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14 + 6).padding(.trailing, 6).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.sidebarSelection : hover ? Theme.sidebarHover : .clear))
        .contentShape(Rectangle()).onHover { hover = $0 }
    }
}
