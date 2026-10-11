import SwiftUI
import PiKit

struct DiffLine: Identifiable {
    enum Kind { case add, del, context, gap }
    let id: Int
    var kind: Kind
    var number: String
    var text: String
}

enum DiffParser {
    /// pi's edit diff: `+ 12 text`, `- 12 text`, `  12 text`, `   ...`.
    static func parsePiDiff(_ diff: String) -> [DiffLine] {
        var out: [DiffLine] = []
        for (i, raw) in diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            guard let first = line.first else { continue }
            let rest = line.dropFirst()
            let kind: DiffLine.Kind = first == "+" ? .add : first == "-" ? .del : .context
            let trimmed = rest.drop(while: { $0 == " " })
            if trimmed.hasPrefix("...") && kind == .context { out.append(DiffLine(id: i, kind: .gap, number: "", text: "")); continue }
            let digits = trimmed.prefix(while: { $0.isNumber })
            let after = trimmed.dropFirst(digits.count)
            let text = after.hasPrefix(" ") ? String(after.dropFirst()) : String(after)
            out.append(DiffLine(id: i, kind: kind, number: String(digits), text: text))
        }
        return out
    }

    /// Standard unified diff (git diff) → lines (headers skipped).
    static func parseUnified(_ diff: String) -> [DiffLine] {
        var out: [DiffLine] = []
        var oldN = 0, newN = 0
        for (i, raw) in diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            if line.hasPrefix("@@") {
                // @@ -a,b +c,d @@
                let nums = line.split(separator: " ")
                if nums.count >= 3 {
                    oldN = Int(nums[1].dropFirst().split(separator: ",").first ?? "0") ?? 0
                    newN = Int(nums[2].dropFirst().split(separator: ",").first ?? "0") ?? 0
                }
                out.append(DiffLine(id: i, kind: .gap, number: "", text: line))
            } else if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file") || line.hasPrefix("\\") {
                continue
            } else if line.hasPrefix("+") {
                out.append(DiffLine(id: i, kind: .add, number: String(newN), text: String(line.dropFirst()))); newN += 1
            } else if line.hasPrefix("-") {
                out.append(DiffLine(id: i, kind: .del, number: String(oldN), text: String(line.dropFirst()))); oldN += 1
            } else if !line.isEmpty || oldN > 0 {
                out.append(DiffLine(id: i, kind: .context, number: String(newN), text: line.hasPrefix(" ") ? String(line.dropFirst()) : line)); oldN += 1; newN += 1
            }
        }
        return out
    }
}

struct DiffView: View {
    let lines: [DiffLine]
    var maxHeight: CGFloat? = 320
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { l in
                    HStack(alignment: .top, spacing: 0) {
                        Text(l.number).frame(width: 40, alignment: .trailing).foregroundStyle(.tertiary).padding(.trailing, 6)
                        Text(sign(l.kind)).frame(width: 14).foregroundStyle(color(l.kind))
                        Text(l.kind == .gap && l.text.isEmpty ? "⋯" : l.text.isEmpty ? " " : l.text)
                            .foregroundStyle(l.kind == .gap ? Color.secondary : Color.primary)
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                    .font(Theme.mono(12))
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bg(l.kind))
                }
            }.padding(.vertical, 4).frame(minWidth: 0, alignment: .leading)
        }
        .frame(maxHeight: maxHeight)
        .background(Theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .hairline(radius: 8)
    }
    private func sign(_ k: DiffLine.Kind) -> String { k == .add ? "+" : k == .del ? "−" : "" }
    private func color(_ k: DiffLine.Kind) -> Color { k == .add ? Theme.added : k == .del ? Theme.removed : .secondary }
    private func bg(_ k: DiffLine.Kind) -> Color { k == .add ? Theme.addedBackground : k == .del ? Theme.removedBackground : .clear }
}
