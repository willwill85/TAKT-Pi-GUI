import SwiftUI
import PiKit

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @AppStorage("expandedProjects") private var expandedRaw = ""
    @AppStorage("expandedMore") private var expandedMoreRaw = ""
    @AppStorage("pinnedCollapsed") private var pinnedCollapsed = false
    @State private var renaming: SessionInfo?
    @State private var renameText = ""
    @State private var renamingProject: ProjectGroup?
    @State private var deleting: SessionInfo?
    @State private var showArchived = false
    @State private var tagFilter: Set<String> = []

    private var expanded: Set<String> { Set(expandedRaw.split(separator: "\n").map(String.init)) }
    private func setExpanded(_ keys: Set<String>) { expandedRaw = keys.sorted().joined(separator: "\n") }
    private func toggleExpanded(_ key: String) {
        var c = expanded
        if c.contains(key) { c.remove(key) } else { c.insert(key) }
        setExpanded(c)
    }
    private var expandedMore: Set<String> { Set(expandedMoreRaw.split(separator: "\n").map(String.init)) }

    // Tag filter: a project shows when it carries a selected tag, or one of its threads does.
    private func familyMatches(_ fam: SessionFamily) -> Bool {
        tagFilter.isEmpty || fam.all.contains { s in model.tagState.tags(forSession: s.id).contains { tagFilter.contains($0.id) } }
    }
    private func projectMatches(_ g: ProjectGroup) -> Bool {
        tagFilter.isEmpty || model.tagState.tags(forProject: g.key).contains { tagFilter.contains($0.id) } || g.families.contains(where: familyMatches)
    }
    private func visibleFamilies(_ g: ProjectGroup) -> [SessionFamily] {
        guard !tagFilter.isEmpty else { return g.families }
        if model.tagState.tags(forProject: g.key).contains(where: { tagFilter.contains($0.id) }) { return g.families }
        return g.families.filter(familyMatches)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                WindowDragArea()
                Button { withAnimation(.snappy(duration: 0.22)) { ui.sidebarVisible = false } } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundStyle(.secondary)
                }.buttonStyle(HoverButtonStyle()).padding(.trailing, 10).help("Hide sidebar (⌘B)")
            }.frame(height: 44)

            VStack(spacing: 1) {
                SidebarActionRow(icon: "square.and.pencil", title: "New thread", shortcut: "⌘N", selected: model.selection == .newThread) { model.startNewThread(); ui.focusComposer += 1 }
                SidebarActionRow(icon: "magnifyingglass", title: "Search", shortcut: "⌘K") { ui.searchOpen = true }
                SidebarActionRow(icon: "clock.arrow.circlepath", title: "Automations", shortcut: "", selected: model.selection == .automations) { model.showAutomations() }
            }.padding(.horizontal, 8)

            if !model.tagState.tags.isEmpty { TagFilterBar(filter: $tagFilter) }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let pinned = model.sidebar.pinnedFamilies.filter(familyMatches)
                    if !pinned.isEmpty {
                        Button { withAnimation(.snappy(duration: 0.18)) { pinnedCollapsed.toggle() } } label: {
                            HStack(spacing: 4) {
                                Text("Pinned").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
                                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).rotationEffect(.degrees(pinnedCollapsed ? 0 : 90))
                                Spacer()
                            }.padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if !pinnedCollapsed { ForEach(pinned) { fam in familyRows(fam, showProject: true) } }
                    }
                    HStack {
                        SectionLabel("Threads")
                        Spacer()
                        Menu {
                            Button("Collapse all projects") { setExpanded([]) }
                            Button("Expand all projects") { setExpanded(Set(model.sidebar.projects.map(\.key))) }
                            Divider()
                            Button("Manage tags…") { ui.activeSheet = .tags }
                        } label: { Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 22, height: 22) }
                            .menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).frame(width: 26).padding(.top, 10)
                    }
                    ForEach(model.sidebar.projects.filter(projectMatches)) { g in projectSection(g) }
                    if !model.sidebar.archived.isEmpty && tagFilter.isEmpty {
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
            }.scrollIndicators(.never).padding(.top, 4)

            if ui.filePlacement == .sidebar { SidebarFilesSection() }
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
        let isOpen = expanded.contains(g.key) || !tagFilter.isEmpty
        let fams = visibleFamilies(g)
        ProjectHeader(group: g, open: isOpen, tags: model.tagState.tags(forProject: g.key),
                      toggle: { withAnimation(.snappy(duration: 0.18)) { toggleExpanded(g.key) } },
                      newThread: { model.startNewThread(cwd: g.root); ui.focusComposer += 1 },
                      rename: { renameText = g.name; renamingProject = g },
                      collapseOthers: { setExpanded([g.key]) },
                      expandAll: { setExpanded(Set(model.sidebar.projects.map(\.key))) })
        if isOpen {
            let limit = expandedMore.contains(g.key) ? Int.max : 8
            ForEach(fams.prefix(limit)) { fam in familyRows(fam, showProject: false) }
            if fams.count > limit {
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
                  tags: model.tagState.tags(forSession: s.id),
                  selected: model.selection == .thread(s.id),
                  running: model.running.contains(s.id), awaiting: model.awaiting.contains(s.id), unread: model.unread.contains(s.id),
                  pinned: model.ui.pinnedAt[s.id] != nil, archived: archived,
                  onSelect: { model.select(s.id) },
                  onArchive: { Task { await model.setArchived(s.id, !archived) } })
        .contextMenu {
            Button("Rename…") { renameText = s.title; renaming = s }
            Button(model.ui.pinnedAt[s.id] != nil ? "Unpin" : "Pin") { Task { await model.setPinned(s.id, model.ui.pinnedAt[s.id] == nil) } }
            Button("Fork") { Task { await model.fork(s.id) } }
            Button(model.namingNow.contains(s.id) ? "Generating title…" : "Generate Title") { Task { await model.autoName(s.id) } }.disabled(model.namingNow.contains(s.id))
            if !model.tagState.tags.isEmpty {
                Menu("Tags") {
                    ForEach(model.tagState.tags) { t in
                        Toggle(t.name, isOn: Binding(get: { model.tagState.sessionAssignments[s.id]?.contains(t.id) ?? false }, set: { _ in Task { await model.toggleSessionTag(s.id, tag: t.id) } }))
                    }
                }
            }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.cwd)]) }
            Button("Copy Session ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s.id, forType: .string) }
            Divider()
            Button(archived ? "Unarchive" : "Archive") { Task { await model.setArchived(s.id, !archived) } }
            Button("Delete…", role: .destructive) { deleting = s }
        }
    }
}

