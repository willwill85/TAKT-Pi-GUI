import SwiftUI
import AppKit
import UserNotifications
import PiKit

enum RightTab: String, CaseIterable { case review = "Review", files = "Files", terminal = "Terminal" }

@Observable
final class UIState {
    var rightTab: RightTab = .review
    var openFilePaths: [String] = []
    var selectedFile: String?
    func openFile(_ path: String) {
        if !openFilePaths.contains(path) { openFilePaths.append(path) }
        selectedFile = path
        withAnimation(.snappy(duration: 0.22)) { rightPanelVisible = true }
    }
    func closeFile(_ path: String) {
        openFilePaths.removeAll { $0 == path }
        if selectedFile == path { selectedFile = openFilePaths.last }
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
