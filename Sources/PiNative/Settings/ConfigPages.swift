import SwiftUI
import PiKit

/// Generic async loader for a settings page.
@MainActor @Observable
final class PageLoader {
    var data: JSON?
    var error: String?
    var loading = false
    func load(_ client: APIClient?, _ path: String, query: [String: String] = [:]) async {
        guard let client else { return }
        loading = true; defer { loading = false }
        do { data = try await client.get(path, query: query); error = nil } catch { self.error = error.localizedDescription }
    }
}

@MainActor private func send(_ model: AppModel, _ method: String, _ path: String, _ body: [String: Any]) async -> String? {
    guard let c = model.client else { return "Not connected" }
    do { _ = try await c.send(method, path, body: body); return nil } catch { return error.localizedDescription }
}

// MARK: - Models

struct ModelsSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var enabled = PageLoader()
    @State private var auth = PageLoader()
    @State private var error: String?
    @State private var keyFor: String?
    @State private var keyText = ""
    @State private var query = ""
    @State private var login: LoginFlow?
    @State private var showAllProviders = false

    var body: some View {
        apiErrorBanner(error)
        SettingsCard(title: "Defaults for new threads") {
            SettingsRow(title: "Model") {
                Menu {
                    ForEach(model.catalog.models) { m in Button("\(m.name)  ·  \(m.provider)") { setDefault(provider: m.provider, modelId: m.modelId) } }
                } label: { Text(model.catalog.info(for: model.catalog.defaultModel)?.name ?? "Choose…").lineLimit(1) }.menuStyle(.borderlessButton).fixedSize()
            }
            SettingsRow(title: "Reasoning effort", divider: false) {
                let levels = model.catalog.levels(for: model.catalog.defaultModel)
                Menu {
                    ForEach(levels, id: \.self) { l in Button(l.capitalized) { Task { error = await send(model, "PUT", "/api/models/default", ["thinkingLevel": l, "cwd": model.workspace.cwd ?? model.homeDirectory]); await model.loadModels(cwd: nil) } } }
                } label: { Text((model.catalog.defaultThinking ?? levels.first ?? "—").capitalized) }.menuStyle(.borderlessButton).fixedSize().disabled(levels.isEmpty)
            }
        }
        SettingsCard(title: "Provider accounts", footer: "Credentials are stored by pi in ~/.pi/agent/auth.json.") {
            let providers = (auth.data?["providers"]?.array ?? [])
            ForEach(Array(providers.enumerated()), id: \.offset) { i, p in
                let id = p["id"]?.string ?? ""
                SettingsRow(title: p["name"]?.string ?? id, subtitle: (p["loggedIn"]?.bool ?? false) ? "Signed in" : nil, divider: i < providers.count - 1) {
                    HStack(spacing: 8) {
                        if p["loggedIn"]?.bool == true {
                            Button("Sign out") { Task { error = await send(model, "POST", "/api/auth/logout/\(id)", [:]); await auth.load(model.client, "/api/auth/providers") } }
                        } else {
                            if p["supportsApiKey"]?.bool == true { Button("API key…") { keyFor = id; keyText = "" } }
                            if (auth.data?["oauthProviders"]?.array ?? []).contains(where: { $0["id"]?.string == id }) || p["supportsApiKey"]?.bool != true {
                                Button("Sign in") { login = LoginFlow(provider: id, name: p["name"]?.string ?? id) }
                            }
                        }
                    }.controlSize(.small)
                }
            }
        }
        SettingsCard(title: "Models in the picker", footer: "Turn off models you never use to keep the model menu short.") {
            if let providers = enabled.data?["providers"]?.array {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.tertiary); TextField("Filter models", text: $query).textFieldStyle(.plain) }.padding(10)
                Divider().opacity(0.7)
                ForEach(Array(providers.enumerated()), id: \.offset) { _, p in
                    let pid = p["id"]?.string ?? ""
                    let models = (p["models"]?.array ?? []).filter { query.isEmpty || ($0["name"]?.string ?? "").localizedCaseInsensitiveContains(query) || pid.localizedCaseInsensitiveContains(query) }
                    if !models.isEmpty {
                        HStack {
                            Text(p["name"]?.string ?? pid).font(.system(size: 12.5, weight: .semibold))
                            Text("\(p["enabledCount"]?.int ?? 0)/\((p["models"]?.array ?? []).count)").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                            Spacer()
                            Button("All") { Task { error = await send(model, "PUT", "/api/models/enabled", ["op": "provider", "provider": pid, "enabled": true]); await reloadEnabled() } }.controlSize(.small)
                            Button("None") { Task { error = await send(model, "PUT", "/api/models/enabled", ["op": "provider", "provider": pid, "enabled": false]); await reloadEnabled() } }.controlSize(.small)
                        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                        ForEach(Array(models.enumerated()), id: \.offset) { _, m in
                            let ref = m["ref"]?.string ?? ""
                            SettingsRow(title: m["name"]?.string ?? ref, divider: false) {
                                Toggle("", isOn: Binding(get: { m["enabled"]?.bool ?? false }, set: { v in Task { error = await send(model, "PUT", "/api/models/enabled", ["op": "models", "refs": [ref], "enabled": v]); await reloadEnabled() } })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                            }.padding(.vertical, -4)
                        }
                    }
                }
            } else { ProgressView().controlSize(.small).padding(20).frame(maxWidth: .infinity) }
        }
        SettingsCard(title: "Custom providers") {
            SettingsRow(title: "models.json", subtitle: "Add OpenAI-compatible endpoints and custom models.", divider: false) {
                Button("Open in editor") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.pi/agent/models.json")) }.controlSize(.small)
            }
        }
        .task { await enabled.load(model.client, "/api/models/enabled"); await auth.load(model.client, "/api/auth/providers") }
        .sheet(item: Binding(get: { keyFor.map { Wrapper(id: $0) } }, set: { if $0 == nil { keyFor = nil } })) { w in
            VStack(alignment: .leading, spacing: 12) {
                Text("API key for \(w.id)").font(.headline)
                SecureField("sk-…", text: $keyText).textFieldStyle(.roundedBorder)
                HStack { Spacer(); Button("Cancel") { keyFor = nil }; Button("Save") { Task { error = await send(model, "POST", "/api/auth/api-key/\(w.id)", ["apiKey": keyText]); keyFor = nil; await auth.load(model.client, "/api/auth/providers"); await model.loadModels(cwd: nil) } }.buttonStyle(.borderedProminent).disabled(keyText.isEmpty) }
            }.padding(20).frame(width: 380)
        }
        .sheet(item: $login) { f in LoginSheet(flow: f) { await auth.load(model.client, "/api/auth/providers"); await model.loadModels(cwd: nil) } }
    }

    struct Wrapper: Identifiable { let id: String }
    private func reloadEnabled() async { await enabled.load(model.client, "/api/models/enabled"); await model.loadModels(cwd: nil) }
    private func setDefault(provider: String, modelId: String) {
        Task { error = await send(model, "PUT", "/api/models/default", ["provider": provider, "modelId": modelId, "cwd": model.workspace.cwd ?? model.homeDirectory]); await model.loadModels(cwd: nil) }
    }
}

