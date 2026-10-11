import Foundation
import AppKit
import Observation

// MARK: - Files

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDir: Bool
    public var hidden: String?
    public var linkTarget: String?
}

public struct TextChunk: Sendable {
    public var content: String
    public var nextOffset: Int
    public var truncated: Bool
    public var language: String
    public var size: Int
}

public struct FileMeta: Sendable {
    public var size: Int
    public var language: String
    public var mime: String
    public var previewKind: String?
}

public enum FileClass: Sendable {
    case text, image, pdf, markdown, csv, docx, media, binary
    public static func of(path: String, mime: String? = nil) -> FileClass {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "heic", "tiff", "avif": return .image
        case "pdf": return .pdf
        case "md", "mdx", "markdown": return .markdown
        case "csv", "tsv": return .csv
        case "docx": return .docx
        case "mp4", "mov", "webm", "mp3", "wav", "m4a", "ogg", "flac": return .media
        case "zip", "gz", "tar", "dmg", "exe", "bin", "o", "a", "dylib", "so", "class", "jar", "woff", "woff2", "ttf", "otf": return .binary
        default: return .text
        }
    }
}

/// Reads files through the server (respecting its allowed roots), or straight from
/// disk when the server runs on this Mac.
public final class FileService: @unchecked Sendable {
    let client: APIClient
    public init(client: APIClient) { self.client = client }

    public var isLocal: Bool {
        let h = client.endpoint.baseURL.host ?? ""
        return h == "127.0.0.1" || h == "localhost" || h == "::1"
    }

    func apiPath(_ path: String) -> String {
        "/api/files" + (path.hasPrefix("/") ? path : "/" + path)
    }

    public func list(_ dir: String, showHidden: Bool = false) async throws -> [FileEntry] {
        let d = try await client.get(apiPath(dir), query: ["type": "list"] .merging(showHidden ? ["hidden": "1"] : [:]) { a, _ in a })
        return (d["entries"]?.array ?? []).compactMap { j in
            guard let n = j["name"]?.string else { return nil }
            return FileEntry(name: n, path: (dir as NSString).appendingPathComponent(n), isDir: j["isDir"]?.bool ?? false,
                             hidden: j["hidden"]?.string, linkTarget: j["linkTarget"]?.string)
        }
    }

    public func meta(_ path: String, sessionId: String? = nil) async throws -> FileMeta {
        var q = ["type": "meta"]; if let sessionId { q["sessionId"] = sessionId }
        let d = try await client.get(apiPath(path), query: q)
        return FileMeta(size: d["size"]?.int ?? 0, language: d["language"]?.string ?? "text", mime: d["mime"]?.string ?? "text/plain", previewKind: d["previewKind"]?.string)
    }

    public func readText(_ path: String, offset: Int = 0, sessionId: String? = nil) async throws -> TextChunk {
        var q = ["type": "read", "offset": String(offset)]; if let sessionId { q["sessionId"] = sessionId }
        let d = try await client.get(apiPath(path), query: q)
        return TextChunk(content: d["content"]?.string ?? "", nextOffset: d["nextOffset"]?.int ?? 0, truncated: d["truncated"]?.bool ?? false,
                         language: d["language"]?.string ?? "text", size: d["size"]?.int ?? 0)
    }

    /// Raw bytes (images, PDFs, docx…). Prefers disk when the server is on this Mac.
    public func data(_ path: String, sessionId: String? = nil) async throws -> Data {
        if isLocal, FileManager.default.isReadableFile(atPath: path) { return try Data(contentsOf: URL(fileURLWithPath: path)) }
        var q = ["type": "download"]; if let sessionId { q["sessionId"] = sessionId }
        return try await client.raw("GET", apiPath(path), query: q)
    }

    public func fileExists(_ path: String) -> Bool { isLocal && FileManager.default.fileExists(atPath: path) }

