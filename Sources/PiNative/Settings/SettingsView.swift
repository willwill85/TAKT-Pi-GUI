import SwiftUI
import PiKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", tags = "Tags", usage = "Usage", models = "Models", skills = "Skills", agents = "Agents", plugins = "Plugins", mcp = "MCP", tools = "Tools", connection = "Connection", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"; case .tags: return "tag"; case .usage: return "chart.bar"; case .models: return "cpu"; case .skills: return "sparkles"; case .agents: return "person.2"
        case .plugins: return "puzzlepiece"; case .mcp: return "server.rack"; case .tools: return "wrench.and.screwdriver"; case .connection: return "network"; case .about: return "info.circle"
        }
    }
}

/// App-wide settings only. Anything scoped to one project (tags, structure, trust, worktrees)
/// lives in the project's own settings sheet, reachable from the sidebar.
struct SettingsView: View {
    @State private var page: SettingsPage = .general
    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: Binding<SettingsPage?>(get: { page }, set: { if let v = $0 { page = v } })) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(page.rawValue).font(.system(size: 22, weight: .semibold))
                    switch page {
                    case .general: GeneralSettings()
                    case .tags: TagsSettings()
                    case .usage: UsageSettings()
                    case .models: ModelsSettings()
                    case .skills: SkillsSettings()
                    case .agents: AgentsSettings()
                    case .plugins: PluginsSettings()
                    case .mcp: MCPSettings()
                    case .tools: ToolsSettings()
                    case .connection: ConnectionSettings()
                    case .about: AboutSettings()
                    }
                }.padding(28).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .frame(width: 900, height: 620)
    }
}

// MARK: - Shared building blocks

struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(alignment: .leading, spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.separator))
            if let footer { Text(footer).font(.system(size: 11.5)).foregroundStyle(.tertiary).padding(.leading, 4) }
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var divider = true
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5))
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                trailing
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if divider { Divider().padding(.leading, 14).opacity(0.7) }
        }
    }
}

@MainActor
func apiErrorBanner(_ e: String?) -> some View {
    Group { if let e { BannerPill(icon: "exclamationmark.triangle.fill", text: e, tint: Theme.warning) } }
}

// MARK: - Tags

struct TagsSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tags").font(.system(size: 22, weight: .semibold))
            TagsManagerContent()
        }
    }
}

// MARK: - Pi version (periodic check + upgrade)

