import SwiftUI
import PiKit

/// Turns path-looking inline code (`src/a.ts:12`, `docs/`, `/Users/me/x.png`) into links
/// the app handles itself (pinative-path://…). Skips fenced code.
enum PathLinker {
    static let scheme = "pinative-path"
    private static let ext = "swift|ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|c|cc|cpp|h|hpp|cs|m|mm|sh|zsh|bash|sql|json|jsonl|yaml|yml|toml|xml|html|htm|css|scss|md|mdx|txt|csv|tsv|log|env|lock|png|jpe?g|gif|webp|svg|pdf|docx?|xlsx?|pptx?|zip|ini|conf|cfg|plist|gradle|vue|svelte|astro|php|lua|dart|ex|exs|zig|nix|tf|proto|graphql|gql|prisma|dockerfile|makefile"
    private static let pathRegex = try! NSRegularExpression(pattern: "^(?:~|\\.{1,2})?/?[\\w@%+=,.~\\-\\u{4e00}-\\u{9fff}]+(?:/[\\w@%+=,.~\\-\\u{4e00}-\\u{9fff} ]+)*/?(?::\\d+(?::\\d+)?)?$")
    private static let extRegex = try! NSRegularExpression(pattern: "\\.(?:\(ext))(?::\\d+(?::\\d+)?)?$", options: .caseInsensitive)
    private static let codeSpan = try! NSRegularExpression(pattern: "(?<!`)`([^`\\n]+)`(?!`)")

    static func looksLikePath(_ s: String) -> Bool {
        guard s.count >= 2, s.count < 300, !s.contains("://"), !s.hasPrefix("-"), !s.hasPrefix("$"), !s.contains(" ") || s.hasPrefix("/") else { return false }
        let r = NSRange(location: 0, length: (s as NSString).length)
        guard pathRegex.firstMatch(in: s, range: r) != nil else { return false }
        let hasSlash = s.contains("/")
        let hasExt = extRegex.firstMatch(in: s, range: r) != nil
        if hasExt { return true }
        // Folder-looking: has a slash, no dots-only segments like "a/b" used as ratios.
        return hasSlash && (s.hasSuffix("/") || s.hasPrefix("/") || s.hasPrefix("~") || s.hasPrefix("./") || s.hasPrefix("../") || s.split(separator: "/").count >= 2) && !s.contains("*")
    }

    static func linkify(_ md: String) -> String {
        var out: [String] = []
        var inFence = false
        for line in md.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") || line.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") { inFence.toggle(); out.append(line); continue }
            if inFence || !line.contains("`") { out.append(line); continue }
            let ns = line as NSString
            var result = ""; var last = 0
            for m in codeSpan.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let content = ns.substring(with: m.range(at: 1))
                // Already inside a markdown link label? `[`x`](…)` — leave alone.
                let before = ns.substring(to: m.range.location)
                let after = ns.substring(from: NSMaxRange(m.range))
                if before.hasSuffix("[") && after.hasPrefix("](") { continue }
                guard looksLikePath(content), let url = encode(content) else { continue }
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                result += "[`\(content)`](\(url))"
                last = NSMaxRange(m.range)
            }
            result += ns.substring(from: last)
            out.append(result)
        }
        return out.joined(separator: "\n")
    }

    static func encode(_ raw: String) -> String? {
        var p = raw, line: Int?
        if let r = p.range(of: #":\d+(?::\d+)?$"#, options: .regularExpression) {
            line = Int(p[r].dropFirst().split(separator: ":").first ?? "")
            p = String(p[..<r.lowerBound])
        }
        guard let enc = p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return "\(scheme)://open?p=\(enc.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? enc)" + (line.map { "&l=\($0)" } ?? "")
    }

    static func decode(_ url: URL) -> (path: String, line: Int?)? {
        guard url.scheme == scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let p = c.queryItems?.first(where: { $0.name == "p" })?.value?.removingPercentEncoding else { return nil }
        return (p, c.queryItems?.first(where: { $0.name == "l" })?.value.flatMap(Int.init))
    }
}

/// Opens a path the way chat links do: folders list in the Files panel, files open in a tab.
@MainActor
func openPathFromChat(_ raw: String, line: Int? = nil, cwd: String?, model: AppModel, ui: UIState) {
    let ws = model.workspace
    var p = raw
    if p.hasPrefix("file://"), let u = URL(string: p) { p = u.path }
    if p.hasPrefix("~") { p = NSHomeDirectory() + p.dropFirst() }
    if !p.hasPrefix("/"), let base = cwd ?? ws.cwd { p = (base as NSString).appendingPathComponent(p) }
    p = (p as NSString).standardizingPath
    Task {
        var isDir = false
        var exists = false
        if let f = model.files, f.isLocal {
            var d: ObjCBool = false
            exists = FileManager.default.fileExists(atPath: p, isDirectory: &d); isDir = d.boolValue
        } else if let f = model.files {
            if (try? await f.meta(p)) != nil { exists = true } else if (try? await f.list(p)) != nil { exists = true; isDir = true }
        }
        guard exists else { model.toast = "Not found: \(shortPath(p))"; return }
        if isDir {
            ws.expanded.insert(p); await ws.loadDir(p)
            if ui.filePlacement == .panel { ui.showPanel(.files) }
            else { ui.filesSectionCollapsed = false }
            ws.reveal(p)
        } else {
            ui.openFile(p, line: line)
            ws.reveal(p)
        }
    }
}

struct PathLinkHandler: ViewModifier {
    let cwd: String?
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            if let (p, l) = PathLinker.decode(url) { openPathFromChat(p, line: l, cwd: cwd, model: model, ui: ui); return .handled }
            if url.scheme == nil || url.scheme == "file" { openPathFromChat(url.isFileURL ? url.path : url.absoluteString.removingPercentEncoding ?? url.path, cwd: cwd, model: model, ui: ui); return .handled }
            return .systemAction
        })
    }
}
extension View { func handlesPathLinks(cwd: String?) -> some View { modifier(PathLinkHandler(cwd: cwd)) } }
