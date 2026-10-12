import Foundation
import Observation

public struct ExtensionRequest: Identifiable, Hashable, Sendable {
    public var id: String
    public var method: String
    public var title: String
    public var message: String
    public var options: [String]
    public var placeholder: String?
    public var prefill: String?
    public var expiresAt: Double?
    init(json j: JSON) {
        id = j["id"]?.string ?? UUID().uuidString
        method = j["method"]?.string ?? ""
        title = j["title"]?.string ?? ""
        message = j["message"]?.string ?? ""
        options = (j["options"]?.array ?? []).compactMap(\.string)
        placeholder = j["placeholder"]?.string
        prefill = j["prefill"]?.string
        expiresAt = j["expiresAt"]?.double
    }
}

public struct StatusItem: Hashable, Sendable, Identifiable { public var id: String { key }; public var key: String; public var text: String }
public struct WidgetItem: Hashable, Sendable, Identifiable {
    public var id: String { key }; public var key: String; public var lines: [String]; public var placement: String
}

public struct Notice: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case info, warning, error }
    public let id = UUID()
    public var kind: Kind
    public var text: String
}

public struct RunningTool: Identifiable, Hashable, Sendable { public var id: String; public var name: String }
public enum Phase: Hashable, Sendable {
    case waitingModel
    case runningCommand
    case runningTools([RunningTool])
}

public struct RetryInfo: Hashable, Sendable { public var attempt: Int; public var maxAttempts: Int; public var message: String? }

public struct ImageAttachment: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var mimeType: String
    public var base64: String
    public var name: String
    public init(mimeType: String, base64: String, name: String = "image") { self.mimeType = mimeType; self.base64 = base64; self.name = name }
}

/// State of one open session. Mirrors `hooks/useAgentSession.ts`.
@MainActor
@Observable
public final class SessionStore {
    public let sessionId: String
    public private(set) var info: SessionInfo?
    public private(set) var messages: [Message] = []
    public private(set) var entryIds: [String] = []
    public private(set) var hasMore = false
    /// Server snapshot token. A change means another client wrote to this session.
    private var snapshotRevision: String?
    public private(set) var isLoading = false
    public private(set) var loadError: String?
    public private(set) var streaming = StreamingState()
    public private(set) var phase: Phase?
    public private(set) var isRunning = false
    public private(set) var isBashRunning = false
    public private(set) var queued = QueuedMessages()
    public private(set) var retry: RetryInfo?
    public private(set) var isCompacting = false
    public private(set) var notices: [Notice] = []
    public private(set) var dialogs: [ExtensionRequest] = []
    public private(set) var statuses: [StatusItem] = []
    public private(set) var widgets: [WidgetItem] = []
    public private(set) var liveToolResults: [String: Message] = [:]
    public private(set) var model: ModelRef?
    public private(set) var thinkingLevel: String?
    public private(set) var contextUsage: ContextUsage?
    public private(set) var commands: [SlashCommand] = []
    public private(set) var runStartedAt: Date?
    public private(set) var lastRunDuration: TimeInterval?
    public var editorTextRequest: String?

    /// Called when a run ends (aborted?) — drives sound / notifications.
    public var onRunFinished: ((_ aborted: Bool) -> Void)?
    public var onChanged: (() -> Void)?

    let client: APIClient
    private var eventTask: Task<Void, Never>?
    private var leaseTask: Task<Void, Never>?
    private var wantsEvents = false
    private var sdkAgentActive = false
    private var promptPending = false
    private var optimisticKey: String?

    public init(sessionId: String, client: APIClient, info: SessionInfo? = nil) {
        self.sessionId = sessionId; self.client = client; self.info = info
    }

    // MARK: Loading