/// Settings › General: pi, remote-pi and pi-web, each with its installed and latest version and an Update button.
struct PiVersionCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        SettingsCard(title: "Updates", footer: "Checked at launch and every 6 hours. pi and remote-pi update from npm; pi-web merges upstream when your fork has no local changes. Running threads keep the old code until restarted.") {
            if model.updates.isEmpty {
                SettingsRow(title: "Checking…", subtitle: nil, divider: false) { EmptyView() }
            }
            ForEach(Array(model.updates.enumerated()), id: \.element.id) { i, u in
                SettingsRow(title: u.name,
                            subtitle: rowSubtitle(u),
                            divider: i < model.updates.count - 1 || model.piUpdateMessage != nil) {
                    HStack(spacing: 8) {
                        if let e = u.error { Text(e).font(.system(size: 11)).foregroundStyle(Theme.removed).lineLimit(1).frame(maxWidth: 180) }
                        if u.available {
                            Button(model.updatingIds.contains(u.id) ? "Updating…" : "Update") { Task { await model.applyUpdate(u.id) } }
                                .buttonStyle(.borderedProminent).controlSize(.small).disabled(model.updatingIds.contains(u.id))
                        } else {
                            Text("up to date").font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            HStack {
                Button(model.piChecking ? "Checking…" : "Check Now") { Task { await model.checkUpdates(force: true) } }
                    .controlSize(.small).disabled(model.piChecking)
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 8)
            if let m = model.piUpdateMessage {
                Text(m).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    private func rowSubtitle(_ u: UpdateItem) -> String {
        if u.available, let latest = u.latest { return "v\(u.current) → v\(latest)" + (u.detail.map { " · \($0)" } ?? "") }
        if let d = u.detail { return "v\(u.current) · \(d)" }
        return "v\(u.current)"
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var model
    @AppStorage("chatFontSize") private var chatFont = 14.0
    @AppStorage("chatWidth") private var chatWidth = 760.0
    var body: some View {
        @Bindable var ui = ui
        PiVersionCard()
        SettingsCard(title: "Appearance") {
            SettingsRow(title: "Theme") {
                Picker("", selection: $ui.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented).frame(width: 220).labelsHidden()
            }
            SettingsRow(title: "Chat text size", subtitle: "\(Int(chatFont)) pt") { Slider(value: $chatFont, in: 12...20, step: 1).frame(width: 180) }
            SettingsRow(title: "Chat width", subtitle: "\(Int(chatWidth)) pt", divider: false) { Slider(value: $chatWidth, in: 600...1100, step: 20).frame(width: 180) }
        }
        SettingsCard(title: "File browser", footer: "Choose where the project's files live: a tab in the side panel (default) or a section under the thread list.") {
            SettingsRow(title: "Show files", divider: false) {
                Picker("", selection: $ui.filePlacement) { Text("In side panel").tag(FilePlacement.panel); Text("Below threads").tag(FilePlacement.sidebar) }.pickerStyle(.segmented).frame(width: 240).labelsHidden()
            }
        }
        SettingsCard(title: "Composer") {
            SettingsRow(title: "Send message with") {
                Picker("", selection: $ui.enterToSend) { Text("Return").tag(true); Text("⌘Return").tag(false) }.pickerStyle(.segmented).frame(width: 180).labelsHidden()
            }
            SettingsRow(title: "Play a sound when a task finishes") { Toggle("", isOn: $ui.soundEnabled).toggleStyle(.switch).labelsHidden() }
            SettingsRow(title: "Notify when a background task finishes", divider: false) { Toggle("", isOn: $ui.notificationsEnabled).toggleStyle(.switch).labelsHidden() }
        }
        SettingsCard(title: "Remote Pi", footer: "Pair your phone with the remote-pi extension: open any thread and run /remote-pi.") {
            SettingsRow(title: "Supervisor", subtitle: RemotePiStatus.shared.online ? "Running" : "Not running", divider: false) {
                Circle().fill(RemotePiStatus.shared.online ? Color.green : Color.secondary.opacity(0.5)).frame(width: 9, height: 9)
            }
        }
    }
}

// MARK: - Connection / About

struct ConnectionSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("connectionMode") private var mode = "embedded"
    @AppStorage("serverDirectory") private var serverDir = ""
    @AppStorage("remoteURL") private var remoteURL = ""
    @AppStorage("remotePassword") private var remotePassword = ""
    var body: some View {
        SettingsCard(title: "Server", footer: "Pi Native talks to a pi-web compatible server. The built-in one starts automatically on a private port.") {
            SettingsRow(title: "Use", divider: mode == "embedded" || true) {
                Picker("", selection: $mode) { Text("Built-in").tag("embedded"); Text("Existing server").tag("remote") }.pickerStyle(.segmented).frame(width: 230).labelsHidden()
            }
            if mode == "embedded" {
                SettingsRow(title: "Server folder", subtitle: model.sidecar.serverDirectory?.path ?? "Auto-detect") { TextField("Auto", text: $serverDir).textFieldStyle(.roundedBorder).frame(width: 220) }
                SettingsRow(title: "Server log", divider: false) { Button("Open") { NSWorkspace.shared.open(model.sidecar.logURL) } }
            } else {
                SettingsRow(title: "URL") { TextField("http://127.0.0.1:30141", text: $remoteURL).textFieldStyle(.roundedBorder).frame(width: 240) }
                SettingsRow(title: "Password", divider: false) { SecureField("", text: $remotePassword).textFieldStyle(.roundedBorder).frame(width: 240) }
            }
        }
        Button("Apply & Reconnect") { model.restart(mode: PiNativeApp.connectionMode(), serverOverride: serverDir.isEmpty ? nil : serverDir) }.buttonStyle(.borderedProminent)
    }
}

import PiBrand
struct AboutSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                PiMark(size: 70)
            }.frame(width: 96, height: 96).shadow(radius: 8, y: 3)
            Text("TAKT Pi GUI").font(.title2.weight(.semibold))
            Text("Native macOS client for the pi coding agent").foregroundStyle(.secondary)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · pi-web \(model.appUpdate?.current ?? "—")").font(.caption).foregroundStyle(.tertiary)
            Link("github.com/willwill85/TAKT-Pi-GUI", destination: URL(string: "https://github.com/willwill85/TAKT-Pi-GUI")!).font(.caption)
        }.frame(maxWidth: .infinity).padding(.top, 20)
    }
}
