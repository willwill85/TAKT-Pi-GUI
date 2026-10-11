import SwiftUI
import PiKit

private struct TreeNode: Identifiable {
    let id: String
    var depth: Int
    var role: String
    var preview: String
    var isLeaf: Bool
    var onActivePath: Bool
    var kind: String
}

/// The session as a branching tree: every user prompt, assistant reply and branch point.
struct SessionTreeSheet: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var nodes: [TreeNode] = []
    @State private var leaf: String?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Conversation tree").font(.system(size: 16, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(16)
            Divider()
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(nodes) { n in
                            HStack(spacing: 8) {
                                Color.clear.frame(width: CGFloat(min(n.depth, 12)) * 14)
                                Image(systemName: n.role == "user" ? "person.fill" : n.role == "assistant" ? "sparkle" : n.role == "toolResult" ? "wrench.and.screwdriver" : "circle.dotted").font(.system(size: 10.5)).frame(width: 14)
                                    .foregroundStyle(n.onActivePath ? Color.primary : Color.secondary)
                                Text(n.preview).font(.system(size: 12.5)).lineLimit(1).foregroundStyle(n.onActivePath ? Color.primary : Color.secondary)
                                Spacer()
                                if n.id == leaf { Text("current").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.primary) }
                            }
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 6).fill(n.id == leaf ? Color.accentColor.opacity(0.12) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { Task { await jump(n.id) } }
                            .help("Double-click to continue from here")
                        }
                    }.padding(10)
                }
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.removed).padding(10) }
            Text("Double-click a message to continue from that point (creates a new branch).").font(.system(size: 11.5)).foregroundStyle(.tertiary).padding(8)
        }
        .frame(width: 640, height: 520)
        .task { await load() }
    }

    private func load() async {
        guard let c = model.client, let d = try? await c.get("/api/sessions/\(sessionId)") else { loading = false; return }
        leaf = d["leafId"]?.string
        // Ancestor chain of the current leaf.
        var parent: [String: String] = [:]
        func index(_ list: [JSON]) { for n in list { if let id = n["entry"]?["id"]?.string, let p = n["entry"]?["parentId"]?.string { parent[id] = p }; index(n["children"]?.array ?? []) } }
        index(d["tree"]?.array ?? [])
        var active = Set<String>(); var cur = leaf
        while let c = cur { active.insert(c); cur = parent[c] }
        var out: [TreeNode] = []
        func walk(_ list: [JSON], depth: Int) {
            for n in list {
                let e = n["entry"] ?? .null
                let id = e["id"]?.string ?? UUID().uuidString
                let children = n["children"]?.array ?? []
                let type = e["type"]?.string ?? ""
                var role = type, preview = type
                if type == "message", let m = e["message"] {
                    role = m["role"]?.string ?? "message"
                    let msg = Message(json: m)
                    preview = msg.text.replacingOccurrences(of: "\n", with: " ")
                    if preview.isEmpty, let c = msg.toolCalls.first { preview = "\(c.name) …" }
                    if preview.isEmpty { preview = role }
                } else if type == "model_change" { preview = "Model → \(e["modelId"]?.string ?? "")" }
                else if type == "compaction" { preview = "Compaction" }
                out.append(TreeNode(id: id, depth: depth, role: role, preview: String(preview.prefix(120)), isLeaf: children.isEmpty, onActivePath: active.contains(id), kind: type))
                walk(children, depth: children.count > 1 ? depth + 1 : depth)
            }
        }
        // Single-child chains stay flat; branches indent.
        func walkRoot(_ list: [JSON]) { walk(list, depth: 0) }
        walkRoot(d["tree"]?.array ?? [])
        nodes = out.filter { $0.kind == "message" || $0.kind == "compaction" || $0.kind == "model_change" }
        loading = false
    }

    private func jump(_ id: String) async {
        guard let store = model.store(for: sessionId) else { return }
        if store.isRunning { error = "Wait for the current run to finish."; return }
        do { try await model.client?.command(sessionId, ["type": "navigate_tree", "targetId": id]); await store.load(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct SystemPromptSheet: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String?
    @State private var tools: [JSON] = []
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) { Text("System prompt").tag(0); Text("Tools (\(tools.count))").tag(1) }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(14)
            Divider()
            if tab == 0 {
                ScrollView { Text(prompt ?? "Loading…").font(Theme.mono(12)).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(tools.enumerated()), id: \.offset) { _, t in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t["name"]?.string ?? "").font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Text(t["description"]?.string ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                        }
                    }.padding(14)
                }
            }
        }
        .frame(width: 720, height: 560)
        .task {
            if let d = try? await model.client?.get("/api/agent/\(sessionId)") { prompt = d["state"]?["systemPrompt"]?.string ?? "" }
            if let d = try? await model.client?.command(sessionId, ["type": "get_tools"]) { tools = d["tools"]?.array ?? [] }
        }
    }
}
