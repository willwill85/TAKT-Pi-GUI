import Foundation

public struct SessionFamily: Identifiable, Hashable, Sendable {
    public var id: String { root.id }
    public var root: SessionInfo
    public var children: [SessionInfo]
    public var pinnedAt: Double?
    public var archived: Bool
    public var latest: Date
    public var all: [SessionInfo] { [root] + children }
}

public struct ProjectGroup: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public var key: String
    public var root: String
    public var name: String
    public var pinned: Bool
    public var families: [SessionFamily]
}

public struct SidebarModel: Sendable {
    public var pinnedFamilies: [SessionFamily] = []
    public var projects: [ProjectGroup] = []
    public var archived: [SessionFamily] = []

    public static func folderName(_ root: String) -> String {
        let n = (root as NSString).lastPathComponent
        return n.isEmpty ? root : n
    }

    /// Groups sessions like `lib/session-tree.ts`: families (subagents nest under
    /// their parent), pinned section, project groups ordered by `projectOrder`.
    public static func build(sessions: [SessionInfo], ui: SessionUiState, running: Set<String>) -> SidebarModel {
        let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var childrenOf: [String: [SessionInfo]] = [:]
        var roots: [SessionInfo] = []
        for s in sessions {
            if s.relation?.kind == .subagent, let p = s.relation?.parentSessionId, byId[p] != nil {
                childrenOf[p, default: []].append(s)
            } else {
                roots.append(s)
            }
        }
        var model = SidebarModel()
        var byProject: [String: [SessionFamily]] = [:]
        var rootOfProject: [String: String] = [:]
        for r in roots {
            let kids = (childrenOf[r.id] ?? []).sorted { $0.modified > $1.modified }
            let latest = ([r] + kids).map(\.modified).max() ?? r.modified
            let isRunning = running.contains(r.id) || kids.contains { running.contains($0.id) }
            let fam = SessionFamily(
                root: r, children: kids, pinnedAt: ui.pinnedAt[r.id],
                archived: ui.archivedAt[r.id] != nil && !isRunning, latest: latest)
            if fam.archived { model.archived.append(fam); continue }
            if fam.pinnedAt != nil { model.pinnedFamilies.append(fam) }
            else {
                byProject[r.projectKey, default: []].append(fam)
                rootOfProject[r.projectKey] = r.projectRoot
            }
        }
        model.pinnedFamilies.sort { ($0.pinnedAt ?? 0) > ($1.pinnedAt ?? 0) }
        model.archived.sort { (ui.archivedAt[$0.id] ?? 0) > (ui.archivedAt[$1.id] ?? 0) }

        var groups: [ProjectGroup] = byProject.map { key, fams in
            ProjectGroup(
                key: key, root: rootOfProject[key] ?? key,
                name: ui.projectNames[key] ?? folderName(rootOfProject[key] ?? key),
                pinned: ui.projectPinnedAt[key] != nil,
                families: fams.sorted { $0.latest > $1.latest })
        }
        // Order: saved `projectOrder` first (pinned band before the rest); unseen keys by recency, on top of their band.
        let rank = Dictionary(ui.projectOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func newest(_ g: ProjectGroup) -> Date { g.families.first?.latest ?? .distantPast }
        groups.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            switch (rank[a.key], rank[b.key]) {
            case let (x?, y?): return x < y
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return newest(a) > newest(b)
            }
        }
        model.projects = groups
        return model
    }
}

/// Whether a project section is unfolded in the sidebar.
///
/// Folding is always the user's own choice: a tag filter only narrows which projects and threads are
/// listed, it never forces sections open (otherwise the fold button would do nothing while a tag is selected).
public func isProjectExpanded(key: String, expanded: Set<String>, tagFilterActive: Bool) -> Bool {
    expanded.contains(key)
}
