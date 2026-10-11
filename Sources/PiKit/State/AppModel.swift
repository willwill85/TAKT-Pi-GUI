import Foundation
import Observation

public enum Selection: Hashable, Sendable {
    case thread(String)
    case newThread
    case automations
}

public struct ModelCatalog: Sendable {
    public var models: [ModelInfo] = []
    public var defaultModel: ModelRef?
    public var defaultThinking: String?
    public init() {}
    public func info(for ref: ModelRef?) -> ModelInfo? {
        guard let ref else { return nil }
        return models.first { $0.provider == ref.provider && $0.modelId == ref.modelId }
    }
    public func levels(for ref: ModelRef?) -> [String] { info(for: ref)?.thinkingLevels ?? [] }
}

/// Root observable state: connection, sidebar data, selection, open sessions.
@MainActor
@Observable
public final class AppModel {
    public let sidecar = SidecarManager()
    public private(set) var client: APIClient?
    public private(set) var sessions: [SessionInfo] = []
    /// Slash commands available before any thread exists (skills, prompts, extensions). A live thread's own
    /// list, which also includes its session commands, takes over once one is open.
    public private(set) var slashCommands: [SlashCommand] = []
    public private(set) var ui = SessionUiState()
    public private(set) var running: Set<String> = []
    public private(set) var awaiting: Set<String> = []
    public private(set) var sidebar = SidebarModel()
    public private(set) var catalog = ModelCatalog()
    public private(set) var sessionsLoaded = false
    public var selection: Selection = .newThread
    public var newThreadCwd: String? { didSet { if selection == .newThread, oldValue != newThreadCwd { syncWorkspace() } } }
    public var newThreadModel: ModelRef?
    public var newThreadThinking: String?
    public var toast: String?
    public private(set) var namingNow: Set<String> = []
    public var unread: Set<String> = []
    public var homeDirectory = NSHomeDirectory()
    public let workspace = WorkspaceModel()
    public private(set) var tagState = TagState()
    public private(set) var appUpdate: (current: String, latest: String, available: Bool)?
    public private(set) var piVersion: String?
    public private(set) var accountUsage = AccountUsage()
    public private(set) var accountUsageLoading = false
    public private(set) var priceTiers = PriceTiers()
    public private(set) var piUpdate: (current: String, latest: String, available: Bool)?
    public private(set) var piChecking = false
    public private(set) var piUpgrading = false
    public var piUpdateMessage: String?
    private var piUpdateTask: Task<Void, Never>?

    /// Fired when any session finishes a run: (store, aborted).
    public var onRunFinished: ((SessionStore, Bool) -> Void)?

    private var stores: [String: SessionStore] = [:]
    private var pollTask: Task<Void, Never>?
    private var connected = false

    public init() {}

    // MARK: Startup

    public func start(mode: ConnectionMode = .embedded, serverOverride: String? = nil) {
        sidecar.start(mode: mode, serverOverride: serverOverride)
        Task { await waitForSidecar() }
    }

    public func restart(mode: ConnectionMode, serverOverride: String? = nil) {
        pollTask?.cancel(); client = nil; connected = false; stores = [:]; sessionsLoaded = false
        sidecar.restart(mode: mode, serverOverride: serverOverride)
        Task { await waitForSidecar() }
    }

    public func shutdown() { pollTask?.cancel(); sidecar.stop() }

    private func waitForSidecar() async {
        while true {
            if case .ready(let ep) = sidecar.state {
                if !connected || client?.endpoint != ep {
                    client = APIClient(endpoint: ep); connected = true
                    workspace.configure(client: client)
                    await bootstrap()
                }
            } else if connected { connected = false }
            if case .failed = sidecar.state, !connected { return }
            try? await Task.sleep(for: .milliseconds(400))
            if connected { return }
        }
    }

