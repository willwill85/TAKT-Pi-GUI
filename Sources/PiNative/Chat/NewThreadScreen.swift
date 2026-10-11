import SwiftUI
import PiBrand
import PiKit

struct NewThreadScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !ui.sidebarVisible {
                    Button { withAnimation(.snappy(duration: 0.22)) { ui.sidebarVisible = true } } label: { Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundStyle(.secondary) }
                        .buttonStyle(HoverButtonStyle()).padding(.leading, 74)
                }
                Spacer()
                Button { ui.showPanel(.terminal) } label: { Image(systemName: "terminal").font(.system(size: 14)).foregroundStyle(.secondary) }.buttonStyle(HoverButtonStyle()).help("Terminal")
                Button { withAnimation(.snappy(duration: 0.22)) { ui.rightPanelVisible.toggle() } } label: { Image(systemName: "sidebar.right").font(.system(size: 14)).foregroundStyle(ui.rightPanelVisible ? Color.primary : .secondary) }.buttonStyle(HoverButtonStyle()).padding(.trailing, 14)
            }.frame(height: 44).background(WindowDragArea())
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                        PiMark(size: 34)
                    }.frame(width: 48, height: 48).shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TAKT Pi").font(.system(size: 22, weight: .bold, design: .monospaced))
                        versionLine
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    ProjectBar()
                    ComposerView(draftKey: "__new__:" + (model.newThreadCwd ?? ""), store: nil, placeholder: "Ask Pi to build, fix, or explain something…")
                }
            }.frame(maxWidth: Theme.columnWidth).padding(.horizontal, 24)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
    }

    private var versionLine: some View {
        HStack(spacing: 4) {
            let v = model.appUpdate
            Text("web v\(v?.current ?? "—")")
            if let v, v.available, !v.latest.isEmpty {
                Text("→ v\(v.latest) ↗").foregroundStyle(Color.accentColor)
                    .onTapGesture { NSWorkspace.shared.open(URL(string: "https://github.com/agegr/pi-web/releases")!) }
            }
            Text("·")
            Text("pi v\(model.piVersion ?? piVersionGuess)")
            if let u = model.piUpdate, u.available {
                Text("→ v\(u.latest) Upgrade").foregroundStyle(Theme.accent)
                    .onTapGesture { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            }
        }.font(.system(size: 11.5)).foregroundStyle(.tertiary)
    }
    private var piVersionGuess: String { "1.1" }
}

/// Project + worktree pickers right above the composer (new-thread screen).
struct ProjectBar: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var branchInput = ""
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        let cwd = model.newThreadCwd ?? model.homeDirectory
        let ws = model.workspace
        HStack(spacing: 2) {
            Menu {
                let projects = model.sidebar.projects
                ForEach(projects) { g in
                    Button { pick(g.root) } label: { if g.root == (ws.worktree?.projectRoot ?? cwd) { Label(g.name, systemImage: "checkmark") } else { Text(g.name) } }
                }
                Divider()
                Button("Use default directory") { Task { await useDefault() } }
                Button("Open another project…") { chooseFolder() }
            } label: {
                HStack(spacing: 5) { Image(systemName: "folder").font(.system(size: 11.5)); Text(displayName(cwd)).font(.system(size: 12.5, weight: .medium, design: .monospaced)).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
                    .foregroundStyle(.secondary)
            }.menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).fixedSize().help(cwd)

            if let w = ws.worktree, w.isGit {
                let current = w.worktrees.first { $0.path == (w.currentPath ?? cwd) }
                Menu {
                    ForEach(w.worktrees) { t in
                        Button { pick(t.path) } label: { if t.path == current?.path { Label((t.branch ?? "detached") + (t.isMain ? " · main" : ""), systemImage: "checkmark") } else { Text((t.branch ?? "detached") + (t.isMain ? " · main" : "")) } }
                    }
                    Divider()
                    Button("New worktree…") { creating = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 11.5)).foregroundStyle(current?.isMain == false ? Color.primary : .secondary)
                        Text(current?.branch ?? "detached").font(.system(size: 12.5, weight: .medium, design: .monospaced)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }.foregroundStyle(.secondary).padding(.leading, 8)
                }.menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).fixedSize()
            }
            Spacer()
        }
        .padding(.horizontal, 6).frame(height: 28)
        .alert("New worktree", isPresented: $creating) {
            TextField("Branch name", text: $branchInput)
            Button("Create") { Task { await createWorktree() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(error ?? "Creates a linked checkout next to the project and starts the thread there.") }
        .task(id: cwd) { await ws.refreshWorktrees() }
    }

    private func displayName(_ cwd: String) -> String {
        if cwd == model.homeDirectory { return "~" }
        if let g = model.sidebar.projects.first(where: { $0.root == cwd }) { return g.name }
        return SidebarModel.folderName(cwd)
    }
    private func pick(_ path: String) { model.newThreadCwd = path; Task { await model.loadModels(cwd: path) } }
    private func useDefault() async {
        guard let c = model.client, let r = try? await c.post("/api/default-cwd"), let p = r["path"]?.string ?? r["cwd"]?.string else { return }
        pick(p)
    }
    private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: model.newThreadCwd ?? model.homeDirectory)
        if p.runModal() == .OK, let u = p.url { pick(u.path) }
    }
    private func createWorktree() async {
        guard let c = model.client else { return }
        let base = model.workspace.worktree?.projectRoot ?? model.newThreadCwd ?? ""
        do { if let path = try await GitService(client: c).addWorktree(cwd: base, branch: branchInput) { pick(path) }; branchInput = "" }
        catch { model.toast = error.localizedDescription }
    }
}
