import Foundation
import Observation

public enum Selection: Hashable, Sendable {
    case thread(String)
    case newThread
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
    public private(set) var ui = SessionUiState()
    public private(set) var running: Set<String> = []
    public private(set) var awaiting: Set<String> = []
    public private(set) var sidebar = SidebarModel()
    public private(set) var catalog = ModelCatalog()
    public private(set) var sessionsLoaded = false
    public var selection: Selection = .newThread
    public var newThreadCwd: String?
    public var newThreadModel: ModelRef?
    public var newThreadThinking: String?
    public var toast: String?
    public var unread: Set<String> = []
    public var homeDirectory = NSHomeDirectory()

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
        sessionsLoaded = true
        if newThreadCwd == nil { newThreadCwd = sessions.first?.cwd ?? homeDirectory }
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
        async let list = try? client.get("/api/sessions", query: ["summary": "1"])
        async let uiJ = try? client.get("/api/sessions/ui-state")
        let (l, u) = await (list, uiJ)
        if let l {
            sessions = (l["sessions"]?.array ?? []).compactMap(SessionInfo.init(json:)).filter { !$0.transient || running.contains($0.id) }
            running = Set((l["runningSessionIds"]?.array ?? []).compactMap(\.string))
            awaiting = Set((l["awaitingInputSessionIds"]?.array ?? []).compactMap(\.string))
        }
        if let u, let st = u["state"] { ui = SessionUiState(json: st) }
        rebuildSidebar()
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

    public func select(_ id: String) {
        if case .thread(let cur) = selection, cur != id, let old = stores[cur], !old.isRunning { old.disconnect() }
        selection = .thread(id)
        unread.remove(id)
        guard let s = store(for: id) else { return }
        if let cwd = s.info?.cwd ?? sessions.first(where: { $0.id == id })?.cwd { newThreadCwd = cwd }
        Task {
            await s.load()
            s.connect()
            await s.refreshState()
            await s.loadCommands()
        }
    }

    public func startNewThread(cwd: String? = nil) {
        if let cwd { newThreadCwd = cwd }
        if case .thread(let cur) = selection, let old = stores[cur], !old.isRunning { old.disconnect() }
        selection = .newThread
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
            s.connect()
            await s.refreshState()
            await s.loadCommands()
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

    public func autoName(_ id: String) async {
        guard let client else { return }
        _ = try? await client.post("/api/sessions/\(id)/auto-name")
        await refreshSessions()
    }
}