struct TagChip: View {
    let tag: ProjectTag
    var small = false
    var body: some View {
        Text(tag.name).font(.system(size: small ? 10 : 11, weight: .semibold)).lineLimit(1)
            .padding(.horizontal, small ? 5 : 7).padding(.vertical, 1.5)
            .background(Capsule().fill(Color(hex: tag.color)))
            .foregroundStyle(Color(hex: tag.color).isLight ? Color.black.opacity(0.8) : Color.white)
    }
}

struct TagFilterBar: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Binding var filter: Set<String>
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button { filter = [] } label: {
                    Text("All").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(filter.isEmpty ? Color.primary.opacity(0.14) : Color.primary.opacity(0.05)))
                }.buttonStyle(.plain)
                ForEach(model.tagState.tags) { t in
                    let on = filter.contains(t.id)
                    Button { if on { filter.remove(t.id) } else { filter.insert(t.id) } } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: t.color)).frame(width: 7, height: 7)
                            Text(t.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(on ? Color(hex: t.color).opacity(0.28) : Color.primary.opacity(0.05)))
                        .overlay(Capsule().strokeBorder(on ? Color(hex: t.color) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                Button { ui.activeSheet = .tags } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 10.5)).foregroundStyle(.tertiary) }.buttonStyle(.plain).help("Manage tags")
            }.padding(.horizontal, 14)
        }.frame(height: 28).padding(.top, 6)
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    var isLight: Bool {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return (0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent) > 0.62
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
    var selected = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13.5)).frame(width: 18)
                Text(title).font(.system(size: 13.5))
                Spacer()
                if hover, !shortcut.isEmpty { Text(shortcut).font(.system(size: 11.5)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.sidebarSelection : hover ? Theme.sidebarHover : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct ProjectHeader: View {
    let group: ProjectGroup
    let open: Bool
    let tags: [ProjectTag]
    let toggle: () -> Void
    let newThread: () -> Void
    let rename: () -> Void
    let collapseOthers: () -> Void
    let expandAll: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var hover = false
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.pinned ? "pin.fill" : (open ? "folder" : "folder")).font(.system(size: 12.5))
                .foregroundStyle(.secondary).frame(width: 18)
            Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(.primary.opacity(0.85))
            if !hover { ForEach(tags.prefix(2)) { TagChip(tag: $0, small: true) } }
            Spacer(minLength: 0)
            if hover {
                Menu { menuItems } label: { Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).frame(width: 22)
                Button(action: newThread) { Image(systemName: "square.and.pencil").font(.system(size: 12)) }
                    .buttonStyle(HoverButtonStyle(size: 22, radius: 6)).help("New thread in \(group.name)")
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Theme.sidebarHover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: toggle)
        .contextMenu { menuItems }
        .help(group.root)
        .confirmationDialog("Remove “\(group.name)” from the list?", isPresented: $confirmRemove) {
            Button("Archive all threads", role: .destructive) { Task { await model.removeProjectFromList(group) } }
        } message: { Text("All threads of this project are archived. You can restore them from Archived.") }
    }

    @ViewBuilder private var menuItems: some View {
        Button(group.pinned ? "Unpin Project" : "Pin Project") { Task { await model.setProjectPinned(group, !group.pinned) } }
        Button("Rename…", action: rename)
        if !model.tagState.tags.isEmpty {
            Menu("Tags") {
                ForEach(model.tagState.tags) { t in
                    Toggle(t.name, isOn: Binding(get: { model.tagState.projectAssignments[group.key]?.contains(t.id) ?? false }, set: { _ in Task { await model.toggleProjectTag(group.key, tag: t.id) } }))
                }
            }
        }
        Button("Project Settings…") { ui.activeSheet = .projectSettings(group.key) }
        Divider()
        Button("Move Up") { Task { await model.moveProject(group, up: true) } }.disabled(!model.canMoveProject(group, up: true))
        Button("Move Down") { Task { await model.moveProject(group, up: false) } }.disabled(!model.canMoveProject(group, up: false))
        let older = model.olderThanWeekCount(group)
        Button("Archive threads older than a week (\(older))") { Task { await model.archiveOlderThanWeek(group) } }.disabled(older == 0)
        Button("Remove from list…", role: .destructive) { confirmRemove = true }
        Divider()
        Button("Open in Files") { model.startNewThreadContextIfNeeded(group.root); ui.openDirectory(group.root) }
        Button("Collapse other projects", action: collapseOthers)
        Button("Expand all projects", action: expandAll)
        Divider()
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: group.root)]) }
        Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(group.root, forType: .string) }
    }
}