    private func bootstrap() async {
        if let h = try? await client?.get("/api/home"), let p = h["home"]?.string { homeDirectory = p }
        await refreshSessions()
        await refreshTags()
        sessionsLoaded = true
        Task { await checkUpdate() }
        startPiUpdateChecks()
        Task { await refreshAccountUsage() }
        if newThreadCwd == nil { newThreadCwd = sessions.first?.cwd ?? homeDirectory }
        syncWorkspace()
        await loadModels(cwd: newThreadCwd)
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var tick = 0
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                tick += 1
                await self.pollRunning(forceList: tick % 6 == 0)
            }
        }
    }

    // MARK: Sidebar data

    public func refreshSessions() async {
        guard let client else { return }
        // Header metadata first, so the sidebar paints immediately; it carries no names.
        async let list = try? client.get("/api/sessions", query: ["summary": "1"])
        async let uiJ = try? client.get("/api/sessions/ui-state")
        let (l, u) = await (list, uiJ)
        applySessionList(l)
        if let u, let st = u["state"] { ui = SessionUiState(json: st) }
        rebuildSidebar()
        // The full listing fills in names and first messages. Without it every unnamed session
        // stays "New thread" forever.
        if sessions.contains(where: \.detailsPending) {
            let full = try? await client.get("/api/sessions")
            applySessionList(full)
            rebuildSidebar()
        }
    }

    private func applySessionList(_ l: JSON?) {
        guard let l else { return }
        sessions = (l["sessions"]?.array ?? []).compactMap(SessionInfo.init(json:)).filter { !$0.transient || running.contains($0.id) }
        running = Set((l["runningSessionIds"]?.array ?? []).compactMap(\.string))
        awaiting = Set((l["awaitingInputSessionIds"]?.array ?? []).compactMap(\.string))
    }

    func rebuildSidebar() { sidebar = SidebarModel.build(sessions: sessions, ui: ui, running: running) }

    private func pollRunning(forceList: Bool) async {
        guard let client else { return }
        guard let r = try? await client.get("/api/agent/running") else { return }
        let nr = Set((r["runningSessionIds"]?.array ?? []).compactMap(\.string))
        let na = Set((r["awaitingInputSessionIds"]?.array ?? []).compactMap(\.string))
        let uiRev = r["sessionUiStateRevision"]?.int ?? ui.revision
        let finished = running.subtracting(nr)
        let changed = nr != running || na != awaiting
        running = nr; awaiting = na
        for id in finished where selection != .thread(id) { unread.insert(id) }
        if forceList || !finished.isEmpty || uiRev != ui.revision || changed && finished.isEmpty == false {
            await refreshSessions()
        } else if changed { rebuildSidebar() }
    }

    // MARK: Tags

    public func refreshTags() async {
        guard let client, let d = try? await client.get("/api/project-tags") else { return }
        tagState = TagState(json: d)
    }

    @discardableResult
    public func tagAction(_ body: [String: Any]) async -> String? {
        guard let client else { return "Not connected" }
        do { let d = try await client.post("/api/project-tags", body: body); tagState = TagState(json: d); return nil }
        catch { return error.localizedDescription }
    }

    public func toggleProjectTag(_ key: String, tag: String) async {
        var ids = tagState.projectAssignments[key] ?? []
        if let i = ids.firstIndex(of: tag) { ids.remove(at: i) } else { ids.append(tag) }
        tagState.projectAssignments[key] = ids
        await tagAction(["action": "assign", "projectKey": key, "tagIds": ids])
    }

    public func toggleSessionTag(_ id: String, tag: String) async {
        var ids = tagState.sessionAssignments[id] ?? []
        if let i = ids.firstIndex(of: tag) { ids.remove(at: i) } else { ids.append(tag) }
        tagState.sessionAssignments[id] = ids
        await tagAction(["action": "assign-session", "sessionId": id, "tagIds": ids])
    }

    // MARK: Updates

    public func checkUpdate() async {
        guard let client, let d = try? await client.get("/api/app-update") else { return }
        appUpdate = (d["currentVersion"]?.string ?? "", d["latestVersion"]?.string ?? "", d["updateAvailable"]?.bool ?? false)
    }

    /// Checks pi's own version now and every 6 hours while the app runs.
    public func startPiUpdateChecks() {
        piUpdateTask?.cancel()
        piUpdateTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.checkPiUpdate(force: false)
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    public func checkPiUpdate(force: Bool) async {
        guard let client else { return }
        piChecking = true; defer { piChecking = false }
        do {
            let d = try await client.get("/api/pi-update", query: force ? ["force": "1"] : [:])
            let cur = d["currentVersion"]?.string ?? ""
            piUpdate = (cur, d["latestVersion"]?.string ?? "", d["updateAvailable"]?.bool ?? false)
            if !cur.isEmpty { piVersion = cur }
            if force { piUpdateMessage = (piUpdate?.available == true) ? nil : "Pi is up to date." }
        } catch {
            if force { piUpdateMessage = "Update check failed: \(error.localizedDescription)" }
        }
    }

    public func upgradePi() async {
        guard let client, !piUpgrading else { return }
        piUpgrading = true; piUpdateMessage = nil; defer { piUpgrading = false }
        do {
            let d = try await client.post("/api/pi-update")
            let v = d["installedVersion"]?.string ?? ""
            piUpdateMessage = "Upgraded to \(v). Restart the app so new threads use it."
            await checkPiUpdate(force: true)
            piUpdateMessage = "Upgraded to \(v). Restart the app so new threads use it."
        } catch {
            piUpdateMessage = "Upgrade failed: \(error.localizedDescription)"
        }
    }

    // MARK: Usage & prices

    /// Balances and 24h / 30d spend, exactly as each provider reports them.
    public func refreshAccountUsage(force: Bool = false) async {
        guard let client else { return }
        accountUsageLoading = true; defer { accountUsageLoading = false }
        if let d = try? await client.get("/api/account-usage", query: force ? ["force": "1"] : [:]) { accountUsage = AccountUsage(json: d) }
    }

    public func refreshPrices() async {
        guard let client, let d = try? await client.get("/api/model-prices") else { return }
        var prices: [String: ModelPrice] = [:]
        for (k, v) in d["prices"]?.object ?? [:] {
            if let i = v["input"]?.double, let o = v["output"]?.double { prices[k] = ModelPrice(input: i, output: o) }
        }
        priceTiers = PriceTiers(prices: prices, among: catalog.models.map(\.id))
    }

    // MARK: Models

    public func loadModels(cwd: String?) async {
        guard let client else { return }
        var q: [String: String] = [:]
        if let cwd { q["cwd"] = cwd }
        guard let d = try? await client.get("/api/models", query: q) else { return }
        var c = ModelCatalog()
        let levels = d["thinkingLevels"]?.object ?? [:]
        c.models = (d["modelList"]?.array ?? []).compactMap { j in
            guard let id = j["id"]?.string, let p = j["provider"]?.string else { return nil }
            return ModelInfo(
                modelId: id, name: j["name"]?.string ?? id, provider: p,
                supportsImages: (j["input"]?.array ?? []).contains { $0.string == "image" },
                thinkingLevels: (levels["\(p):\(id)"]?.array ?? []).compactMap(\.string))
        }
        if let dm = d["defaultModel"], let p = dm["provider"]?.string, let id = dm["modelId"]?.string { c.defaultModel = ModelRef(provider: p, modelId: id) }
        c.defaultThinking = d["defaultThinkingLevel"]?.string
        catalog = c
        priceTiers = PriceTiers(prices: priceTiers.prices, among: c.models.map(\.id))
        Task { await refreshPrices() }
        if newThreadModel == nil { newThreadModel = c.defaultModel }
        if newThreadThinking == nil { newThreadThinking = c.defaultThinking ?? c.levels(for: c.defaultModel).first }
    }

    // MARK: Sessions

    public func store(for id: String) -> SessionStore? {
        guard let client else { return nil }
        if let s = stores[id] { return s }
        let s = SessionStore(sessionId: id, client: client, info: sessions.first { $0.id == id })
        s.onRunFinished = { [weak self, weak s] aborted in
            guard let self, let s else { return }
            self.onRunFinished?(s, aborted)
            Task { await self.refreshSessions() }
        }
        stores[id] = s
        return s
    }

    public var currentStore: SessionStore? {
        if case .thread(let id) = selection { return store(for: id) } else { return nil }
    }

    public var files: FileService? { workspace.fileService }

    func syncWorkspace() {
        switch selection {
        case .thread(let id): workspace.setCwd(sessions.first { $0.id == id }?.cwd ?? stores[id]?.info?.cwd)
        case .newThread: workspace.setCwd(newThreadCwd)
        case .automations: break
        }
        if case .thread(let id) = selection { workspace.sessionId = id } else { workspace.sessionId = nil }
    }

    public func select(_ id: String) {
        if case .thread(let cur) = selection, cur != id, let old = stores[cur], !old.isRunning { old.disconnect() }
        selection = .thread(id)
        unread.remove(id)
        guard let s = store(for: id) else { return }
        if let cwd = s.info?.cwd ?? sessions.first(where: { $0.id == id })?.cwd { newThreadCwd = cwd }
        syncWorkspace()
        Task {
            await s.load()
            s.connect()
            await s.refreshState()
            await s.loadCommands()
            if !s.commands.isEmpty { slashCommands = s.commands }
        }
    }

    /// Makes `root` the folder the side panel works on (when no thread of it is open).
    public func startNewThreadContextIfNeeded(_ root: String) {
        if case .thread(let id) = selection, sessions.first(where: { $0.id == id })?.projectRoot == root { return }
        newThreadCwd = root
        if selection != .newThread { workspace.setCwd(root) }
    }

    public func showAutomations() { selection = .automations }

    public func startNewThread(cwd: String? = nil) {
        if let cwd { newThreadCwd = cwd }
        if case .thread(let cur) = selection, let old = stores[cur], !old.isRunning { old.disconnect() }
        selection = .newThread
        syncWorkspace()
        Task { await loadModels(cwd: newThreadCwd) }
    }

    /// Creates the session on the server, then sends the first prompt.
    public func sendFromNewThread(_ text: String, images: [ImageAttachment]) async -> String? {
        guard let client, let cwd = newThreadCwd else { return nil }
        var body: [String: Any] = ["cwd": cwd, "type": "ensure_session"]
        if let m = newThreadModel { body["provider"] = m.provider; body["modelId"] = m.modelId }
        if let t = newThreadThinking { body["thinkingLevel"] = t }
        do {
            let r = try await client.post("/api/agent/new", body: body)
            guard let sid = r["sessionId"]?.string else { toast = "Could not create session"; return nil }
            let s = SessionStore(sessionId: sid, client: client, info: nil)
            s.onRunFinished = { [weak self, weak s] aborted in
                guard let self, let s else { return }
                self.onRunFinished?(s, aborted); Task { await self.refreshSessions() }
            }
            stores[sid] = s
            selection = .thread(sid)
            syncWorkspace()
            s.connect()
            await s.refreshState()
            await s.loadCommands()
            if !s.commands.isEmpty { slashCommands = s.commands }
            let ok = await s.send(text, images: images)
            await refreshSessions()
            return ok ? sid : sid
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    // MARK: Sidebar actions

    private func uiPost(_ body: [String: Any]) async {
        guard let client else { return }
        if let r = try? await client.post("/api/sessions/ui-state", body: body), let st = r["state"] { ui = SessionUiState(json: st); rebuildSidebar() }
    }

    public func setPinned(_ id: String, _ pinned: Bool) async { await uiPost(["action": "set", "ids": [id], "pinned": pinned]) }
    public func setArchived(_ id: String, _ archived: Bool) async {
        await uiPost(["action": "set", "ids": [id], "archived": archived])
        if archived { toast = "Thread archived" }
    }
    public func setProjectPinned(_ g: ProjectGroup, _ pinned: Bool) async {
        await uiPost(["action": "pin-project", "projectKey": g.key, "root": g.root, "pinned": pinned])
    }
    public func renameProject(_ g: ProjectGroup, to name: String?) async {
        await uiPost(["action": "rename-project", "projectKey": g.key, "name": name as Any? ?? NSNull()])
    }

    public func moveProject(_ g: ProjectGroup, up: Bool) async {
        let band = sidebar.projects.filter { $0.pinned == g.pinned }
        guard let i = band.firstIndex(where: { $0.key == g.key }) else { return }
        let j = up ? i - 1 : i + 1
        guard band.indices.contains(j) else { return }
        let unsaved = band.map(\.key).filter { !ui.projectOrder.contains($0) }
        await uiPost(["action": "move-project", "projectKey": g.key, "anchorKey": band[j].key, "position": up ? "before" : "after", "add": unsaved])
    }

    public func canMoveProject(_ g: ProjectGroup, up: Bool) -> Bool {
        let band = sidebar.projects.filter { $0.pinned == g.pinned }
        guard let i = band.firstIndex(where: { $0.key == g.key }) else { return false }
        return band.indices.contains(up ? i - 1 : i + 1)
    }

    public func archiveOlderThanWeek(_ g: ProjectGroup) async {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        let ids = g.families.filter { $0.latest < cutoff && $0.pinnedAt == nil && !running.contains($0.id) }.map(\.id)
        guard !ids.isEmpty else { return }
        await uiPost(["action": "set", "ids": ids, "archived": true])
        toast = "Archived \(ids.count) older thread\(ids.count == 1 ? "" : "s")"
    }

    public func olderThanWeekCount(_ g: ProjectGroup) -> Int {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return g.families.filter { $0.latest < cutoff && $0.pinnedAt == nil && !running.contains($0.id) }.count
    }

    public func removeProjectFromList(_ g: ProjectGroup) async {
        let ids = g.families.filter { !running.contains($0.id) }.map(\.id)
        guard !ids.isEmpty else { return }
        await uiPost(["action": "set", "ids": ids, "archived": true])
        toast = "Removed “\(g.name)” from the list"
    }

    public func rename(_ id: String, to name: String) async {
        guard let client else { return }
        do { _ = try await client.send("PATCH", "/api/sessions/\(id)", body: ["name": name]); await refreshSessions() }
        catch { toast = error.localizedDescription }
    }

    public func delete(_ id: String) async {
        guard let client else { return }
        do {
            _ = try await client.send("DELETE", "/api/sessions/\(id)")
            stores[id]?.disconnect(); stores[id] = nil
            if selection == .thread(id) { selection = .newThread }
            await refreshSessions()
        } catch { toast = error.localizedDescription }
    }

    public func fork(_ id: String) async {
        guard let client else { return }
        do {
            let r = try await client.post("/api/sessions/\(id)/fork")
            await refreshSessions()
            if let n = r["sessionId"]?.string { select(n) }
        } catch { toast = error.localizedDescription }
    }

    /// Asks the model for a short title (same call the web app uses) and reports the outcome.
    public func autoName(_ id: String) async {
        guard let client, !namingNow.contains(id) else { return }
        namingNow.insert(id); defer { namingNow.remove(id) }
        toast = "Generating title…"
        do {
            let r = try await client.post("/api/sessions/\(id)/auto-name")
            await refreshSessions()
            toast = r["title"]?.string.map { "Titled: \($0)" } ?? "Title updated"
        } catch {
            toast = "Could not generate a title: \(error.localizedDescription)"
        }
    }
}