    public func load(tail: Int = 50) async {
        if messages.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let d = try await client.get("/api/sessions/\(sessionId)", query: ["tail": String(tail), "tree": "summary"])
            if let i = d["info"], let si = SessionInfo(json: i) { info = si }
            snapshotRevision = d["snapshotRevision"]?.string
            let ctx = d["context"] ?? .null
            let msgs = ctx["messages"]?.array ?? []
            let ids = (ctx["entryIds"]?.array ?? []).map { $0.string ?? "" }
            // While streaming, don't clobber the optimistic tail with a stale file read.
            if !isRunning || streaming.message == nil {
                let fresh = msgs.enumerated().map { Message(json: $1, id: ids.indices.contains($0) ? ids[$0] : nil) }
                // Everything the user already paged in ("Load earlier messages") sits before the newest
                // window. A refresh replaces only that window, so older history is never dropped.
                let merged: [Message]
                let mergedIds: [String]
                if let firstId = ids.first, let cut = entryIds.firstIndex(of: firstId), cut > 0 {
                    merged = Array(messages.prefix(cut)) + fresh
                    mergedIds = Array(entryIds.prefix(cut)) + ids
                } else {
                    merged = fresh
                    mergedIds = ids
                }
                // Assigning an identical array still re-renders the whole transcript, so skip it when the
                // entries are unchanged. That is what made open threads flicker on every sync tick.
                if mergedIds != entryIds || merged.count != messages.count || merged.last?.id != messages.last?.id {
                    messages = merged
                    entryIds = mergedIds
                    SyncLog.write("\(sessionId.prefix(8)) rewrote transcript (\(merged.count) rows)")
                }
                // "hasMore" stays true while there is older history left to page in.
                hasMore = hasMore || (ctx["hasMore"]?.bool ?? false)
            }
            if let m = ctx["model"], let p = m["provider"]?.string, let mid = m["modelId"]?.string { model = ModelRef(provider: p, modelId: mid) }
            if let t = ctx["thinkingLevel"]?.string { thinkingLevel = t }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Reloads when the session file changed under us, so a turn finished in pi-web (or another
    /// window) shows up here without reopening the thread. Skipped while this window is streaming.
    /// Pulls the thread again when the file changed on disk, whoever wrote it. An event stream only reports
    /// the runs this window started, so a turn written from another window (pi-gui, pi-web) is found here.
    /// A thread that is streaming here is left alone: its live tail is newer than the file until the run ends.
    public func syncIfChanged() async {
        guard !isLoading, !isRunning else {
            SyncLog.write("\(sessionId.prefix(8)) skipped loading=\(isLoading) running=\(isRunning)")
            return
        }
        guard let d = try? await client.get("/api/sessions/\(sessionId)", query: ["tail": "1"]) else { SyncLog.write("\(sessionId.prefix(8)) fetch failed"); return }
        guard let rev = d["snapshotRevision"]?.string else { SyncLog.write("\(sessionId.prefix(8)) no snapshotRevision in response"); return }
        let decision = SyncDecision.decide(known: snapshotRevision, current: rev)
        SyncLog.write("\(sessionId.prefix(8)) known=\(snapshotRevision ?? "nil") current=\(rev) -> \(decision)")
        switch decision {
        case .recordOnly: snapshotRevision = rev
        case .reload: await load()
        case .none: break
        }
    }

    public func loadOlder() async {
        guard hasMore, !isLoading, let oldest = entryIds.first else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let d = try await client.get("/api/sessions/\(sessionId)/context", query: ["before": oldest, "tail": "50"])
            let ctx = d["context"] ?? .null
            let msgs = ctx["messages"]?.array ?? []
            let ids = (ctx["entryIds"]?.array ?? []).map { $0.string ?? "" }
            let older = msgs.enumerated().map { Message(json: $1, id: ids.indices.contains($0) ? ids[$0] : nil) }
            messages = older + messages
            entryIds = ids + entryIds
            hasMore = ctx["hasMore"]?.bool ?? false
        } catch { addNotice(.error, error.localizedDescription) }
    }

    /// `GET /api/agent/{id}` — model, context usage, queue, extension UI state.
    public func refreshState() async {
        guard let d = try? await client.get("/api/agent/\(sessionId)"), let st = d["state"], !st.isNull else { return }
        if let m = st["model"], let p = m["provider"]?.string, let id = m["id"]?.string { model = ModelRef(provider: p, modelId: id) }
        if let t = st["thinkingLevel"]?.string { thinkingLevel = t }
        if let cu = st["contextUsage"], cu.object != nil {
            contextUsage = ContextUsage(percent: cu["percent"]?.double, tokens: cu["tokens"]?.int, contextWindow: cu["contextWindow"]?.int)
        }
        if let q = st["queuedMessages"] { queued = Self.parseQueue(q) }
        if let s = st["extensionStatuses"]?.array {
            statuses = s.compactMap { j in j["key"]?.string.map { StatusItem(key: $0, text: j["text"]?.string ?? "") } }
        }
        if let w = st["extensionWidgets"]?.array {
            widgets = w.compactMap { j in j["key"]?.string.map { WidgetItem(key: $0, lines: (j["lines"]?.array ?? []).compactMap(\.string), placement: j["placement"]?.string ?? "aboveEditor") } }
        }
        if st["isStreaming"]?.bool == true, !isRunning { beginRun(resumed: true) }
    }

    public func loadCommands() async {
        guard let d = try? await client.command(sessionId, ["type": "get_commands"]) else { return }
        commands = (d["commands"]?.array ?? []).compactMap { j in
            guard let n = j["name"]?.string else { return nil }
            return SlashCommand(name: n, description: j["description"]?.string ?? "", source: j["source"]?.string ?? "")
        }
    }

    static func parseQueue(_ q: JSON) -> QueuedMessages {
        QueuedMessages(steering: (q["steering"]?.array ?? []).compactMap(\.string), followUp: (q["followUp"]?.array ?? []).compactMap(\.string))
    }

    // MARK: Events

    public func connect() {
        wantsEvents = true
        guard eventTask == nil else { return }
        startLease()
        eventTask = Task { [weak self] in
            var backoff = 0.5
            while let self, self.wantsEvents, !Task.isCancelled {
                do {
                    let stream = self.client.events("/api/agent/\(self.sessionId)/events")
                    for try await ev in stream {
                        backoff = 0.5
                        self.handle(ev)
                    }
                } catch {
                    if Task.isCancelled { break }
                }
                guard self.wantsEvents, !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 8)
                await self.reconcileAfterReconnect()
            }
        }
    }

