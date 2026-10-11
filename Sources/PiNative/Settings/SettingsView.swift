import SwiftUI
import PiKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ConnectionSettings().tabItem { Label("Connection", systemImage: "network") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }.frame(width: 560, height: 420)
    }
}

struct GeneralSettings: View {
    @Environment(UIState.self) private var ui
    var body: some View {
        @Bindable var ui = ui
        Form {
            Picker("Appearance", selection: $ui.appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }.pickerStyle(.segmented)
            Picker("Send message with", selection: $ui.enterToSend) {
                Text("Return (⇧Return for new line)").tag(true); Text("⌘Return (Return for new line)").tag(false)
            }
            Toggle("Play a sound when a task finishes", isOn: $ui.soundEnabled)
            Toggle("Show a notification when a task finishes in the background", isOn: $ui.notificationsEnabled)
        }.formStyle(.grouped).padding()
    }
}

struct ConnectionSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("connectionMode") private var mode = "embedded"
    @AppStorage("serverDirectory") private var serverDir = ""
    @AppStorage("remoteURL") private var remoteURL = ""
    @AppStorage("remotePassword") private var remotePassword = ""
    var body: some View {
        Form {
            Picker("Server", selection: $mode) {
                Text("Built-in (starts automatically)").tag("embedded"); Text("Existing Pi Web server").tag("remote")
            }
            if mode == "embedded" {
                TextField("Server folder (optional)", text: $serverDir, prompt: Text("Auto-detect"))
                LabeledContent("Using") { Text(model.sidecar.serverDirectory?.path ?? "—").foregroundStyle(.secondary).textSelection(.enabled) }
                Button("Open Server Log") { NSWorkspace.shared.open(model.sidecar.logURL) }
            } else {
                TextField("URL", text: $remoteURL, prompt: Text("http://127.0.0.1:30141"))
                SecureField("Password", text: $remotePassword)
            }
            Button("Apply & Reconnect") { model.restart(mode: PiNativeApp.connectionMode(), serverOverride: serverDir.isEmpty ? nil : serverDir) }
        }.formStyle(.grouped).padding()
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle").font(.system(size: 34, weight: .light))
            Text("TAKT Pi GUI").font(.title2.weight(.semibold))
            Text("Native macOS client for pi").foregroundStyle(.secondary)
            Text("Backend: pi-web sidecar · UI: SwiftUI").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
