import SwiftUI
import PiKit

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @AppStorage("collapsedProjects") private var collapsedRaw = ""
    @AppStorage("expandedMore") private var expandedMoreRaw = ""
    @State private var renaming: SessionInfo?
    @State private var renameText = ""
    @State private var renamingProject: ProjectGroup?
    @State private var deleting: SessionInfo?
    @State private var showArchived = false

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: "\n").map(String.init)) }
    private func toggleCollapsed(_ key: String) {
        var c = collapsed
        if c.contains(key) { c.remove(key) } else { c.insert(key) }
        collapsedRaw = c.sorted().joined(separator: "\n")
    }
    private var expandedMore: Set<String> { Set(expandedMoreRaw.split(separator: "\n").map(String.init)) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                WindowDragArea()
                Button { withAnimation(.snappy(duration: 0.22)) { ui.sidebarVisible = false } } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundStyle(.secondary)
                }.buttonStyle(HoverButtonStyle()).padding(.trailing, 10).help("Hide sidebar (⌘B)")
            }.frame(height: 44)

            VStack(spacing: 1) {
                SidebarActionRow(icon: "square.and.pencil", title: "New thread", shortcut: "⌘N") { model.startNewThread(); ui.focusComposer += 1 }
                SidebarActionRow(icon: "magnifyingglass", title: "Search", shortcut: "⌘K") { ui.searchOpen = true }
            }.padding(.horizontal, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    if !model.sidebar.pinnedFamilies.isEmpty {
                        SectionLabel("Pinned")
                        ForEach(model.sidebar.pinnedFamilies) { fam in familyRows(fam, showProject: true) }
                    }
                    HStack {
                        SectionLabel("Threads")
                        Spacer()
                    }
                    ForEach(model.sidebar.projects) { g in projectSection(g) }
                    if !model.sidebar.archived.isEmpty {
                        Button { withAnimation(.snappy(duration: 0.18)) { showArchived.toggle() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showArchived ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                                Text("Archived (\(model.sidebar.archived.count))").font(.system(size: 12.5, weight: .medium))
                                Spacer()
                            }.foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.top, 8)
                        if showArchived { ForEach(model.sidebar.archived) { fam in familyRows(fam, showProject: true) } }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 12)
            }.scrollIndicators(.never).padding(.top, 6)

            SidebarFooter()
        }
        .background(VisualEffectView(material: .sidebar))
        .alert("Rename thread", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let r = renaming { let n = renameText; Task { await model.rename(r.id, to: n) } }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Rename project", isPresented: Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let g = renamingProject { let n = renameText; Task { await model.renameProject(g, to: n.isEmpty ? nil : n) } }; renamingProject = nil }
            Button("Cancel", role: .cancel) { renamingProject = nil }
        }
        .confirmationDialog("Delete this thread?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { s in
            Button("Delete", role: .destructive) { Task { await model.delete(s.id) } }
        } message: { s in Text("“\(s.title)” will be permanently removed.") }
    }

    @ViewBuilder private func projectSection(_ g: ProjectGroup) -> some View {
        let isCollapsed = collapsed.contains(g.key)
        ProjectHeader(group: g, collapsed: isCollapsed,
                      toggle: { withAnimation(.snappy(duration: 0.18)) { toggleCollapsed(g.key) } },
                      newThread: { model.startNewThread(cwd: g.root); ui.focusComposer += 1 },
                      rename: { renameText = g.name; renamingProject = g },
                      togglePin: { Task { await model.setProjectPinned(g, !g.pinned) } })
        if !isCollapsed {
            let limit = expandedMore.contains(g.key) ? Int.max : 8
            ForEach(g.families.prefix(limit)) { fam in familyRows(fam, showProject: false) }
            if g.families.count > limit {
                Button("Show more") { expandedMoreRaw = (expandedMore.union([g.key])).sorted().joined(separator: "\n") }
                    .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(.tertiary).padding(.leading, 30).padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private func familyRows(_ fam: SessionFamily, showProject: Bool) -> some View {
        threadRow(fam.root, indent: 0, showProject: showProject, archived: fam.archived)
        ForEach(fam.children) { c in threadRow(c, indent: 14, showProject: false, archived: false) }
    }

    private func threadRow(_ s: SessionInfo, indent: CGFloat, showProject: Bool, archived: Bool) -> some View {
        ThreadRow(session: s, indent: indent, subtitle: showProject ? SidebarModel.folderName(s.projectRoot) : nil,
                  selected: model.selection == .thread(s.id),
                  running: model.running.contains(s.id), awaiting: model.awaiting.contains(s.id), unread: model.unread.contains(s.id),
                  pinned: model.ui.pinnedAt[s.id] != nil, archived: archived,
                  onSelect: { model.select(s.id) },
                  onArchive: { Task { await model.setArchived(s.id, !archived) } })
        .contextMenu {
            Button("Rename…") { renameText = s.title; renaming = s }
            Button(model.ui.pinnedAt[s.id] != nil ? "Unpin" : "Pin") { Task { await model.setPinned(s.id, model.ui.pinnedAt[s.id] == nil) } }
            Button("Fork") { Task { await model.fork(s.id) } }
            Button("Generate Title") { Task { await model.autoName(s.id) } }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.cwd)]) }
            Button("Copy Session ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s.id, forType: .string) }
            Divider()
            Button(archived ? "Unarchive" : "Archive") { Task { await model.setArchived(s.id, !archived) } }
            Button("Delete…", role: .destructive) { deleting = s }
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 4)
    }
}