struct LoginFlow: Identifiable { let id = UUID(); let provider: String; let name: String }

/// OAuth / device-code sign-in driven by the server's SSE endpoint.
struct LoginSheet: View {
    let flow: LoginFlow
    let done: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Starting…"
    @State private var url: URL?
    @State private var userCode: String?
    @State private var prompt: String?
    @State private var input = ""
    @State private var finished = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to \(flow.name)").font(.headline)
            Text(status).font(.system(size: 13)).foregroundStyle(failed ? Theme.removed : .secondary)
            if let userCode { Text(userCode).font(.system(size: 26, weight: .semibold, design: .monospaced)).textSelection(.enabled) }
            if let url { Button("Open browser") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent) }
            if let prompt {
                Text(prompt).font(.system(size: 12.5))
                HStack { TextField("Paste redirect URL or code", text: $input).textFieldStyle(.roundedBorder); Button("Submit") { Task { _ = try? await model.client?.post("/api/auth/login/\(flow.provider)", body: ["code": input, "value": input]); self.prompt = nil } } }
            }
            HStack { Spacer(); Button(finished ? "Done" : "Cancel") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 440)
        .task {
            guard let c = model.client else { return }
            do {
                for try await e in c.events("/api/auth/login/\(flow.provider)") {
                    switch e["type"]?.string {
                    case "auth": url = e["url"]?.string.flatMap(URL.init(string:)); status = e["instructions"]?.string ?? "Complete the sign-in in your browser."; if let u = url { NSWorkspace.shared.open(u) }
                    case "device_code": userCode = e["userCode"]?.string; url = e["verificationUri"]?.string.flatMap(URL.init(string:)); status = "Enter this code at the verification page."
                    case "progress": status = e["message"]?.string ?? status
                    case "prompt_request": prompt = e["message"]?.string ?? e["prompt"]?.string ?? "Enter a value"
                    case "success": status = "Signed in."; finished = true; await done()
                    case "error": status = e["message"]?.string ?? "Sign-in failed."; failed = true
                    case "cancelled": status = "Cancelled."
                    default: break
                    }
                }
            } catch { if !finished { status = error.localizedDescription; failed = true } }
        }
    }
}

