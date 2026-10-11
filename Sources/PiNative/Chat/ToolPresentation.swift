import SwiftUI
import PiKit

/// How a tool call reads in the thread ("Read foo.swift", "Ran npm test").
struct ToolPresentation {
    enum Kind { case read, edit, write, command, search, list, web, agent, mcp, other }
    var kind: Kind
    var icon: String
    var verb: String          // "Read", "Ran", "Edited"…
    var runningVerb: String   // "Reading", "Running"…
    var target: String        // file name, command, query
    var fullPath: String?
    var stats: (add: Int, del: Int)?

    static func describe(_ e: ToolEntry) -> ToolPresentation {
        let c = e.call
        let input = c.input.object != nil && !(c.input.object ?? [:]).isEmpty ? c.input : (c.rawInput.flatMap(PartialJSON.parse) ?? c.input)
        func str(_ k: String...) -> String? { for key in k { if let s = input[key]?.string, !s.isEmpty { return s } }; return nil }
        let path = str("path", "file_path", "filePath")
        let base = path.map { ($0 as NSString).lastPathComponent }
        switch c.name {
        case "read":
            return .init(kind: .read, icon: "doc.text", verb: "Read", runningVerb: "Reading", target: base ?? "file", fullPath: path)
        case "write":
            let n = str("content").map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0
            return .init(kind: .write, icon: "square.and.pencil", verb: "Wrote", runningVerb: "Writing", target: base ?? "file", fullPath: path, stats: n > 0 ? (n, 0) : nil)
        case "edit":
            var s: (Int, Int)? = nil
            if let ch = TurnBuilder.change(for: c, result: e.result) { s = (ch.additions, ch.deletions) }
            return .init(kind: .edit, icon: "pencil", verb: "Edited", runningVerb: "Editing", target: base ?? "file", fullPath: path, stats: s)
        case "bash", "powershell":
            let cmd = (str("command") ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return .init(kind: .command, icon: "terminal", verb: "Ran", runningVerb: "Running", target: cmd)
        case "grep":
            return .init(kind: .search, icon: "magnifyingglass", verb: "Searched for", runningVerb: "Searching for", target: str("pattern", "query") ?? "")
        case "find":
            return .init(kind: .search, icon: "magnifyingglass", verb: "Found files", runningVerb: "Finding files", target: str("pattern", "query") ?? "")
        case "ls":
            return .init(kind: .list, icon: "folder", verb: "Listed", runningVerb: "Listing", target: base ?? path ?? ".", fullPath: path)
        case "web_search", "fetch_content", "get_search_content", "source_check":
            return .init(kind: .web, icon: "globe", verb: c.name == "web_search" ? "Searched the web" : "Fetched", runningVerb: c.name == "web_search" ? "Searching the web" : "Fetching",
                         target: str("query", "url") ?? (input["queries"]?.array?.first?.string ?? ""))
        case "subagent":
            return .init(kind: .agent, icon: "person.2", verb: "Delegated to", runningVerb: "Delegating to", target: str("agent", "task") ?? "subagent")
        case "agent_send", "agent_request", "list_peers":
            return .init(kind: .agent, icon: "paperplane", verb: c.name == "list_peers" ? "Listed peers" : "Messaged", runningVerb: c.name == "list_peers" ? "Listing peers" : "Messaging",
                         target: str("to") ?? "")
        default:
            if c.name == "mcp" || c.name.hasPrefix("mcp__") {
                return .init(kind: .mcp, icon: "puzzlepiece.extension", verb: "Used", runningVerb: "Using", target: c.name.replacingOccurrences(of: "mcp__", with: "") + (str("tool").map { " · \($0)" } ?? ""))
            }
            return .init(kind: .other, icon: "wrench.and.screwdriver", verb: "Used", runningVerb: "Using", target: c.name)
        }
    }
}

/// Collapsed summary of a work group: "Explored 3 files, ran 2 commands".
func workSummary(_ entries: [WorkEntry]) -> String {
    var reads = 0, edits = 0, cmds = 0, searches = 0, others = 0, thoughts = 0
    var files = Set<String>()
    for e in entries {
        switch e {
        case .thinking: thoughts += 1
        case .tool(let t):
            let p = ToolPresentation.describe(t)
            switch p.kind {
            case .read, .list: reads += 1
            case .edit, .write: if let f = p.fullPath { files.insert(f) } else { edits += 1 }
            case .command: cmds += 1
            case .search, .web: searches += 1
            default: others += 1
            }
        }
    }
    edits += files.count
    var parts: [String] = []
    if reads > 0 { parts.append("explored \(reads) file\(reads == 1 ? "" : "s")") }
    if searches > 0 { parts.append("\(searches) search\(searches == 1 ? "" : "es")") }
    if edits > 0 { parts.append("edited \(edits) file\(edits == 1 ? "" : "s")") }
    if cmds > 0 { parts.append("ran \(cmds) command\(cmds == 1 ? "" : "s")") }
    if others > 0 { parts.append("\(others) other action\(others == 1 ? "" : "s")") }
    if parts.isEmpty { return thoughts > 0 ? "Thought" : "Worked" }
    let s = parts.joined(separator: ", ")
    return s.prefix(1).uppercased() + s.dropFirst()
}

func toolResultText(_ m: Message?) -> String {
    guard let m else { return "" }
    return m.blocks.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n")
}
