import SwiftUI
import PiKit

struct ReviewPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var collapsed: Set<String> = []

    var body: some View {
        let ws = model.workspace
        let git = ws.git
        VStack(spacing: 0) {
            if ws.cwd == nil {
                EmptyState(icon: "folder", title: "No project", text: "Open a thread to review its changes.")
            } else if !git.isRepo {
                EmptyState(icon: "arrow.triangle.branch", title: "Not a Git repository", text: "Review shows uncommitted changes in Git projects.")
            } else if git.files.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "No changes", text: "Everything is committed. Changes made by Pi will show up here.")
            } else {
                HStack(spacing: 8) {
                    Text("\(git.files.count) file\(git.files.count == 1 ? "" : "s") changed").font(.system(size: 13, weight: .semibold))
                    Text("+\(git.additions)").foregroundStyle(Theme.added).font(.system(size: 12.5, weight: .medium))
                    Text("−\(git.deletions)").foregroundStyle(Theme.removed).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button(collapsed.count == git.files.count ? "Expand all" : "Collapse all") {
                        collapsed = collapsed.count == git.files.count ? [] : Set(git.files.map(\.path))
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                    Button { Task { await ws.refreshGit() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(HoverButtonStyle(size: 24)).help("Refresh")
                }.padding(.horizontal, 12).frame(height: 38)
                Divider().opacity(0.6)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(git.files) { f in
                            ReviewFileCard(change: f, root: git.root ?? ws.cwd ?? "", collapsed: collapsed.contains(f.path)) {
                                if collapsed.contains(f.path) { collapsed.remove(f.path) } else { collapsed.insert(f.path) }
                            }
                        }
                    }.padding(12)
                }
            }
        }
        .task(id: ws.cwd) { await ws.refreshGit() }
    }
}

struct ReviewFileCard: View {
    let change: GitChange
    let root: String
    let collapsed: Bool
    let toggle: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        let ws = model.workspace
        let patch = ws.diffs[change.path]
        let lines = patch.map { DiffParser.parseUnified($0) } ?? []
        let add = lines.filter { $0.kind == .add }.count, del = lines.filter { $0.kind == .del }.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary).rotationEffect(.degrees(collapsed ? 0 : 90))
                statusBadge
                Text((change.path as NSString).lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(relative).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                if patch != nil { Text("+\(add)").foregroundStyle(Theme.added); Text("−\(del)").foregroundStyle(Theme.removed) }
                Button { ui.openFile(change.path) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(HoverButtonStyle(size: 22)).help("Open file")
            }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle()).onTapGesture(perform: toggle)
            if !collapsed {
                Divider().opacity(0.6)
                if patch == nil { ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(16) }
                else if lines.isEmpty { Text(change.status == "untracked" ? "New untracked file" : "No textual changes").font(.system(size: 12)).foregroundStyle(.secondary).padding(12) }
                else { DiffView(lines: lines, maxHeight: 420).clipShape(Rectangle()).overlay(Rectangle().strokeBorder(.clear)) }
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.background))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)).hairline()
        .task(id: change.path) { if !collapsed { await ws.loadDiff(change.path) } }
        .onChange(of: collapsed) { _, c in if !c { Task { await ws.loadDiff(change.path) } } }
    }

    private var relative: String {
        let r = root.isEmpty ? "" : (change.path.hasPrefix(root + "/") ? String(change.path.dropFirst(root.count + 1)) : change.path)
        return (r as NSString).deletingLastPathComponent
    }

    private var statusBadge: some View {
        let (txt, color): (String, Color) = switch change.status {
        case "added", "untracked": ("A", Theme.added)
        case "deleted": ("D", Theme.removed)
        case "renamed": ("R", .blue)
        case "conflict": ("!", .orange)
        default: ("M", .orange)
        }
        return Text(txt).font(.system(size: 10, weight: .bold)).foregroundStyle(color).frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)))
    }
}

struct EmptyState: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