struct SidebarActionRow: View {
    let icon: String, title: String, shortcut: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13.5)).frame(width: 18)
                Text(title).font(.system(size: 13.5))
                Spacer()
                if hover { Text(shortcut).font(.system(size: 11.5)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Theme.sidebarHover : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct ProjectHeader: View {
    let group: ProjectGroup
    let collapsed: Bool
    let toggle: () -> Void
    let newThread: () -> Void
    let rename: () -> Void
    let togglePin: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.pinned ? "pin.fill" : (collapsed ? "folder" : "folder")).font(.system(size: 12.5))
                .foregroundStyle(.secondary).frame(width: 18)
            Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(.primary.opacity(0.85))
            Spacer(minLength: 0)
            if hover {
                Menu {
                    Button(group.pinned ? "Unpin Project" : "Pin Project", action: togglePin)
                    Button("Rename…", action: rename)
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: group.root)]) }
                    Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(group.root, forType: .string) }
                } label: { Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                Button(action: newThread) { Image(systemName: "square.and.pencil").font(.system(size: 12)) }
                    .buttonStyle(HoverButtonStyle(size: 22, radius: 6)).help("New thread in \(group.name)")
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Theme.sidebarHover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: toggle)
        .help(group.root)
    }
}

struct ThreadRow: View {
    let session: SessionInfo
    let indent: CGFloat
    let subtitle: String?
    let selected: Bool
    let running: Bool, awaiting: Bool, unread: Bool, pinned: Bool, archived: Bool
    let onSelect: () -> Void
    let onArchive: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            statusView.frame(width: 14)
            Text(session.title).font(.system(size: 13.5)).lineLimit(1)
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.82))
            if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1) }
            Spacer(minLength: 4)
            if hover {
                Button(action: onArchive) { Image(systemName: archived ? "tray.and.arrow.up" : "archivebox").font(.system(size: 11.5)) }
                    .buttonStyle(HoverButtonStyle(size: 22, radius: 6)).help(archived ? "Unarchive" : "Archive")
            } else {
                Text(relativeTime(session.modified)).font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 10 + indent).padding(.trailing, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.sidebarSelection : (hover ? Theme.sidebarHover : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder private var statusView: some View {
        if running { SpinnerView() }
        else if awaiting { Circle().fill(Theme.warning).frame(width: 7, height: 7) }
        else if unread { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
        else if session.relation?.kind == .subagent { Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(.tertiary) }
        else if pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.tertiary) }
        else { Color.clear }
    }
}

struct SpinnerView: View {
    var size: CGFloat = 11
    @State private var spin = false
    var body: some View {
        Circle().trim(from: 0, to: 0.72).stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: size, height: size).rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
    }
}

struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    @State private var remote = RemotePiStatus.shared
    var body: some View {
        HStack(spacing: 6) {
            SettingsLink {
                HStack(spacing: 8) { Image(systemName: "gearshape").font(.system(size: 13.5)); Text("Settings").font(.system(size: 13.5)) }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.primary.opacity(0.8))
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(remote.online ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                Text("Remote Pi").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }.help(remote.online ? "remote-pi supervisor is running" : "remote-pi supervisor is not running").padding(.trailing, 10)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .task { remote.start() }
    }
}

/// Is the remote-pi supervisor alive? (`~/.pi/remote/supervisor.sock`)
@MainActor @Observable
final class RemotePiStatus {
    static let shared = RemotePiStatus()
    var online = false
    private var task: Task<Void, Never>?
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let path = NSHomeDirectory() + "/.pi/remote/supervisor.sock"
                self?.online = FileManager.default.fileExists(atPath: path)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