// MARK: - Skills

struct SkillsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var loader = PageLoader()
    @State private var query = ""
    @State private var searchQ = ""
    @State private var results: [(String, String, String)] = []
    @State private var searching = false
    @State private var installing: String?
    @State private var error: String?

    var body: some View {
        apiErrorBanner(error ?? loader.error)
        let skills = (loader.data?["skills"]?.array ?? []).filter { query.isEmpty || ($0["name"]?.string ?? "").localizedCaseInsensitiveContains(query) || ($0["description"]?.string ?? "").localizedCaseInsensitiveContains(query) }
        SettingsCard(title: "Installed (\(loader.data?["skills"]?.array?.count ?? 0))", footer: "Skills the model can load on demand. Turning one off hides it from the model; you can still invoke it with /skill:name.") {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.tertiary); TextField("Filter", text: $query).textFieldStyle(.plain)
                Spacer(); Button("Disable all") { setAll(false) }.controlSize(.small); Button("Enable all") { setAll(true) }.controlSize(.small) }.padding(10)
            Divider().opacity(0.7)
            ForEach(Array(skills.enumerated()), id: \.offset) { i, s in
                SettingsRow(title: s["name"]?.string ?? "", subtitle: s["description"]?.string.map { String($0.prefix(160)) }, divider: i < skills.count - 1) {
                    HStack(spacing: 8) {
                        Text(s["sourceInfo"]?["scope"]?.string ?? "").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        Toggle("", isOn: Binding(get: { !(s["disableModelInvocation"]?.bool ?? false) }, set: { on in Task { await toggle(s["filePath"]?.string ?? "", on) } })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }.contextMenu { Button("Reveal in Finder") { if let p = s["filePath"]?.string { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } } }
            }
        }
        SettingsCard(title: "Find skills on skills.sh") {
            HStack { TextField("Search skills (e.g. pdf, react, docx)", text: $searchQ).textFieldStyle(.roundedBorder).onSubmit { Task { await search() } }; Button("Search") { Task { await search() } }.disabled(searchQ.isEmpty) }.padding(10)
            if searching { ProgressView().controlSize(.small).padding(10) }
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                Divider().opacity(0.7)
                SettingsRow(title: r.0, subtitle: r.1, divider: false) {
                    Button(installing == r.0 ? "Installing…" : "Install") { Task { await install(r.0) } }.controlSize(.small).disabled(installing != nil)
                }
            }
        }
        .task { await load() }
    }

    private func load() async { await loader.load(model.client, "/api/skills", query: ["cwd": model.workspace.cwd ?? model.homeDirectory]) }
    private func toggle(_ path: String, _ on: Bool) async { error = await send(model, "PATCH", "/api/skills", ["filePath": path, "disableModelInvocation": !on]); await load() }
    private func setAll(_ on: Bool) {
        let paths = (loader.data?["skills"]?.array ?? []).compactMap { $0["filePath"]?.string }
        Task { error = await send(model, "PATCH", "/api/skills", ["filePaths": paths, "disableModelInvocation": !on]); await load() }
    }
    private func search() async {
        searching = true; defer { searching = false }
        guard let r = try? await model.client?.post("/api/skills/search", body: ["query": searchQ]) else { return }
        results = (r["results"]?.array ?? []).map { ($0["package"]?.string ?? "", $0["installs"]?.string ?? "", $0["url"]?.string ?? "") }
    }
    private func install(_ pkg: String) async {
        installing = pkg; defer { installing = nil }
        error = await send(model, "POST", "/api/skills/install", ["package": pkg, "scope": "global"]); await load()
    }
}

// MARK: - Agents

