import Foundation

/// Live assistant message being streamed. Mirrors `lib/streaming-message.ts`.
public struct StreamingState: Sendable, Equatable {
    public var isStreaming = false
    public var message: Message?
    public init() {}
    public static func == (a: Self, b: Self) -> Bool { a.isStreaming == b.isStreaming && a.message == b.message }
}

public enum StreamAction {
    case start
    case snapshot(Message)
    /// `assistantMessageEvent` payload of a `message_update` event.
    case delta(JSON)
    case end
}

public enum StreamReducer {
    public static func reduce(_ state: StreamingState, _ action: StreamAction) -> StreamingState {
        switch action {
        case .start:
            var s = StreamingState(); s.isStreaming = true; return s
        case .snapshot(let m):
            guard m.role == .assistant else { return state }
            var s = StreamingState(); s.isStreaming = true; s.message = m; return s
        case .delta(let e):
            return applyDelta(state, e)
        case .end:
            return StreamingState()
        }
    }

    private static func update(_ state: StreamingState, _ index: Int?, _ f: (ContentBlock?) -> ContentBlock?) -> StreamingState {
        guard var msg = state.message, let index, index >= 0 else { return state }
        let current = msg.blocks.indices.contains(index) ? msg.blocks[index] : nil
        guard let next = f(current) else { return state }
        while msg.blocks.count <= index { msg.blocks.append(.text("")) }
        msg.blocks[index] = next
        var s = state; s.isStreaming = true; s.message = msg
        return s
    }

    static func applyDelta(_ state: StreamingState, _ e: JSON) -> StreamingState {
        let idx = e["contentIndex"]?.int
        switch e["type"]?.string {
        case "text_start":
            // `start` must reset: the shared partial may already hold the first delta.
            return update(state, idx) { _ in .text("") }
        case "text_delta":
            return update(state, idx) { cur in
                if case .text(let t)? = cur { return .text(t + (e["delta"]?.string ?? "")) }
                return nil
            }
        case "text_end":
            return update(state, idx) { _ in .text(e["content"]?.string ?? "") }
        case "thinking_start":
            return update(state, idx) { _ in .thinking("") }
        case "thinking_delta":
            return update(state, idx) { cur in
                if case .thinking(let t)? = cur { return .thinking(t + (e["delta"]?.string ?? "")) }
                return nil
            }
        case "thinking_end":
            return update(state, idx) { _ in .thinking(e["content"]?.string ?? "") }
        case "toolcall_start":
            return update(state, idx) { cur in
                if case .toolCall(var c)? = cur {
                    c.id = e["id"]?.string ?? c.id
                    c.name = e["toolName"]?.string ?? c.name
                    c.rawInput = ""
                    return .toolCall(c)
                }
                guard let name = e["toolName"]?.string else { return nil }
                return .toolCall(ToolCall(id: e["id"]?.string ?? "", name: name, input: .object([:]), rawInput: ""))
            }
        case "toolcall_delta":
            return update(state, idx) { cur in
                if case .toolCall(var c)? = cur {
                    if let id = e["id"]?.string, !id.isEmpty { c.id = id }
                    if let n = e["toolName"]?.string, !n.isEmpty { c.name = n }
                    c.rawInput = (c.rawInput ?? "") + (e["delta"]?.string ?? "")
                    return .toolCall(c)
                }
                return nil
            }
        case "toolcall_end":
            return update(state, idx) { _ in
                let tc = e["toolCall"] ?? .null
                return .toolCall(ToolCall(id: tc["id"]?.string ?? "", name: tc["name"]?.string ?? "", input: tc["arguments"] ?? .object([:])))
            }
        default:
            return state
        }
    }
}

/// Best-effort parse of a partially streamed JSON object (tool arguments), so
/// cards can show `path` / `command` while the model is still writing.
public enum PartialJSON {
    public static func parse(_ raw: String) -> JSON? {
        if let j = JSON.parse(raw), j.object != nil { return j }
        // Close open strings / containers.
        var stack: [Character] = []
        var inString = false, escaped = false
        for ch in raw {
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]": if !stack.isEmpty { stack.removeLast() }
            default: break
            }
        }
        var s = raw
        if inString {
            if escaped { s.removeLast() }
            s += "\""
        }
        // Drop a dangling key / comma / colon.
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = trimmed
        for _ in 0..<3 {
            if s.hasSuffix(",") || s.hasSuffix(":") { s.removeLast(); s = s.trimmingCharacters(in: .whitespaces) }
        }
        let closers = String(stack.reversed())
        for candidate in [s + closers, dropLastKey(s) + closers] {
            if let j = JSON.parse(candidate), j.object != nil { return j }
        }
        return nil
    }

    private static func dropLastKey(_ s: String) -> String {
        // `{"a":"b","c"` → `{"a":"b"`
        guard let comma = s.lastIndex(of: ",") else { return s }
        return String(s[..<comma])
    }
}
