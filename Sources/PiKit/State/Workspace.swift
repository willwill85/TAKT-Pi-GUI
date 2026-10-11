import Foundation
import Observation

public struct OpenFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var line: Int?
    public var name: String { (path as NSString).lastPathComponent }
}

public enum PanelTab: Hashable, Sendable {
    case review, files, terminal, browser
    case file(String)
    case subagent(String)
}

/// Everything behind the right-hand panel: file tree, open files, git review, terminals.
@MainActor
@Observable
public final class WorkspaceModel {
    public private(set) var cwd: String?
    public private(set) var entries: [String: [FileEntry]] = [:]
    public var expanded: Set<String> = []
    public var showHidden = false { didSet { Task { await reloadTree() } } }
    public private(set) var treeError: String?
    public var openFiles: [OpenFile] = []
    public var tab: PanelTab = .review
    public private(set) var git = GitStatus() { didSet { rebuildGitIndex() } }

    /// Git changes keyed by absolute path (git reports paths relative to the repo root).
    /// Built once per git change, never per row: tree rows read it on every render.
    public private(set) var gitStatusByAbsolutePath: [String: GitChange] = [:]
    /// Directories (absolute) that contain at least one changed file.
    public private(set) var changedDirectoryPaths: Set<String> = []

    /// Test seam: applies a git status as `refreshGit` would.
    public func testSetGit(_ s: GitStatus) { git = s }

    private func rebuildGitIndex() {
        guard let root = git.root ?? cwd, !git.files.isEmpty else {
            if !gitStatusByAbsolutePath.isEmpty { gitStatusByAbsolutePath = [:] }
            if !changedDirectoryPaths.isEmpty { changedDirectoryPaths = [] }
            return
        }
        var byPath: [String: GitChange] = [:]
        byPath.reserveCapacity(git.files.count)
        var dirs: Set<String> = []
        for c in git.files {
            byPath[root + "/" + c.path] = c
            var dir = (c.path as NSString).deletingLastPathComponent
            while !dir.isEmpty && dir != "." {
                // Parents of an already-registered directory are registered too, so stop at the first hit.
                if !dirs.insert(root + "/" + dir).inserted { break }
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        gitStatusByAbsolutePath = byPath
        changedDirectoryPaths = dirs
    }
    public private(set) var worktree: WorktreeContext?
    public var reviewSelection: String?
    public private(set) var diffs: [String: String] = [:]
    public private(set) var terminals: [TerminalSession] = []
    public var activeTerminal: String?
    public var sessionId: String?

    private var client: APIClient?
    private var files: FileService?
    private var gitService: GitService?
    private var gitTask: Task<Void, Never>?
    private var parked: [String: (open: [OpenFile], tab: PanelTab, expanded: Set<String>)] = [:]

    public init() {}

    public func configure(client: APIClient?) {
        guard let client else { self.client = nil; files = nil; gitService = nil; return }
        self.client = client
        files = FileService(client: client)
        gitService = GitService(client: client)
    }

    public var fileService: FileService? { files }
    public var gitSvc: GitService? { gitService }

    // MARK: Project switching

    public func setCwd(_ new: String?) {
        guard new != cwd else { return }
        if let old = cwd { parked[old] = (openFiles, tab, expanded) }
        cwd = new
        entries = [:]; diffs = [:]; git = GitStatus(); worktree = nil; reviewSelection = nil
        if let new, let p = parked[new] { openFiles = p.open; tab = p.tab; expanded = p.expanded } else { openFiles = []; expanded = []; if case .file = tab { tab = .review } }
        gitTask?.cancel()
        guard new != nil else { return }
        Task { await reloadTree(); await refreshGit() }
        gitTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await self?.refreshGit()
            }
        }
    }

    // MARK: Tree

    public func reloadTree() async {
        guard let cwd, let files else { return }
        var dirs = [cwd] + Array(expanded)
        dirs = Array(Set(dirs))
        for d in dirs {
            do { entries[d] = try await files.list(d, showHidden: showHidden); if d == cwd { treeError = nil } }
            catch { if d == cwd { treeError = error.localizedDescription }; if d != cwd { expanded.remove(d) } }
        }
    }

    public func loadDir(_ dir: String) async {
        guard let files else { return }
        do { entries[dir] = try await files.list(dir, showHidden: showHidden) } catch { entries[dir] = [] }
    }

    public func toggle(_ dir: String) {
        if expanded.contains(dir) { expanded.remove(dir) } else { expanded.insert(dir); Task { await loadDir(dir) } }
    }

    /// Expands every ancestor of `path` below the cwd so it is visible in the tree.
    public func reveal(_ path: String) {
        guard let cwd, path.hasPrefix(cwd) else { return }
        var dir = (path as NSString).deletingLastPathComponent
        while dir.count > cwd.count, dir.hasPrefix(cwd) {
            if !expanded.contains(dir) { expanded.insert(dir); Task { await loadDir(dir) } }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    // MARK: Files

    public func resolve(_ raw: String) -> String {
        var p = raw
        if p.hasPrefix("file://"), let u = URL(string: p) { p = u.path }
        if p.hasPrefix("~") { p = NSHomeDirectory() + p.dropFirst() }
        if !p.hasPrefix("/"), let cwd { p = (cwd as NSString).appendingPathComponent(p) }
        return (p as NSString).standardizingPath
    }

    public func open(_ path: String, line: Int? = nil) {
        let p = resolve(path)
        if let i = openFiles.firstIndex(where: { $0.path == p }) { openFiles[i].line = line ?? openFiles[i].line }
        else { openFiles.append(OpenFile(path: p, line: line)) }
        tab = .file(p)
    }

    public func close(_ path: String) {
        openFiles.removeAll { $0.path == path }
        if tab == .file(path) { tab = openFiles.last.map { .file($0.path) } ?? .files }
    }

    // MARK: Git

    public func refreshGit() async {
        guard let cwd, let gitService else { return }
        let s = await gitService.status(cwd: cwd)
        guard self.cwd == cwd else { return }
        if s.files != git.files || s.isRepo != git.isRepo || s.additions != git.additions || s.deletions != git.deletions {
            // changed files may have new diffs
            if s.files != git.files { diffs = [:] }
            git = s
        }
        if worktree == nil || worktree?.projectRoot == nil { worktree = await gitService.worktrees(cwd: cwd) }
    }

    public func refreshWorktrees() async {
        guard let cwd, let gitService else { return }
        worktree = await gitService.worktrees(cwd: cwd)
    }

    public func loadDiff(_ path: String) async {
        guard let cwd, let gitService, diffs[path] == nil else { return }
        diffs[path] = await gitService.diff(cwd: cwd, path: path) ?? ""
    }

    // MARK: Terminals

    public func newTerminal() async {
        guard let cwd, let client else { return }
        do {
            let t = try await TerminalSession.create(cwd: cwd, cols: 100, rows: 28, client: client)
            terminals.append(t); activeTerminal = t.id; tab = .terminal
        } catch {}
    }

    public func closeTerminal(_ id: String) {
        terminals.first { $0.id == id }?.close()
        terminals.removeAll { $0.id == id }
        if activeTerminal == id { activeTerminal = terminals.last?.id }
    }
}