struct AgentsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var settings = PageLoader()
    @State private var profiles = PageLoader()
    @State private var error: String?
    @State private var concurrent = 10.0

    var body: some View {
        apiErrorBanner(error ?? settings.error)
        SettingsCard(title: "Built-in subagents", footer: "Lets the main agent delegate work to focused child agents (explore, general-purpose…).") {
            SettingsRow(title: "Enable subagent tool") {
                Toggle("", isOn: Binding(get: { settings.data?["enabled"]?.bool ?? false }, set: { v in Task { error = await send(model, "PUT", "/api/subagents/settings", ["enabled": v]); await reload() } })).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Max concurrent subagents", subtitle: "\(Int(concurrent))", divider: false) {
                Slider(value: $concurrent, in: 1...32, step: 1) { editing in if !editing { Task { error = await send(model, "PUT", "/api/subagents/settings", ["maxConcurrent": Int(concurrent)]) } } }.frame(width: 180)
            }
        }
        SettingsCard(title: "Profiles") {
            let list = profiles.data?["profiles"]?.array ?? []
            ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                SettingsRow(title: p["displayName"]?.string ?? p["name"]?.string ?? "", subtitle: p["description"]?.string, divider: i < list.count - 1) {
                    HStack(spacing: 8) {
                        Text(p["scope"]?.string ?? "").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        Text((p["tools"]?.array ?? []).compactMap(\.string).prefix(4).joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).frame(maxWidth: 160)
                    }
                }
            }
            if list.isEmpty { Text("No profiles").foregroundStyle(.secondary).padding(14) }
        }
        .task { await reload(); await profiles.load(model.client, "/api/subagents/profiles", query: ["cwd": model.workspace.cwd ?? model.homeDirectory]) }
    }
    private func reload() async { await settings.load(model.client, "/api/subagents/settings"); concurrent = Double(settings.data?["maxConcurrent"]?.int ?? 10) }
}

// MARK: - Plugins

