import SwiftUI
import PiKit

// MARK: - Tags manager (global: create / rename / recolor / delete)

struct TagsManagerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = Color(hex: "#7c8cff")
    @State private var error: String?
    @State private var editing: ProjectTag?
    @State private var editName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Tags").font(.system(size: 17, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            Text("Colored labels to organise projects and threads in the sidebar. Assign them from a project or thread menu.").font(.system(size: 12.5)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("New tag name", text: $name).textFieldStyle(.roundedBorder).onSubmit(add)
                ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
                Button("Add", action: add).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.removed) }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.tagState.tags) { t in
                        let projects = model.tagState.projectAssignments.values.filter { $0.contains(t.id) }.count
                        let threads = model.tagState.sessionAssignments.values.filter { $0.contains(t.id) }.count
                        HStack(spacing: 10) {
                            TagChip(tag: t)
                            Text("\(projects) project\(projects == 1 ? "" : "s") · \(threads) thread\(threads == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(.tertiary)
                            Spacer()
                            ColorPicker("", selection: Binding(get: { Color(hex: t.color) }, set: { c in Task { await model.tagAction(["action": "update", "id": t.id, "color": c.hexString]) } }), supportsOpacity: false).labelsHidden()
                            Button("Rename") { editing = t; editName = t.name }.controlSize(.small)
                            Button("Delete", role: .destructive) { Task { error = await model.tagAction(["action": "delete", "id": t.id]) } }.controlSize(.small)
                        }.padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                    }
                    if model.tagState.tags.isEmpty { Text("No tags yet").foregroundStyle(.secondary).padding(30) }
                }
            }.frame(height: 260)
        }
        .padding(22).frame(width: 520)
        .alert("Rename tag", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Name", text: $editName)
            Button("Save") { if let t = editing { let n = editName; Task { error = await model.tagAction(["action": "update", "id": t.id, "name": n]) } }; editing = nil }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        Task { error = await model.tagAction(["action": "create", "name": n, "color": color.hexString]); if error == nil { name = "" } }
    }
}

extension Color {
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02x%02x%02x", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

// MARK: - Project settings (everything scoped to one project)

struct ProjectSettingsSheet: View {
    let projectKey: String
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var structure: JSON?
    @State private var trust: JSON?
    @State private var worktrees: WorktreeContext?
    @State private var newBranch = ""
    @State private var error: String?