    public func disconnect() {
        wantsEvents = false
        eventTask?.cancel(); eventTask = nil
        leaseTask?.cancel(); leaseTask = nil
    }

    private func reconcileAfterReconnect() async {
        await load()
        await refreshState()
    }

    private func startLease() {
        leaseTask?.cancel()
        leaseTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                _ = try? await self.client.post("/api/agent/\(self.sessionId)/lease")
            }
        }
    }

    private func beginRun(resumed: Bool = false) {
        isRunning = true
        sdkAgentActive = true
        if runStartedAt == nil { runStartedAt = Date() }
        if phase == nil { phase = .waitingModel }
        if !resumed { streaming = StreamReducer.reduce(streaming, .start) }
        else { streaming.isStreaming = true }
    }

    private func settle(aborted: Bool) {
        let wasRunning = isRunning
        isRunning = false
        sdkAgentActive = false
        promptPending = false
        phase = nil
        retry = nil
        streaming = StreamReducer.reduce(streaming, .end)
        liveToolResults = [:]
        if let s = runStartedAt { lastRunDuration = Date().timeIntervalSince(s) }
        runStartedAt = nil
        optimisticKey = nil
        Task { await self.load(); await self.refreshState() }
        if wasRunning { onRunFinished?(aborted) }
    }

    func handle(_ e: JSON) {
        defer { onChanged?() }
        switch e["type"]?.string {
        case "connected":
            if let pending = e["pendingExtensionUiIds"]?.array?.compactMap(\.string) {
                let keep = Set(pending); dialogs = dialogs.filter { keep.contains($0.id) }
            }
            if e["isStreaming"]?.bool == true { beginRun(resumed: true) }
            Task { await self.refreshState() }
        case "agent_start":
            retry = nil
            beginRun()
            phase = .waitingModel
        case "agent_end":
            guard isRunning else { break }
            phase = nil; retry = nil
            streaming = StreamReducer.reduce(streaming, .end)
            Task { await self.load(); await self.refreshState() }
        case "agent_settled":
            let was = sdkAgentActive
            sdkAgentActive = false
            if !was || promptPending { break }
            settle(aborted: e["aborted"]?.bool == true)
        case "prompt_done":
            let wasPending = promptPending
            promptPending = false
            optimisticKey = nil
            if !wasPending && !isRunning { break }
            if !sdkAgentActive { settle(aborted: e["aborted"]?.bool == true) }
        case "prompt_error":
            addNotice(.error, e["errorMessage"]?.string ?? "Command failed")
        case "extension_error":
            addNotice(.error, e["error"]?.string ?? "Extension command failed")
        case "message_start", "message_update":
            guard isRunning else { break }
            if e["message"]?["role"]?.string == "system" { break }
            if e["type"]?.string == "message_start" {
                guard let m = e["message"], let role = m["role"]?.string else { break }
                if role == "user" { break }
                if role == "assistant" {
                    streaming = StreamReducer.reduce(streaming, .snapshot(Message(json: m)))
                    if !(Message(json: m).blocks.isEmpty) { phase = nil }
                } else { phase = nil }
            } else if let d = e["assistantMessageEvent"] {
                streaming = StreamReducer.reduce(streaming, .delta(d))
                let t = d["type"]?.string
                if t != "toolcall_start" && t != "toolcall_delta" { phase = nil }
            }
        case "message_end":
            guard isRunning else { break }
            guard let mj = e["message"], mj["role"]?.string != "system" else { break }
            let msg = Message(json: mj)
            if msg.role == .user {
                let key = Self.userKey(msg)
                let opt = optimisticKey; optimisticKey = nil
                if let opt, let last = messages.last, last.role == .user, Self.userKey(last) == opt {
                    if opt != key { messages[messages.count - 1] = msg }
                } else { messages.append(msg) }
            } else {
                messages.append(msg)
                if msg.role == .assistant { Task { await self.refreshState() } }
            }
            streaming = StreamReducer.reduce(streaming, .end)
            streaming.isStreaming = true
            phase = .waitingModel
        case "tool_execution_start":
            if e["parentToolCallId"]?.string?.isEmpty == false { break }
            let t = RunningTool(id: e["toolCallId"]?.string ?? "", name: e["toolName"]?.string ?? "")
            var tools: [RunningTool] = []
            if case .runningTools(let cur)? = phase { tools = cur }
            if !tools.contains(where: { $0.id == t.id }) { tools.append(t) }
            phase = .runningTools(tools)
        case "tool_execution_update":
            if e["parentToolCallId"]?.string?.isEmpty == false { break }
            let id = e["toolCallId"]?.string ?? ""
            let name = e["toolName"]?.string ?? ""
            if let pr = e["partialResult"], let content = pr["content"]?.array, name == "bash" || name == "powershell" || name == "codemode" {
                var m = Message(id: id, role: .toolResult, blocks: content.compactMap(ContentBlock.parse))
                m.toolCallId = id; m.toolName = name; m.isError = pr["isError"]?.bool ?? false; m.details = pr["details"]
                liveToolResults[id] = m
            }
        case "tool_execution_end":
            if e["parentToolCallId"]?.string?.isEmpty == false { break }
            let id = e["toolCallId"]?.string ?? ""
            liveToolResults[id] = nil
            if case .runningTools(var tools)? = phase {
                tools.removeAll { $0.id == id }
                phase = tools.isEmpty ? .waitingModel : .runningTools(tools)
            }
        case "queue_update":
            queued = Self.parseQueue(e)
        case "auto_retry_start":
            retry = RetryInfo(attempt: e["attempt"]?.int ?? 1, maxAttempts: e["maxAttempts"]?.int ?? 1, message: e["errorMessage"]?.string)
        case "auto_retry_end":
            retry = nil
        case "auto_compaction_start", "compaction_start":
            isCompacting = true
        case "auto_compaction_end", "compaction_end":
            isCompacting = false
            if let err = e["errorMessage"]?.string { addNotice(.error, err) }
            else if e["aborted"]?.bool != true { Task { await self.load() } }
        case "extension_ui_request":
            handleExtensionUi(e)
        case "extension_ui_closed":
            if let id = e["id"]?.string { dialogs.removeAll { $0.id == id } }
        default: break
        }
    }

    static func userKey(_ m: Message) -> String {
        m.text + "|" + String(m.blocks.filter { if case .image = $0 { return true } else { return false } }.count)
    }

    private func handleExtensionUi(_ e: JSON) {
        switch e["method"]?.string {
        case "select", "confirm", "input", "editor":
            let r = ExtensionRequest(json: e)
            if !dialogs.contains(where: { $0.id == r.id }) { dialogs.append(r) }
        case "notify":
            let k: Notice.Kind = e["notifyType"]?.string == "error" ? .error : (e["notifyType"]?.string == "warning" ? .warning : .info)
            addNotice(k, e["message"]?.string ?? "")
        case "setStatus":
            let key = e["statusKey"]?.string ?? ""
            if let t = e["statusText"]?.string, !t.isEmpty {
                if let i = statuses.firstIndex(where: { $0.key == key }) { statuses[i].text = t } else { statuses.append(StatusItem(key: key, text: t)) }
            } else { statuses.removeAll { $0.key == key } }
        case "setWidget":
            let key = e["widgetKey"]?.string ?? ""
            if let lines = e["widgetLines"]?.array?.compactMap(\.string), !lines.isEmpty {
                let w = WidgetItem(key: key, lines: lines, placement: e["widgetPlacement"]?.string ?? "aboveEditor")
                if let i = widgets.firstIndex(where: { $0.key == key }) { widgets[i] = w } else { widgets.append(w) }
            } else { widgets.removeAll { $0.key == key } }
        case "set_editor_text":
            editorTextRequest = e["text"]?.string
        default: break
        }
    }

    // MARK: Actions

    public func addNotice(_ kind: Notice.Kind, _ text: String) {
        guard !text.isEmpty else { return }
        notices.append(Notice(kind: kind, text: text))
        let id = notices.last!.id
        Task { try? await Task.sleep(for: .seconds(8)); self.notices.removeAll { $0.id == id } }
    }
    public func dismissNotice(_ id: UUID) { notices.removeAll { $0.id == id } }

    /// Sends a prompt. While a run is active it is delivered as a steer (or follow-up).
    public func send(_ text: String, images: [ImageAttachment] = [], whileRunning: String = "steer") async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return false }
        if trimmed.hasPrefix("!") && images.isEmpty && !isRunning {
            return await runBash(trimmed)
        }
        var cmd: [String: Any] = ["type": "prompt", "message": text]
        if !images.isEmpty { cmd["images"] = images.map { ["type": "image", "data": $0.base64, "mimeType": $0.mimeType] } }
        if isRunning { cmd["streamingBehavior"] = whileRunning == "followUp" ? "followUp" : "steer" }
        else {
            let m = Message.user(text, images: images.map { ImageRef(mediaType: $0.mimeType, data: $0.base64) })
            messages.append(m)
            optimisticKey = Self.userKey(m)
            promptPending = true
            isRunning = true
            runStartedAt = Date()
            phase = text.hasPrefix("/") ? .runningCommand : .waitingModel
            streaming = StreamReducer.reduce(streaming, .start)
        }
        do {
            try await client.command(sessionId, cmd)
            return true
        } catch {
            if !isRunning || promptPending {
                // Definitive refusal: roll back the optimistic bubble.
                if let last = messages.last, last.role == .user, Self.userKey(last) == optimisticKey { messages.removeLast() }
                promptPending = false; optimisticKey = nil
                isRunning = false; phase = nil; runStartedAt = nil
                streaming = StreamReducer.reduce(streaming, .end)
            }
            addNotice(.error, error.localizedDescription)
            return false
        }
    }

    private func runBash(_ raw: String) async -> Bool {
        let excluded = raw.hasPrefix("!!")
        let cmd = String(raw.dropFirst(excluded ? 2 : 1)).trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return false }
        isBashRunning = true; defer { isBashRunning = false }
        do {
            try await client.command(sessionId, ["type": "bash", "command": cmd, "excludeFromContext": excluded])
            await load()
            return true
        } catch { addNotice(.error, error.localizedDescription); return false }
    }

    public func abort() async {
        do {
            try await client.command(sessionId, ["type": isBashRunning ? "abort_bash" : "abort"])
        } catch { addNotice(.error, error.localizedDescription) }
    }

    public func clearQueue() async { _ = try? await client.command(sessionId, ["type": "clear_queue"]); await refreshState() }

    public func setModel(_ m: ModelRef) async {
        let prev = model; model = m
        do { try await client.command(sessionId, ["type": "set_model", "provider": m.provider, "modelId": m.modelId]); await refreshState() }
        catch { model = prev; addNotice(.error, error.localizedDescription) }
    }

    public func setThinking(_ level: String) async {
        let prev = thinkingLevel; thinkingLevel = level
        do { try await client.command(sessionId, ["type": "set_thinking_level", "level": level]) }
        catch { thinkingLevel = prev; addNotice(.error, error.localizedDescription) }
    }

    public func compact() async {
        do { try await client.command(sessionId, ["type": "compact"]) } catch { addNotice(.error, error.localizedDescription) }
    }

    public func respond(to request: ExtensionRequest, value: String? = nil, confirmed: Bool? = nil, cancelled: Bool = false) async {
        dialogs.removeAll { $0.id == request.id }
        var cmd: [String: Any] = ["type": "extension_ui_response", "id": request.id]
        if cancelled { cmd["cancelled"] = true }
        else if let confirmed { cmd["confirmed"] = confirmed }
        else { cmd["value"] = value ?? "" }
        _ = try? await client.command(sessionId, cmd)
    }

    public func fork() async -> String? {
        let r = try? await client.post("/api/sessions/\(sessionId)/fork")
        return r?["sessionId"]?.string
    }

    /// Tool result for a call id, from loaded or live messages.
    public func result(for callId: String) -> Message? {
        liveToolResults[callId] ?? messages.last { $0.role == .toolResult && $0.toolCallId == callId }
    }
}

/// When an open thread should reload after the server reports a revision. Pure, so it is tested directly.
public enum SyncDecision: Equatable, Sendable {
    case none, recordOnly, reload

    public static func decide(known: String?, current: String) -> SyncDecision {
        guard let known else { return .recordOnly }   // first sight: remember it, nothing to compare yet
        return known == current ? .none : .reload
    }
}

/// Diagnostic trail for thread sync, written to ~/Library/Logs/PiNative/sync.log.
enum SyncLog {
    static func write(_ line: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PiNative")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("sync.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }
}
