import SwiftUI
import AppKit
import UserNotifications
import PiKit

enum AppSheet: Identifiable, Hashable {
    case projectSettings(String)
    case tags
    case automations
    case sessionTree(String)
    case systemPrompt(String)
    var id: String { switch self { case .projectSettings(let k): return "p" + k; case .tags: return "tags"; case .automations: return "auto"; case .sessionTree(let i): return "tree" + i; case .systemPrompt(let i): return "sp" + i } }
}

enum FilePlacement: String { case panel, sidebar }

@MainActor
@Observable
final class UIState {
    weak var model: AppModel?
    var lightbox: LightboxItem?
    var mentionRequest: String?
    var filePlacement: FilePlacement = FilePlacement(rawValue: UserDefaults.standard.string(forKey: "filePlacement") ?? "") ?? .panel {
        didSet { UserDefaults.standard.set(filePlacement.rawValue, forKey: "filePlacement"); if filePlacement == .sidebar, model?.workspace.tab == .files { model?.workspace.tab = .review } }
    }
    var filesSectionHeight: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "filesSectionHeight"); return v > 0 ? CGFloat(v) : 280
    }() { didSet { UserDefaults.standard.set(Double(filesSectionHeight), forKey: "filesSectionHeight") } }
    var filesSectionCollapsed: Bool = UserDefaults.standard.bool(forKey: "filesSectionCollapsed") {
        didSet { UserDefaults.standard.set(filesSectionCollapsed, forKey: "filesSectionCollapsed") }
    }
    var activeSheet: AppSheet?

    func openFile(_ path: String, line: Int? = nil) {
        model?.workspace.open(path, line: line)
        withAnimation(.snappy(duration: 0.22)) { rightPanelVisible = true }
    }
    func openDirectory(_ path: String) {
        guard let ws = model?.workspace else { return }
        ws.expanded.insert(path); Task { await ws.loadDir(path) }
        if filePlacement == .panel { showPanel(.files) } else { filesSectionCollapsed = false }
    }
    func showPanel(_ tab: PanelTab) {
        model?.workspace.tab = tab
        withAnimation(.snappy(duration: 0.22)) { rightPanelVisible = true }
    }
    func attachMention(_ path: String) {
        var p = path
        if let cwd = model?.workspace.cwd, p.hasPrefix(cwd + "/") { p = String(p.dropFirst(cwd.count + 1)) }
        mentionRequest = p
        focusComposer += 1
    }
    var sidebarVisible = true
    var sidebarWidth: CGFloat = 280
    var rightPanelVisible = false
    var rightPanelWidth: CGFloat = 460
    var searchOpen = false
    var focusComposer = 0
    var enterToSend: Bool = UserDefaults.standard.object(forKey: "enterToSend") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enterToSend, forKey: "enterToSend") }
    }
    var soundEnabled: Bool = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    var appearance: String = UserDefaults.standard.string(forKey: "appearance") ?? "system" {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
    }
    var colorScheme: ColorScheme? {
        switch appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.shutdown() }
    }
}

@main
struct PiNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var ui = UIState()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("Pi") {
            RootView()
                .environment(model)
                .environment(ui)
                .preferredColorScheme(ui.colorScheme)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    ui.model = model
                    delegate.model = model
                    model.start(mode: Self.connectionMode(), serverOverride: UserDefaults.standard.string(forKey: "serverDirectory"))
                    Notifier.shared.setup(model: model, ui: ui)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { AppCommands(model: model, ui: ui) }

        Settings {
            SettingsView()
                .environment(model)
                .environment(ui)
                .preferredColorScheme(ui.colorScheme)
        }
    }

    static func connectionMode() -> ConnectionMode {
        let d = UserDefaults.standard
        if d.string(forKey: "connectionMode") == "remote", let s = d.string(forKey: "remoteURL"), let u = URL(string: s) {
            return .remote(url: u, password: d.string(forKey: "remotePassword"))
        }
        return .embedded
    }
}

struct AppCommands: Commands {
    let model: AppModel
    let ui: UIState
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Thread") { model.startNewThread(); ui.focusComposer += 1 }.keyboardShortcut("n")
        }
        CommandGroup(after: .textEditing) {
            Button("Search Threads") { ui.searchOpen = true }.keyboardShortcut("k")
        }
        CommandGroup(replacing: .sidebar) {
            Button(ui.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { withAnimation(.snappy(duration: 0.22)) { ui.sidebarVisible.toggle() } }.keyboardShortcut("b")
            Button(ui.rightPanelVisible ? "Hide Side Panel" : "Show Side Panel") { withAnimation(.snappy(duration: 0.22)) { ui.rightPanelVisible.toggle() } }.keyboardShortcut("b", modifiers: [.command, .option])
        }
        CommandMenu("Thread") {
            Button("Focus Composer") { ui.focusComposer += 1 }.keyboardShortcut("l")
            Button("Stop") { Task { await model.currentStore?.abort() } }.keyboardShortcut(".")
        }
    }
}

/// Completion sound + system notification when a run ends.
@MainActor
final class Notifier {
    static let shared = Notifier()
    func setup(model: AppModel, ui: UIState) {
        let canNotify = Bundle.main.bundleIdentifier != nil
        if canNotify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
        model.onRunFinished = { store, aborted in
            guard !aborted else { return }
            if ui.soundEnabled { NSSound(named: "Glass")?.play() }
            guard canNotify, ui.notificationsEnabled, !NSApp.isActive || model.selection != .thread(store.sessionId) else { return }
            let c = UNMutableNotificationContent()
            c.title = store.info?.title ?? "Pi"
            c.body = "Task finished"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }
}
