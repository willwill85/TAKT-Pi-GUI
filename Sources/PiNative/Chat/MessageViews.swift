import SwiftUI
import Textual
import PiKit

struct MarkdownText: View {
    let text: String
    var size: CGFloat?
    var cwd: String?
    var sessionId: String?
    var linkPaths = true
    @AppStorage("chatFontSize") private var chatFont = 14.0
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let size = self.size ?? CGFloat(chatFont)
        let loader = PiImageLoader(files: model.files, client: model.client, cwd: cwd ?? model.workspace.cwd, sessionId: sessionId)
        StructuredText(markdown: linkPaths ? PathLinker.linkify(text) : text, syntaxExtensions: [.math])
            .font(.system(size: size))
            .lineSpacing(size * 0.45)
            .textual.structuredTextStyle(.gitHub)
            .textual.imageAttachmentLoader(loader)
            .textual.textSelection(.enabled)
            .handlesPathLinks(cwd: cwd)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UserBubble: View {
    let message: Message
    @State private var hover = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 80)
            if hover {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }.buttonStyle(HoverButtonStyle(size: 24)).help("Copy")
            }
            VStack(alignment: .trailing, spacing: 8) {
                let images = message.blocks.compactMap { b -> ImageRef? in if case .image(let i) = b { return i } else { return nil } }
                if !images.isEmpty {
                    HStack(spacing: 6) { ForEach(Array(images.enumerated()), id: \.offset) { _, img in ImageThumbView(source: .ref(img), width: images.count == 1 ? 280 : 150, maxHeight: images.count == 1 ? 300 : 150) } }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 14)).lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusBubble, style: .continuous).fill(Theme.surface))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct AssistantText: View {
    let text: String
    let live: Bool
    var cwd: String?
    var sessionId: String?
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarkdownText(text: text, cwd: cwd, sessionId: sessionId)
            if !live { ReferencedImages(text: text, cwd: cwd, sessionId: sessionId) }
            if hover && !live {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }.buttonStyle(HoverButtonStyle(size: 24)).help("Copy")
            } else if !live { Color.clear.frame(height: 24) }
        }
        .onHover { hover = $0 }
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.removed)
            Text(text).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.removedBackground))
    }
}

struct WorkedForDivider: View {
    let seconds: Double
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            Text("Worked for \(formatDuration(seconds))").font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize()
            Rectangle().fill(Theme.separator).frame(height: 1)
        }.padding(.vertical, 4)
    }
}

struct ChangesCard: View {
    let files: [FileChange]
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var model
    var body: some View {
        let add = files.reduce(0) { $0 + $1.additions }, del = files.reduce(0) { $0 + $1.deletions }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(files.count) file\(files.count == 1 ? "" : "s") changed").font(.system(size: 13, weight: .medium))
                Text("+\(add)").foregroundStyle(Theme.added).font(.system(size: 12.5, weight: .medium))
                Text("−\(del)").foregroundStyle(Theme.removed).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Button("Review") { ui.showPanel(.review) }
                    .buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.primary)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            ForEach(files.prefix(12)) { f in
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    FileIcon(path: f.path).frame(width: 16)
                    Text((f.path as NSString).lastPathComponent).font(.system(size: 13)).lineLimit(1)
                    Text(shortPath((f.path as NSString).deletingLastPathComponent)).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Text("+\(f.additions)").foregroundStyle(Theme.added); Text("−\(f.deletions)").foregroundStyle(Theme.removed)
                }
                .font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture { ui.openFile(f.path) }
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.surface))
        .hairline()
    }
}

struct FileIcon: View {
    let path: String
    var body: some View {
        let ext = (path as NSString).pathExtension.lowercased()
        let name: String = switch ext {
        case "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go", "java", "c", "cpp", "h", "rb", "sh": "chevron.left.forwardslash.chevron.right"
        case "md", "txt": "doc.text"
        case "json", "yaml", "yml", "toml": "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": "photo"
        case "pdf": "doc.richtext"
        default: "doc"
        }
        Image(systemName: name).font(.system(size: 12)).foregroundStyle(.secondary)
    }
}

struct BashMessageCard: View {
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("$").foregroundStyle(.secondary)
                Text(message.command ?? "").lineLimit(2)
                Spacer()
                if let c = message.exitCode, c != 0 { Text("exit \(c)").foregroundStyle(Theme.removed) }
                if message.cancelled { Text("cancelled").foregroundStyle(.secondary) }
            }.font(Theme.mono(12.5)).padding(.horizontal, 12).padding(.vertical, 8)
            if let out = message.output, !out.isEmpty {
                Divider().opacity(0.5)
                OutputBlock(text: out, maxHeight: 240).padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.codeBackground)).hairline()
    }
}

struct CustomMessageCard: View {
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let t = message.customType { Text(t).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.tertiary) }
            MarkdownText(text: message.text, size: 13)
        }.padding(12).background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface)).hairline()
    }
}

/// Monospaced, scrollable text output (command output, file previews).
struct OutputBlock: View {
    let text: String
    var maxHeight: CGFloat = 260
    @State private var expanded = false
    var body: some View {
        let limit = 20_000
        let long = text.count > limit
        let shown = long && !expanded ? String(text.suffix(limit)) : text
        VStack(alignment: .leading, spacing: 4) {
            if long && !expanded {
                Button("Showing last \(limit / 1000)K of \(text.count / 1000)K characters — show all") { expanded = true }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Color.primary)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(shown).font(Theme.mono(12)).textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: maxHeight)
        }
    }
}