    public func upload(_ urls: [URL], to dir: String) async throws {
        let boundary = "pinative-" + UUID().uuidString
        var body = Data()
        for u in urls {
            guard let d = try? Data(contentsOf: u) else { continue }
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(u.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(d); body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        try await client.raw("POST", apiPath(dir), query: ["type": "upload", "conflict": "rename"], body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }
}

// MARK: - Image cache

@MainActor
public final class ImageCache {
    public static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    public func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    public func load(key: String, _ fetch: @escaping @Sendable () async -> Data?) async -> NSImage? {
        if let c = cache.object(forKey: key as NSString) { return c }
        if let t = inflight[key] { return await t.value }
        let t = Task<NSImage?, Never> { @MainActor in
            guard let data = await fetch(), let img = NSImage(data: data) else { return nil }
            return img
        }
        inflight[key] = t
        let img = await t.value
        inflight[key] = nil
        if let img { cache.setObject(img, forKey: key as NSString, cost: Int(img.size.width * img.size.height * 4)) }
        return img
    }
}

// MARK: - Git

public struct GitStatus: Sendable {
    public var isRepo = false
    public var root: String?
    public var files: [GitChange] = []
    public var additions = 0
    public var deletions = 0
}
public struct GitChange: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var status: String
    public var code: String
}

public struct WorktreeEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var branch: String?
    public var isMain: Bool
}
public struct WorktreeContext: Sendable {
    public var projectRoot: String
    public var projectKey: String
    public var isGit: Bool
    public var currentPath: String?
    public var worktrees: [WorktreeEntry]
}

public struct GitService: Sendable {
    let client: APIClient
    public init(client: APIClient) { self.client = client }

    public func status(cwd: String) async -> GitStatus {
        guard let d = try? await client.get("/api/git/status", query: ["cwd": cwd]) else { return GitStatus() }
        var s = GitStatus()
        s.isRepo = d["isGitRepository"]?.bool ?? false
        s.root = d["repositoryRoot"]?.string
        s.additions = d["additions"]?.int ?? 0; s.deletions = d["deletions"]?.int ?? 0
        s.files = (d["files"]?.array ?? []).compactMap { j in
            guard let p = j["filePath"]?.string else { return nil }
            return GitChange(path: p, status: j["status"]?.string ?? "modified", code: j["code"]?.string ?? "M")
        }
        return s
    }

    public func diff(cwd: String, path: String) async -> String? {
        guard let d = try? await client.get("/api/git/diff", query: ["cwd": cwd, "path": path]) else { return nil }
        return d["patch"]?.string
    }

    public func worktrees(cwd: String) async -> WorktreeContext? {
        guard let d = try? await client.get("/api/worktrees", query: ["cwd": cwd]) else { return nil }
        return WorktreeContext(
            projectRoot: d["projectRoot"]?.string ?? cwd, projectKey: d["projectKey"]?.string ?? cwd,
            isGit: d["isGit"]?.bool ?? false, currentPath: d["currentWorktreePath"]?.string,
            worktrees: (d["worktrees"]?.array ?? []).compactMap { j in
                guard let p = j["path"]?.string else { return nil }
                return WorktreeEntry(path: p, branch: j["branch"]?.string, isMain: j["isMain"]?.bool ?? false)
            })
    }

    public func addWorktree(cwd: String, branch: String) async throws -> String? {
        let d = try await client.post("/api/worktrees", body: ["cwd": cwd, "branch": branch])
        return d["path"]?.string
    }

