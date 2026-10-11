import Foundation

// MARK: - Content

public struct ImageRef: Hashable, Sendable {
    public var mediaType: String?
    /// base64 payload
    public var data: String?
    public var url: String?
    public init(mediaType: String? = nil, data: String? = nil, url: String? = nil) {
        self.mediaType = mediaType; self.data = data; self.url = url
    }
}

public struct ToolCall: Hashable, Sendable {
    public var id: String
    public var name: String
    public var input: JSON
    /// Streamed, not yet complete JSON arguments.
    public var rawInput: String?
    public init(id: String, name: String, input: JSON = .object([:]), rawInput: String? = nil) {
        self.id = id; self.name = name; self.input = input; self.rawInput = rawInput
    }
}

public enum ContentBlock: Hashable, Sendable {
    case text(String)
    case thinking(String)
    case image(ImageRef)
    case toolCall(ToolCall)

    static func parse(_ j: JSON) -> ContentBlock? {
        switch j["type"]?.string {
        case "text": return .text(j["text"]?.string ?? "")
        case "thinking": return .thinking(j["thinking"]?.string ?? "")
        case "image":
            if let s = j["source"] {
                return .image(ImageRef(mediaType: s["media_type"]?.string ?? s["mediaType"]?.string, data: s["data"]?.string, url: s["url"]?.string))
            }
            return .image(ImageRef(mediaType: j["mimeType"]?.string, data: j["data"]?.string, url: j["url"]?.string))
        case "toolCall":
            // Session/context output is normalised (toolCallId/toolName/input);
            // live SDK events use id/name/arguments.
            let id = j["toolCallId"]?.string ?? j["id"]?.string ?? ""
            let name = j["toolName"]?.string ?? j["name"]?.string ?? ""
            let input = j["input"] ?? j["arguments"] ?? .object([:])
            return .toolCall(ToolCall(id: id, name: name, input: input))
        default: return nil
        }
    }
}

public struct Usage: Hashable, Sendable {
    public var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
    public var totalCost: Double = 0
    static func parse(_ j: JSON?) -> Usage? {
        guard let j, j.object != nil else { return nil }
        var u = Usage()
        u.input = j["input"]?.int ?? 0
        u.output = j["output"]?.int ?? 0
        u.cacheRead = j["cacheRead"]?.int ?? 0
        u.cacheWrite = j["cacheWrite"]?.int ?? 0
        u.totalCost = j["cost"]?["total"]?.double ?? 0
        return u
    }
}

// MARK: - Message

public struct Message: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable { case user, assistant, toolResult, custom, bashExecution, system, unknown }

    public var id: String
    public var role: Role
    public var blocks: [ContentBlock]
    // toolResult
    public var toolCallId: String?
    public var toolName: String?
    public var isError: Bool = false
    public var details: JSON?
    public var durationMs: Double?
    public var timestamp: Double?
    // assistant
    public var model: String?
    public var provider: String?
    public var stopReason: String?
    public var errorMessage: String?
    public var usage: Usage?
    // custom
    public var customType: String?
    public var display: Bool = true
    // bashExecution
    public var command: String?
    public var output: String?
    public var exitCode: Int?
    public var cancelled: Bool = false
    public var truncated: Bool = false
    public var excludeFromContext: Bool = false

    public init(id: String = UUID().uuidString, role: Role, blocks: [ContentBlock] = []) {
        self.id = id; self.role = role; self.blocks = blocks
    }

    public static func user(_ text: String, images: [ImageRef] = []) -> Message {
        var blocks: [ContentBlock] = []
        if !text.isEmpty { blocks.append(.text(text)) }
        blocks += images.map { .image($0) }
        var m = Message(role: .user, blocks: blocks)
        m.timestamp = Date().timeIntervalSince1970 * 1000
        return m
    }

    public init(json j: JSON, id: String? = nil) {
        self.id = id ?? UUID().uuidString
        self.role = Role(rawValue: j["role"]?.string ?? "") ?? .unknown
        if let s = j["content"]?.string {
            self.blocks = s.isEmpty ? [] : [.text(s)]
        } else {
            self.blocks = (j["content"]?.array ?? []).compactMap(ContentBlock.parse)
        }
        toolCallId = j["toolCallId"]?.string
        toolName = j["toolName"]?.string
        isError = j["isError"]?.bool ?? false
        details = j["details"]
        durationMs = j["durationMs"]?.double
        timestamp = j["timestamp"]?.double
        model = j["model"]?.string
        provider = j["provider"]?.string
        stopReason = j["stopReason"]?.string
        errorMessage = j["errorMessage"]?.string
        usage = Usage.parse(j["usage"])
        customType = j["customType"]?.string
        display = j["display"]?.bool ?? true
        if role == .bashExecution {
            command = j["command"]?.string
            output = j["output"]?.string
            exitCode = j["exitCode"]?.int
            cancelled = j["cancelled"]?.bool ?? false
            truncated = j["truncated"]?.bool ?? false
            excludeFromContext = j["excludeFromContext"]?.bool ?? false
        }
    }

    /// Plain text of all text blocks.
    public var text: String {
        blocks.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n\n")
    }
    public var toolCalls: [ToolCall] {
        blocks.compactMap { if case .toolCall(let c) = $0 { return c } else { return nil } }
    }
}