struct PluginsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var loader = PageLoader()
    @State private var source = ""
    @State private var busy: String?
    @State private var error: String?
    private var cwd: String { model.workspace.cwd ?? model.homeDirectory }

    var body: some View {
        apiErrorBanner(error ?? loader.error)
        SettingsCard(title: "Install a package", footer: "npm:name, git:github.com/user/repo, or a local path. Packages can bundle extensions, skills, prompts and themes.") {
            HStack { TextField("npm:package-name", text: $source).textFieldStyle(.roundedBorder).onSubmit { Task { await act("install", source) } }
                Button("Install") { Task { await act("install", source) } }.disabled(source.isEmpty || busy != nil) }.padding(10)
        }
        SettingsCard(title: "Installed packages") {
            let pkgs = loader.data?["packages"]?.array ?? []
            ForEach(Array(pkgs.enumerated()), id: \.offset) { i, p in
                let src = p["source"]?.string ?? ""
                let disabled = p["disabled"]?.bool ?? false
                SettingsRow(title: p["packageName"]?.string ?? src,
                            subtitle: [p["version"]?.string.map { "v\($0)" }, p["scope"]?.string, p["description"]?.string.map { String($0.prefix(110)) }].compactMap { $0 }.joined(separator: " · "),
                            divider: i < pkgs.count - 1) {
                    HStack(spacing: 8) {
                        if busy == src { ProgressView().controlSize(.small) }
                        Menu {
                            Button("Update") { Task { await act("update", src, scope: p["scope"]?.string) } }
                            Button("Remove", role: .destructive) { Task { await act("remove", src, scope: p["scope"]?.string) } }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                        Toggle("", isOn: Binding(get: { !disabled }, set: { on in Task { await act(on ? "enable" : "disable", src, scope: p["scope"]?.string) } })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }
            }
            if pkgs.isEmpty && !loader.loading { Text("No packages").foregroundStyle(.secondary).padding(14) }
        }
        Text("Changes apply to new sessions.").font(.system(size: 11.5)).foregroundStyle(.tertiary)
        .task { await loader.load(model.client, "/api/plugins", query: ["cwd": cwd]) }
    }

    private func act(_ action: String, _ src: String, scope: String? = nil) async {
        busy = src; defer { busy = nil }
        var body: [String: Any] = ["action": action, "source": src, "cwd": cwd]
        if let scope { body["scope"] = scope }
        error = await send(model, "POST", "/api/plugins", body)
        if action == "install", error == nil { source = "" }
        await loader.load(model.client, "/api/plugins", query: ["cwd": cwd])
    }
}

// MARK: - MCP

struct MCPSettings: View {
    @Environment(AppModel.self) private var model
    @State private var loader = PageLoader()
    @State private var error: String?
    @State private var addText = ""
    @State private var addScope = "global"
    @State private var showAdd = false
    private var cwd: String { model.workspace.cwd ?? model.homeDirectory }

    var body: some View {
        apiErrorBanner(error ?? loader.error)
        let mcp = loader.data?["mcp"]
        if let mcp, mcp["available"]?.bool == false {
            SettingsCard(title: "MCP") {
                SettingsRow(title: "Built-in MCP is off", subtitle: mcp["error"]?.string ?? "Another extension (for example pi-mcp-adapter) may be providing MCP.", divider: false) {
                    Button("Open mcp.json") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.pi/agent/mcp.json")) }.controlSize(.small)
                }
            }
        }
        let servers = loader.data?["servers"]?.array ?? []
        SettingsCard(title: "Servers (\(servers.count))", footer: "Global servers live in ~/.pi/agent/mcp.json. Project servers in <project>/.pi/mcp.json need project trust.") {
            ForEach(Array(servers.enumerated()), id: \.offset) { i, s in
                let name = s["name"]?.string ?? "", scope = s["scope"]?.string ?? "global"
                SettingsRow(title: name, subtitle: [scope, s["transport"]?.string, s["command"]?.string ?? s["url"]?.string, s["invalidError"]?.string].compactMap { $0 }.joined(separator: " · "), divider: i < servers.count - 1) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("Test") { Task { await test(scope, name) } }
                            Button("Remove", role: .destructive) { Task { error = await send(model, "POST", "/api/mcp", ["action": "remove", "scope": scope, "name": name, "cwd": cwd]); await load() } }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                        Toggle("", isOn: Binding(get: { s["enabled"]?.bool ?? true }, set: { on in Task { error = await send(model, "POST", "/api/mcp", ["action": on ? "enable" : "disable", "scope": scope, "name": name, "cwd": cwd]); await load() } })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }
            }
            if servers.isEmpty { Text("No servers configured").foregroundStyle(.secondary).padding(14) }
        }
        HStack {
            Button { showAdd.toggle() } label: { Label("Add server", systemImage: "plus") }
            Button("Open mcp.json") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.pi/agent/mcp.json")) }
        }
        if showAdd {
            SettingsCard(title: "Add server", footer: "Paste a JSON snippet, a `claude mcp add …` command, or a server URL.") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $addText).font(Theme.mono(12)).frame(height: 110).scrollContentBackground(.hidden).padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Theme.background))
                    HStack {
                        Picker("", selection: $addScope) { Text("Global").tag("global"); Text("Project").tag("project") }.pickerStyle(.segmented).frame(width: 160).labelsHidden()
                        Spacer(); Button("Add") { Task { error = await send(model, "POST", "/api/mcp", ["action": "add", "text": addText, "scope": addScope, "cwd": cwd]); if error == nil { addText = ""; showAdd = false }; await load() } }.buttonStyle(.borderedProminent).disabled(addText.isEmpty)
                    }
                }.padding(12)
            }
        }
        Color.clear.frame(height: 0).task { await load() }
    }

    private func load() async { await loader.load(model.client, "/api/mcp", query: ["cwd": cwd]) }
    private func test(_ scope: String, _ name: String) async {
        guard let c = model.client else { return }
        do { let r = try await c.post("/api/mcp/test", body: ["scope": scope, "name": name, "cwd": cwd]); model.toast = (r["ok"]?.bool ?? (r["status"]?.string == "connected")) ? "\(name): connected" : "\(name): \(r["error"]?.string ?? r["status"]?.string ?? "failed")" }
        catch { model.toast = error.localizedDescription }
    }
}

// MARK: - Tools

struct ToolsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var loader = PageLoader()
    @State private var error: String?
    var body: some View {
        apiErrorBanner(error ?? loader.error)
        SettingsCard(title: "Code mode", footer: "Lets the model write a small script that calls several tools at once, saving round trips.") {
            SettingsRow(title: "Always enable Code mode") {
                Toggle("", isOn: Binding(get: { loader.data?["codemode"]?.string == "always" }, set: { v in Task { error = await send(model, "PUT", "/api/tools/settings", ["codemode": v ? "always" : "automatic"]); await loader.load(model.client, "/api/tools/settings") } })).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Hide other tools from the model", subtitle: "“Only”: the model calls tools through scripts.", divider: false) {
                Picker("", selection: Binding(get: { loader.data?["codemodeMode"]?["value"]?.string ?? "on" }, set: { v in Task { error = await send(model, "PUT", "/api/tools/settings", ["codemodeMode": v]); await loader.load(model.client, "/api/tools/settings") } })) { Text("Off").tag("on"); Text("Only").tag("only") }.pickerStyle(.segmented).frame(width: 130).labelsHidden()
            }
        }
        .task { await loader.load(model.client, "/api/tools/settings") }
    }
}