struct ThreadRow: View {
    let session: SessionInfo
    let indent: CGFloat
    let subtitle: String?
    var tags: [ProjectTag] = []
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
            if !hover { ForEach(tags.prefix(2)) { Circle().fill(Color(hex: $0.color)).frame(width: 7, height: 7).help($0.name) } }
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
        else if unread { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
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
    @State private var showUsage = false
    @State private var showUpgrade = false
    var body: some View {
        HStack(spacing: 4) {
            SettingsLink {
                HStack(spacing: 8) { Image(systemName: "gearshape").font(.system(size: 13.5)); Text("Settings").font(.system(size: 13.5)) }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.primary.opacity(0.8))
            Spacer(minLength: 0)
            Button { showUsage.toggle() } label: {
                Image(systemName: "chart.bar").font(.system(size: 12.5)).frame(width: 26, height: 26).contentShape(Rectangle())
            }.buttonStyle(HoverButtonStyle()).foregroundStyle(.secondary).help("Balance & spend")
                .popover(isPresented: $showUsage, arrowEdge: .top) { UsagePopover() }
            statusPill
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .task { remote.start() }
    }

    /// Where the Remote Pi indicator lives: an available pi upgrade takes its place until it is applied.
    @ViewBuilder private var statusPill: some View {
        if let u = model.piUpdate, u.available || model.piUpgrading {
            Button { showUpgrade.toggle() } label: {
                HStack(spacing: 5) {
                    if model.piUpgrading { SpinnerView(size: 9) } else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 11)) }
                    Text(model.piUpgrading ? "Upgrading…" : "Pi \(u.latest)").font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Theme.accent).padding(.horizontal, 8).frame(height: 24)
                .background(Capsule().fill(Theme.accent.opacity(0.14)))
            }.buttonStyle(.plain).help("pi \(u.latest) is available (you have \(u.current))")
                .popover(isPresented: $showUpgrade, arrowEdge: .top) { PiUpgradePopover() }
                .padding(.trailing, 4)
        } else {
            HStack(spacing: 5) {
                Circle().fill(remote.online ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                Text("Remote Pi").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }.help(remote.online ? "remote-pi supervisor is running" : "remote-pi supervisor is not running").padding(.horizontal, 8)
        }
    }
}