    private var group: ProjectGroup? { model.sidebar.projects.first { $0.key == projectKey } }
    private var root: String { group?.root ?? projectKey }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group?.name ?? SidebarModel.folderName(root)).font(.system(size: 16, weight: .semibold))
                    Text(shortPath(root)).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(18)
            Picker("", selection: $tab) { Text("Tags").tag(0); Text("Structure").tag(1); Text("Worktrees").tag(2); Text("Trust & MCP").tag(3) }
                .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 18)
            Divider().padding(.top, 12)
            ScrollView {
                Group {
                    switch tab {
                    case 0: tagsTab
                    case 1: structureTab
                    case 2: worktreeTab
                    default: trustTab
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 600, height: 520)
        .task { await loadAll() }
    }

    private func loadAll() async {
        guard let c = model.client else { return }
        structure = try? await c.get("/api/project-structure", query: ["cwd": root])
        trust = try? await c.get("/api/project-trust", query: ["cwd": root])
        worktrees = await GitService(client: c).worktrees(cwd: root)
    }

    private var tagsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags for this project").font(.system(size: 13, weight: .semibold))
            if model.tagState.tags.isEmpty {
                Text("You have no tags yet.").foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                ForEach(model.tagState.tags) { t in
                    let on = model.tagState.projectAssignments[projectKey]?.contains(t.id) ?? false
                    Button { Task { await model.toggleProjectTag(projectKey, tag: t.id) } } label: {
                        HStack(spacing: 5) { Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 11)); TagChip(tag: t) }
                            .padding(.horizontal, 6).padding(.vertical, 4).background(Capsule().fill(on ? Color.primary.opacity(0.08) : .clear)).overlay(Capsule().strokeBorder(Theme.separator))
                    }.buttonStyle(.plain)
                }
            }
            Button("Manage tags…") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ui.activeSheet = .tags } }.controlSize(.small)
        }
    }

    private var structureTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = structure {
                Text("\(s["totalFiles"]?.int ?? 0) files").font(.system(size: 13, weight: .semibold))
                let nodes = (s["nodes"]?.array ?? []).sorted { ($0["lines"]?.int ?? 0) > ($1["lines"]?.int ?? 0) }
                let maxLines = max(1, nodes.first?["lines"]?.int ?? 1)
                ForEach(Array(nodes.prefix(24).enumerated()), id: \.offset) { _, n in
                    HStack(spacing: 10) {
                        Text(n["dir"]?.string ?? "").font(Theme.mono(12)).lineLimit(1).truncationMode(.head).frame(width: 220, alignment: .leading)
                        GeometryReader { g in RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.55)).frame(width: g.size.width * CGFloat(n["lines"]?.int ?? 0) / CGFloat(maxLines)) }.frame(height: 8)
                        Text("\(n["files"]?.int ?? 0) files · \(n["lines"]?.int ?? 0) lines").font(.system(size: 11.5)).foregroundStyle(.tertiary).frame(width: 130, alignment: .trailing)
                    }.onTapGesture { ui.openDirectory((root as NSString).appendingPathComponent(n["dir"]?.string ?? "")) }
                }
                if s["truncated"]?.bool == true { Text("Scan truncated.").font(.system(size: 12)).foregroundStyle(.secondary) }
            } else { ProgressView().controlSize(.small) }
        }
    }

    private var worktreeTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let w = worktrees, w.isGit {
                ForEach(w.worktrees) { t in
                    HStack {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(t.isMain ? Color.secondary : Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(t.branch ?? "detached").font(.system(size: 13, weight: .medium)) + Text(t.isMain ? "  main checkout" : "").font(.system(size: 11.5)).foregroundColor(.secondary)
                            Text(shortPath(t.path)).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Button("New thread") { dismiss(); model.startNewThread(cwd: t.path) }.controlSize(.small)
                        if !t.isMain { Button("Remove", role: .destructive) { Task { do { try await GitService(client: model.client!).removeWorktree(cwd: root, path: t.path, force: false); await loadAll() } catch { self.error = error.localizedDescription } } }.controlSize(.small) }
                    }.padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                }
                HStack { TextField("New branch name", text: $newBranch).textFieldStyle(.roundedBorder)
                    Button("Create worktree") { Task { do { _ = try await GitService(client: model.client!).addWorktree(cwd: root, branch: newBranch); newBranch = ""; await loadAll() } catch { self.error = error.localizedDescription } } }.disabled(newBranch.isEmpty) }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.removed) }
            } else { Text("This folder isn't a Git repository.").foregroundStyle(.secondary) }
        }
    }

    private var trustTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = trust {
                let requires = t["requiresTrust"]?.bool ?? false, trusted = t["trusted"]?.bool ?? false
                HStack {
                    Image(systemName: trusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill").foregroundStyle(trusted ? .green : .orange)
                    Text(!requires ? "This project has no project-level resources that need trust." : trusted ? "Project resources are trusted." : "Project resources are NOT trusted — project MCP servers and extensions are not loaded.").font(.system(size: 13))
                }
                if requires {
                    if !trusted { Button("Trust this project") { Task { _ = try? await model.client?.post("/api/project-trust", body: ["cwd": root]); await loadAll() } }.buttonStyle(.borderedProminent) }
                }
                let servers = t["mcpServers"]?.array ?? []
                Text("Project MCP servers (\(servers.count))").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
                ForEach(Array(servers.enumerated()), id: \.offset) { _, s in
                    HStack { Image(systemName: "puzzlepiece.extension"); Text(s["name"]?.string ?? "server").font(.system(size: 13)); Spacer(); Text(s["transport"]?.string ?? s["kind"]?.string ?? "").font(.system(size: 11.5)).foregroundStyle(.tertiary) }
                        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                }
                if servers.isEmpty { Text("None. Add servers in Settings › MCP (project scope).").font(.system(size: 12.5)).foregroundStyle(.secondary) }
            } else { ProgressView().controlSize(.small) }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews { let sz = s.sizeThatFits(.unspecified); if x + sz.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }; x += sz.width + spacing; row = max(row, sz.height) }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews { let sz = s.sizeThatFits(.unspecified); if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }; s.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += sz.width + spacing; row = max(row, sz.height) }
    }
}