// MARK: - Sessions

public struct SessionRelation: Hashable, Sendable {
    public enum Kind: String, Sendable { case fork, subagent }
    public var kind: Kind
    public var parentSessionId: String?
    public var profile: String?
    public var description: String?
    public var status: String?
}

public struct SessionInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var path: String
    public var cwd: String
    public var name: String?
    public var created: Date
    public var modified: Date
    public var messageCount: Int
    public var firstMessage: String
    public var projectRoot: String
    public var projectKey: String
    public var parentSessionId: String?
    public var relation: SessionRelation?
    public var transient: Bool
    /// True for a summary row: the server returned header metadata only, so the name and the first
    /// message are not known yet. Such a row must not be titled "New thread" as if it were empty.
    public var detailsPending: Bool

    public var title: String {
        if let n = name, !n.isEmpty { return n }
        let f = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? "New thread" : f
    }

    public init?(json j: JSON) {
        guard let id = j["id"]?.string else { return nil }
        self.id = id
        path = j["path"]?.string ?? ""
        cwd = j["cwd"]?.string ?? ""
        name = j["name"]?.string
        created = Self.parseDate(j["created"]?.string)
        modified = Self.parseDate(j["modified"]?.string)
        messageCount = j["messageCount"]?.int ?? 0
        firstMessage = j["firstMessage"]?.string ?? ""
        projectRoot = j["projectRoot"]?.string ?? cwd
        projectKey = j["projectKey"]?.string ?? projectRoot
        parentSessionId = j["parentSessionId"]?.string
        transient = j["transient"]?.bool ?? false
        detailsPending = j["detailsPending"]?.bool ?? false
        if let r = j["relation"], let kind = r["kind"]?.string.flatMap(SessionRelation.Kind.init(rawValue:)) {
            relation = SessionRelation(
                kind: kind,
                parentSessionId: r["parentSessionId"]?.string ?? r["originSessionId"]?.string,
                profile: r["profile"]?.string, description: r["description"]?.string, status: r["status"]?.string)
        }
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()
    static func parseDate(_ s: String?) -> Date {
        guard let s else { return .distantPast }
        return iso.date(from: s) ?? isoPlain.date(from: s) ?? .distantPast
    }
}

// MARK: - Sidebar UI state (pins / archive / project order)

public struct SessionUiState: Sendable {
    public var revision = 0
    public var pinnedAt: [String: Double] = [:]
    public var archivedAt: [String: Double] = [:]
    public var projectPinnedAt: [String: Double] = [:]
    public var projectOrder: [String] = []
    public var projectNames: [String: String] = [:]

    public init() {}
    public init(json j: JSON) {
        revision = j["revision"]?.int ?? 0
        for (id, v) in j["sessions"]?.object ?? [:] {
            if let p = v["pinnedAt"]?.double { pinnedAt[id] = p }
            if let a = v["archivedAt"]?.double { archivedAt[id] = a }
        }
        for (k, v) in j["projects"]?.object ?? [:] {
            if let p = v["pinnedAt"]?.double { projectPinnedAt[k] = p }
        }
        projectOrder = (j["projectOrder"]?.array ?? []).compactMap(\.string)
        for (k, v) in j["projectNames"]?.object ?? [:] { if let s = v.string { projectNames[k] = s } }
    }
}

// MARK: - Models

public struct ModelInfo: Identifiable, Hashable, Sendable {
    public var id: String { "\(provider):\(modelId)" }
    public var modelId: String
    public var name: String
    public var provider: String
    public var supportsImages: Bool
    public var thinkingLevels: [String]
}

public struct ModelRef: Hashable, Sendable {
    public var provider: String
    public var modelId: String
    public init(provider: String, modelId: String) { self.provider = provider; self.modelId = modelId }
}

public struct ContextUsage: Hashable, Sendable {
    public var percent: Double?
    public var tokens: Int?
    public var contextWindow: Int?
}

public struct QueuedMessages: Hashable, Sendable {
    public var steering: [String] = []
    public var followUp: [String] = []
    public var isEmpty: Bool { steering.isEmpty && followUp.isEmpty }
}

public struct SlashCommand: Identifiable, Hashable, Sendable {
    public var id: String { name + source }
    public var name: String
    public var description: String
    public var source: String
}

public struct GitFileChange: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var status: String
    public var additions: Int
    public var deletions: Int
}