struct PiUpgradePopover: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let u = model.piUpdate
        VStack(alignment: .leading, spacing: 10) {
            Text("Pi update available").font(.system(size: 13.5, weight: .semibold))
            Text("v\(u?.current ?? "?") → v\(u?.latest ?? "?")").font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.secondary)
            Text("Runs `pi update self`. Threads that are already running keep the old version until restarted.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let m = model.piUpdateMessage { Text(m).font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack {
                Button("Check Now") { Task { await model.checkPiUpdate(force: true) } }.controlSize(.small).disabled(model.piChecking || model.piUpgrading)
                Spacer()
                Button(model.piUpgrading ? "Upgrading…" : "Upgrade") { Task { await model.upgradePi() } }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(model.piUpgrading)
            }
        }.padding(14).frame(width: 300)
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

/// The file browser as a section under the thread list (Settings › General › File browser).
struct SidebarFilesSection: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var dragStart: CGFloat?

    var body: some View {
        @Bindable var ui = ui
        VStack(spacing: 0) {
            if !ui.filesSectionCollapsed {
                Rectangle().fill(Theme.separator).frame(height: 1)
                    .overlay(Color.clear.frame(height: 9).contentShape(Rectangle())
                        .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in
                                if dragStart == nil { dragStart = ui.filesSectionHeight }
                                ui.filesSectionHeight = min(600, max(160, (dragStart ?? 280) - v.translation.height))
                            }.onEnded { _ in dragStart = nil }))
            }
            Button { withAnimation(.snappy(duration: 0.2)) { ui.filesSectionCollapsed.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold)).rotationEffect(.degrees(ui.filesSectionCollapsed ? 0 : 90)).frame(width: 12)
                    Text("FILES").font(.system(size: 11, weight: .semibold)).tracking(0.4)
                    if let cwd = model.workspace.cwd { Text(SidebarModel.folderName(cwd)).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1).tracking(0) }
                    Spacer()
                    if !model.workspace.git.files.isEmpty { Text("\(model.workspace.git.files.count) changed").font(.system(size: 11)).foregroundStyle(.tertiary).tracking(0) }
                }.foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !ui.filesSectionCollapsed {
                FilesPanel(compact: true).frame(height: ui.filesSectionHeight)
            }
        }
    }
}