    public func removeWorktree(cwd: String, path: String, force: Bool) async throws {
        _ = try await client.send("DELETE", "/api/worktrees", body: ["cwd": cwd, "path": path, "force": force])
    }
}

// MARK: - Tags

public struct ProjectTag: Identifiable, Hashable, Sendable {
    public var id: String; public var name: String; public var color: String
}

public struct TagState: Sendable {
    public var tags: [ProjectTag] = []
    public var projectAssignments: [String: [String]] = [:]
    public var sessionAssignments: [String: [String]] = [:]
    public init() {}
    public init(json d: JSON) {
        tags = (d["tags"]?.array ?? []).compactMap { j in
            guard let id = j["id"]?.string, let n = j["name"]?.string else { return nil }
            return ProjectTag(id: id, name: n, color: j["color"]?.string ?? "#7c8cff")
        }
        for (k, v) in d["assignments"]?.object ?? [:] { projectAssignments[k] = (v.array ?? []).compactMap(\.string) }
        for (k, v) in d["sessionAssignments"]?.object ?? [:] { sessionAssignments[k] = (v.array ?? []).compactMap(\.string) }
    }
    public func tag(_ id: String) -> ProjectTag? { tags.first { $0.id == id } }
    public func tags(forProject key: String) -> [ProjectTag] { (projectAssignments[key] ?? []).compactMap(tag) }
    public func tags(forSession id: String) -> [ProjectTag] { (sessionAssignments[id] ?? []).compactMap(tag) }
}

// MARK: - Cron / daemons

public struct CronJob: Identifiable, Hashable, Sendable {
    public var id: String
    public var daemonId: String
    public var schedule: String
    public var prompt: String
    public var enabled: Bool
    public var tz: String
    public var lastRun: Date?
    public var lastStatus: String?
    public var nextRun: Date?
    public init(id: String, daemonId: String, schedule: String, prompt: String, enabled: Bool, tz: String, lastRun: Date?, lastStatus: String?, nextRun: Date?) {
        self.id = id; self.daemonId = daemonId; self.schedule = schedule; self.prompt = prompt; self.enabled = enabled; self.tz = tz; self.lastRun = lastRun; self.lastStatus = lastStatus; self.nextRun = nextRun
    }
}
public struct Daemon: Identifiable, Hashable, Sendable {
    public var id: String; public var cwd: String; public var name: String; public var state: String
    public init(id: String, cwd: String, name: String, state: String) { self.id = id; self.cwd = cwd; self.name = name; self.state = state }
}

// MARK: - Terminal

@MainActor
@Observable
public final class TerminalSession: Identifiable {
    public let id: String
    public let cwd: String
    public var title: String
    public private(set) var exited = false
    public var onOutput: ((String) -> Void)?
    private let client: APIClient
    private var task: Task<Void, Never>?
    private var buffer = ""
    private var lastOffset = 0

    public init(id: String, cwd: String, client: APIClient) {
        self.id = id; self.cwd = cwd; self.client = client
        self.title = (cwd as NSString).lastPathComponent
    }

    public static func create(cwd: String, cols: Int, rows: Int, client: APIClient) async throws -> TerminalSession {
        let tid = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let r = try await client.post("/api/terminal", body: ["id": tid, "cwd": cwd, "cols": cols, "rows": rows])
        return TerminalSession(id: r["id"]?.string ?? tid, cwd: cwd, client: client)
    }

    public func attach() {
        guard task == nil else { return }
        let id = id, client = client
        task = Task { [weak self] in
            var after = 0
            while !Task.isCancelled {
                do {
                    let stream = client.events("/api/terminal/\(id)/events", query: after > 0 ? ["after": String(after)] : [:])
                    for try await ev in stream {
                        guard let self else { return }
                        switch ev["type"]?.string {
                        case "output":
                            let data = ev["data"]?.string ?? ""
                            after = ev["offset"]?.int ?? after
                            if ev["reset"]?.bool == true { self.onOutput?("\u{1b}c") }
                            self.deliver(data)
                        case "exit", "closed": self.exited = true; return
                        default: break
                        }
                    }
                } catch { if Task.isCancelled { return } }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func deliver(_ s: String) {
        if let o = onOutput { o(s) } else { buffer += s }
    }

    public func setOutputHandler(_ h: @escaping (String) -> Void) {
        onOutput = h
        if !buffer.isEmpty { h(buffer); buffer = "" }
    }

    public func send(_ data: String) {
        let id = id, client = client
        Task { _ = try? await client.post("/api/terminal/\(id)", body: ["type": "input", "data": data]) }
    }
    public func resize(cols: Int, rows: Int) {
        let id = id, client = client
        guard cols >= 2, rows >= 2 else { return }
        Task { _ = try? await client.post("/api/terminal/\(id)", body: ["type": "resize", "cols": cols, "rows": rows]) }
    }
    public func close() {
        task?.cancel(); task = nil
        let id = id, client = client
        Task { _ = try? await client.send("DELETE", "/api/terminal/\(id)") }
    }
}
