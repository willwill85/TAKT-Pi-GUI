import SwiftUI
import PiKit

struct WorkGroupView: View {
    let entries: [WorkEntry]
    let live: Bool
    @State private var expanded: Bool
    @State private var userToggled = false

    init(entries: [WorkEntry], live: Bool) {
        self.entries = entries; self.live = live
        _expanded = State(initialValue: live)
    }

    private var currentStep: String {
        for e in entries.reversed() {
            switch e {
            case .tool(let t) where t.isRunning:
                let p = ToolPresentation.describe(t); return "\(p.runningVerb) \(p.target)"
            case .thinking(_, _, let l) where l: return "Thinking"
            default: continue
            }
        }
        return "Working"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                userToggled = true
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if live { SpinnerView(size: 10) }
                    Text(live ? currentStep + "…" : workSummary(entries))
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        .modifier(ShimmerIf(active: live))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { e in
                        switch e {
                        case .thinking(_, let text, let l): ThinkingRow(text: text, live: l)
                        case .tool(let t): ToolRow(entry: t)
                        }
                    }
                }
                .padding(.leading, 4).padding(.top, 4)
                .transition(.opacity)
            }
        }
        .onChange(of: live) { _, nowLive in
            if !nowLive && !userToggled { withAnimation(.snappy(duration: 0.2)) { expanded = false } }
            if nowLive && !userToggled { expanded = true }
        }
    }
}

struct ShimmerIf: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        if active {
            content.overlay(
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.primary.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.5).offset(x: phase * g.size.width * 1.5)
                        .blendMode(.sourceAtop)
                }.mask(content)
            )
            .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 } }
        } else { content }
    }
}

struct ThinkingRow: View {
    let text: String
    let live: Bool
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.snappy(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain").font(.system(size: 11.5)).frame(width: 16).foregroundStyle(.tertiary)
                    Text(live ? "Thinking…" : "Thought").font(.system(size: 13)).foregroundStyle(.secondary)
                    if !open && !live {
                        Text(text.replacingOccurrences(of: "\n", with: " ").prefix(80)).font(.system(size: 12.5)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.frame(height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open || live {
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).textSelection(.enabled)
                    .lineSpacing(3).padding(.leading, 24).padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ToolRow: View {
    let entry: ToolEntry
    @Environment(UIState.self) private var ui
    @State private var open = false

    var body: some View {
        let p = ToolPresentation.describe(entry)
        let failed = entry.result?.isError == true
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.snappy(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: failed ? "xmark.circle.fill" : p.icon).font(.system(size: 11.5)).frame(width: 16)
                        .foregroundStyle(failed ? Theme.removed : Color.secondary)
                    Text(entry.isRunning ? p.runningVerb : p.verb).font(.system(size: 13)).foregroundStyle(.secondary)
                    targetView(p)
                    if let s = p.stats, !entry.isRunning {
                        Text("+\(s.add)").foregroundStyle(Theme.added).font(.system(size: 12))
                        if s.del > 0 { Text("−\(s.del)").foregroundStyle(Theme.removed).font(.system(size: 12)) }
                    }
                    if entry.isRunning { SpinnerView(size: 9) }
                    Spacer(minLength: 0)
                    if let d = entry.result?.durationMs, d >= 1000 { Text(formatDuration(d / 1000)).font(.system(size: 11.5)).foregroundStyle(.tertiary) }
                }.frame(height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open || (failed && !entry.isRunning) {
                ToolDetails(entry: entry, presentation: p).padding(.leading, 24).padding(.bottom, 6).transition(.opacity)
            }
        }
    }

    @ViewBuilder private func targetView(_ p: ToolPresentation) -> some View {
        if let path = p.fullPath {
            Text(p.target).font(.system(size: 12.5, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                .lineLimit(1).onTapGesture { ui.openFile(path) }.help(path)
        } else if p.kind == .command {
            Text(p.target).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.primary.opacity(0.8)).lineLimit(1)
        } else {
            Text(p.target).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85)).lineLimit(1)
        }
    }
}

struct ToolDetails: View {
    let entry: ToolEntry
    let presentation: ToolPresentation

    var body: some View {
        let c = entry.call
        let input = (c.input.object ?? [:]).isEmpty ? (c.rawInput.flatMap(PartialJSON.parse) ?? c.input) : c.input
        let out = toolResultText(entry.result)
        VStack(alignment: .leading, spacing: 8) {
            switch presentation.kind {
            case .command:
                VStack(alignment: .leading, spacing: 0) {
                    Text("$ " + (input["command"]?.string ?? "")).font(Theme.mono(12)).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    if !out.isEmpty { Divider().opacity(0.5); OutputBlock(text: out).padding(10) }
                }.background(RoundedRectangle(cornerRadius: 8).fill(Theme.codeBackground)).hairline(radius: 8)
            case .edit:
                if let diff = entry.result?.details?["diff"]?.string {
                    DiffView(lines: DiffParser.parsePiDiff(diff))
                } else if let edits = input["edits"]?.array ?? (input["oldText"] != nil ? [input] : nil) {
                    ForEach(Array(edits.enumerated()), id: \.offset) { _, e in
                        DiffView(lines: simpleDiff(old: e["oldText"]?.string ?? "", new: e["newText"]?.string ?? ""))
                    }
                }
                if entry.result?.isError == true { Text(out).font(.system(size: 12)).foregroundStyle(Theme.removed).textSelection(.enabled) }
            case .write:
                if let content = input["content"]?.string { OutputBlock(text: content, maxHeight: 280).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Theme.codeBackground)).hairline(radius: 8) }
            case .read:
                if !out.isEmpty { OutputBlock(text: out, maxHeight: 280).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Theme.codeBackground)).hairline(radius: 8) }
            default:
                if !(input.object ?? [:]).isEmpty {
                    OutputBlock(text: input.serialized(pretty: true), maxHeight: 160).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Theme.codeBackground)).hairline(radius: 8)
                }
                if !out.isEmpty { OutputBlock(text: out, maxHeight: 280).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Theme.codeBackground)).hairline(radius: 8) }
            }
            ForEach(Array((entry.result?.blocks ?? []).enumerated()), id: \.offset) { _, b in
                if case .image(let img) = b { ImageThumb(image: img, size: 220) }
            }
        }
    }

    private func simpleDiff(old: String, new: String) -> [DiffLine] {
        var out: [DiffLine] = []
        var i = 0
        for l in old.split(separator: "\n", omittingEmptySubsequences: false) { out.append(DiffLine(id: i, kind: .del, number: "", text: String(l))); i += 1 }
        for l in new.split(separator: "\n", omittingEmptySubsequences: false) { out.append(DiffLine(id: i, kind: .add, number: "", text: String(l))); i += 1 }
        return out
    }
}
