import Foundation

public struct ToolEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var call: ToolCall
    public var result: Message?
    public var isRunning: Bool
}

public enum WorkEntry: Identifiable, Hashable, Sendable {
    case thinking(id: String, text: String, live: Bool)
    case tool(ToolEntry)
    public var id: String {
        switch self { case .thinking(let id, _, _): return id; case .tool(let t): return t.id }
    }
}

public struct FileChange: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var additions: Int
    public var deletions: Int
}

public enum ThreadItem: Identifiable, Hashable, Sendable {
    case user(Message)
    case text(id: String, text: String, live: Bool, model: String?)
    case work(id: String, entries: [WorkEntry], live: Bool)
    case bash(Message)
    case custom(Message)
    case error(id: String, text: String)
    case workedFor(id: String, seconds: Double)
    case changes(id: String, files: [FileChange])

    public var id: String {
        switch self {
        case .user(let m), .bash(let m), .custom(let m): return m.id
        case .text(let id, _, _, _), .work(let id, _, _), .error(let id, _), .workedFor(let id, _), .changes(let id, _): return id
        }
    }
}

public enum TurnBuilder {
    public static func build(messages: [Message], streaming: Message?, isRunning: Bool, liveResults: [String: Message]) -> [ThreadItem] {
        var results: [String: Message] = [:]
        for m in messages where m.role == .toolResult { if let id = m.toolCallId { results[id] = m } }
        for (k, v) in liveResults { results[k] = v }

        var items: [ThreadItem] = []
        var work: [WorkEntry] = []
        var workLive = false
        var turnStart: Double?
        var turnEnd: Double?
        var turnChanges: [String: FileChange] = [:]
        var turnHasWork = false

        func flushWork() {
            if !work.isEmpty {
                items.append(.work(id: "work-" + work[0].id, entries: work, live: workLive))
                work = []; workLive = false
            }
        }
        func flushTurn(finished: Bool) {
            flushWork()
            guard finished else { turnChanges = [:]; turnHasWork = false; return }
            if !turnChanges.isEmpty {
                items.append(.changes(id: "chg-\(items.count)", files: turnChanges.values.sorted { $0.path < $1.path }))
            }
            if turnHasWork, let s = turnStart, let e = turnEnd, e > s, e - s >= 1000 {
                items.insert(.workedFor(id: "wf-\(items.count)", seconds: (e - s) / 1000), at: items.count - (turnChanges.isEmpty ? 0 : 1))
            }
            turnChanges = [:]; turnHasWork = false
        }

        func addAssistant(_ m: Message, live: Bool) {
            for (i, b) in m.blocks.enumerated() {
                let bid = "\(m.id)-\(i)"
                switch b {
                case .text(let t):
                    if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    flushWork()
                    items.append(.text(id: bid, text: t, live: live && i == m.blocks.count - 1, model: m.model))
                case .thinking(let t):
                    if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !live { continue }
                    work.append(.thinking(id: bid, text: t, live: live && i == m.blocks.count - 1))
                    turnHasWork = true
                    if live { workLive = true }
                case .toolCall(let c):
                    let id = c.id.isEmpty ? bid : c.id
                    let res = results[c.id]
                    let running = res == nil && (live || isRunning)
                    work.append(.tool(ToolEntry(id: id, call: c, result: res, isRunning: running)))
                    turnHasWork = true
                    if running { workLive = true }
                    if let ch = change(for: c, result: res) {
                        var cur = turnChanges[ch.path] ?? FileChange(path: ch.path, additions: 0, deletions: 0)
                        cur.additions += ch.additions; cur.deletions += ch.deletions
                        turnChanges[ch.path] = cur
                    }
                case .image:
                    break
                }
            }
            if m.stopReason == "error", let err = m.errorMessage, !err.isEmpty {
                flushWork()
                items.append(.error(id: m.id + "-err", text: err))
            }
            if let ts = m.timestamp { turnEnd = ts + (m.durationMs ?? 0) }
        }

        for m in messages {
            switch m.role {
            case .user:
                flushTurn(finished: true)
                turnStart = m.timestamp; turnEnd = m.timestamp
                items.append(.user(m))
            case .assistant:
                addAssistant(m, live: false)
            case .toolResult:
                if let ts = m.timestamp { turnEnd = max(turnEnd ?? 0, ts) }
            case .bashExecution:
                flushWork(); items.append(.bash(m))
            case .custom:
                if m.display { flushWork(); items.append(.custom(m)) }
            default: break
            }
        }
        if let s = streaming { addAssistant(s, live: true) }
        flushTurn(finished: !isRunning)
        return items
    }

    public static func change(for c: ToolCall, result: Message?) -> FileChange? {
        guard result?.isError != true else { return nil }
        let path = c.input["path"]?.string ?? c.input["file_path"]?.string
        guard let path else { return nil }
        switch c.name {
        case "write":
            let n = c.input["content"]?.string.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0
            return FileChange(path: path, additions: n, deletions: 0)
        case "edit":
            if let diff = result?.details?["diff"]?.string {
                var a = 0, d = 0
                for line in diff.split(separator: "\n") {
                    if line.hasPrefix("+") { a += 1 } else if line.hasPrefix("-") { d += 1 }
                }
                return FileChange(path: path, additions: a, deletions: d)
            }
            var a = 0, d = 0
            let edits = c.input["edits"]?.array ?? [c.input]
            for e in edits {
                a += e["newText"]?.string.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0
                d += e["oldText"]?.string.map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0
            }
            return FileChange(path: path, additions: a, deletions: d)
        default: return nil
        }
    }
}
