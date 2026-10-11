import SwiftUI
import AppKit
import Textual
import PiKit

// MARK: - Lightbox

struct LightboxItem: Identifiable {
    let id = UUID()
    var image: NSImage
    var title: String
    var path: String?
}

/// Where an image comes from: inline data, a file on disk / behind the server, or a URL.
enum ImageSource: Hashable {
    case ref(ImageRef)
    case path(String, sessionId: String?)
    case url(URL)

    var key: String {
        switch self {
        case .ref(let r): return "ref:\(r.data?.prefix(64) ?? "")\(r.data?.count ?? 0)\(r.url ?? "")"
        case .path(let p, _): return "path:" + p
        case .url(let u): return "url:" + u.absoluteString
        }
    }
    var title: String {
        switch self {
        case .ref: return "Image"
        case .path(let p, _): return (p as NSString).lastPathComponent
        case .url(let u): return u.lastPathComponent
        }
    }
    var filePath: String? { if case .path(let p, _) = self { return p } else { return nil } }
}

@MainActor
func loadImage(_ source: ImageSource, files: FileService?, client: APIClient?) async -> NSImage? {
    if let c = ImageCache.shared.cached(source.key) { return c }
    return await ImageCache.shared.load(key: source.key) {
        switch source {
        case .ref(let r):
            if let d = r.data { return Data(base64Encoded: d) }
            if let u = r.url, let client {
                if u.hasPrefix("http"), let url = URL(string: u) { return try? await URLSession.shared.data(from: url).0 }
                return try? await client.raw("GET", u)
            }
            return nil
        case .path(let p, let sid): return try? await files?.data(p, sessionId: sid)
        case .url(let u):
            if u.isFileURL { return try? Data(contentsOf: u) }
            return try? await URLSession.shared.data(from: u).0
        }
    }
}

struct LoadedImage<Content: View, Placeholder: View>: View {
    let source: ImageSource
    @ViewBuilder var content: (NSImage) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { content(image) } else { placeholder().overlay(failed ? AnyView(Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.tertiary)) : AnyView(ProgressView().controlSize(.small))) }
        }
        .task(id: source) {
            if let c = ImageCache.shared.cached(source.key) { image = c; return }
            let img = await loadImage(source, files: model.files, client: model.client)
            image = img; failed = img == nil
        }
    }
}

/// A clickable thumbnail that opens the lightbox.
struct ImageThumbView: View {
    let source: ImageSource
    var width: CGFloat = 220
    var maxHeight: CGFloat = 260
    var caption: Bool = false
    @Environment(UIState.self) private var ui
    @State private var hover = false

    var body: some View {
        LoadedImage(source: source) { img in
            let ratio = img.size.height > 0 ? img.size.width / img.size.height : 1
            let w = min(width, max(60, img.size.width))
            let h = min(maxHeight, w / max(ratio, 0.05))
            VStack(alignment: .leading, spacing: 4) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: min(w, h * ratio), height: h).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.separator))
                    .overlay(alignment: .topTrailing) {
                        if hover { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold)).padding(5).background(.regularMaterial, in: Circle()).padding(6) }
                    }
                    .onHover { hover = $0 }
                    .onTapGesture { ui.lightbox = LightboxItem(image: img, title: source.title, path: source.filePath) }
                    .help("Click to preview")
                if caption { Text(source.title).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1) }
            }
        } placeholder: {
            RoundedRectangle(cornerRadius: 10).fill(Theme.surface).frame(width: 120, height: 90)
        }
    }
}

struct LightboxView: View {
    let item: LightboxItem
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var fit = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("\(Int(item.image.size.width))×\(Int(item.image.size.height))").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Button { fit.toggle(); zoom = 1 } label: { Image(systemName: fit ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }.help(fit ? "Actual size" : "Fit")
                Button { zoom = min(8, zoom * 1.25); fit = false } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
                Button { zoom = max(0.1, zoom / 1.25); fit = false } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
                Divider().frame(height: 16)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([item.image]) } label: { Image(systemName: "doc.on.doc") }.help("Copy image")
                Button(action: save) { Image(systemName: "square.and.arrow.down") }.help("Save…")
                if let p = item.path { Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } label: { Image(systemName: "folder") }.help("Reveal in Finder") }
                Button { dismiss() } label: { Image(systemName: "xmark") }.keyboardShortcut(.cancelAction).help("Close (Esc)")
            }.buttonStyle(HoverButtonStyle()).padding(.horizontal, 14).frame(height: 44)
            Divider()
            GeometryReader { g in
                ScrollView([.horizontal, .vertical]) {
                    let base = item.image.size
                    let scale = fit ? min(1, min((g.size.width - 40) / max(base.width, 1), (g.size.height - 40) / max(base.height, 1))) : zoom
                    Image(nsImage: item.image).resizable().interpolation(.high)
                        .frame(width: base.width * scale, height: base.height * scale)
                        .padding(20).frame(minWidth: g.size.width, minHeight: g.size.height)
                }
            }
            .background(Color.black.opacity(0.04))
        }
        .frame(minWidth: 640, idealWidth: 900, minHeight: 480, idealHeight: 640)
    }

    private func save() {
        let p = NSSavePanel(); p.nameFieldStringValue = item.title.contains(".") ? item.title : item.title + ".png"
        guard p.runModal() == .OK, let url = p.url, let tiff = item.image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        let ext = url.pathExtension.lowercased()
        let data = ext == "jpg" || ext == "jpeg" ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) : rep.representation(using: .png, properties: [:])
        try? data?.write(to: url)
    }
}

// MARK: - Markdown image attachments (Textual)

struct PiImageAttachment: Attachment {
    let box: ImageBox
    let text: String
    var description: String { text }
    let sourceKey: String

    var body: some View { InlineImageBody(box: box, title: text) }

    func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        let size = box.image.size
        let maxW = min(proposal.width ?? size.width, 520)
        let w = min(maxW, size.width)
        return CGSize(width: w, height: w * size.height / max(size.width, 1))
    }
    func pngData() -> Data? {
        guard let tiff = box.image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
    static func == (a: Self, b: Self) -> Bool { a.sourceKey == b.sourceKey && a.text == b.text }
    func hash(into h: inout Hasher) { h.combine(sourceKey); h.combine(text) }
}

final class ImageBox: @unchecked Sendable { let image: NSImage; init(_ i: NSImage) { image = i } }

struct InlineImageBody: View {
    let box: ImageBox
    let title: String
    @Environment(UIState.self) private var ui
    var body: some View {
        Image(nsImage: box.image).resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.separator))
            .onTapGesture { ui.lightbox = LightboxItem(image: box.image, title: title.isEmpty ? "Image" : title, path: nil) }
    }
}

struct PiImageLoader: AttachmentLoader {
    let files: FileService?
    let client: APIClient?
    let cwd: String?
    let sessionId: String?

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> PiImageAttachment {
        var source: ImageSource
        if url.scheme == "http" || url.scheme == "https" { source = .url(url) }
        else {
            var p = url.isFileURL ? url.path : (url.absoluteString.removingPercentEncoding ?? url.path)
            if p.hasPrefix("~") { p = NSHomeDirectory() + p.dropFirst() }
            if !p.hasPrefix("/"), let cwd { p = (cwd as NSString).appendingPathComponent(p) }
            source = .path((p as NSString).standardizingPath, sessionId: sessionId)
        }
        guard let img = await loadImage(source, files: files, client: client) else { throw URLError(.fileDoesNotExist) }
        return PiImageAttachment(box: ImageBox(img), text: text, sourceKey: source.key)
    }
}

// MARK: - Image paths mentioned in assistant text

enum ImagePathScanner {
    private static let regex = try! NSRegularExpression(pattern: #"(?:(?<=[\s`"'(\[])|^)((?:~|\.{0,2})?/?[\w@%+=:,.~\-/\u{4e00}-\u{9fff} ]*?[\w\-\u{4e00}-\u{9fff}]\.(?:png|jpe?g|gif|webp|bmp|heic|svg))(?=$|[\s`"')\]:,;!?])"#, options: [.caseInsensitive])
    /// Absolute / `~` / relative image paths mentioned in `text` (not inside http URLs).
    static func paths(in text: String) -> [String] {
        var found: [String] = []
        let ns = text as NSString
        for line in text.split(separator: "\n") {
            let l = String(line)
            let lns = l as NSString
            for m in regex.matches(in: l, range: NSRange(location: 0, length: lns.length)) {
                var p = lns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if p.contains("://") || p.hasPrefix("//") { continue }
                // Greedy spaces: keep only the part after the last whitespace unless the path starts with / or ~.
                if !(p.hasPrefix("/") || p.hasPrefix("~")) , let sp = p.lastIndex(of: " ") { p = String(p[p.index(after: sp)...]) }
                if !found.contains(p) { found.append(p) }
            }
        }
        _ = ns
        return Array(found.prefix(8))
    }
}

/// Thumbnails for local images the assistant refers to in its reply.
struct ReferencedImages: View {
    let text: String
    let cwd: String?
    let sessionId: String?
    @Environment(AppModel.self) private var model
    @State private var resolved: [String] = []

    var body: some View {
        Group {
            if !resolved.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(resolved, id: \.self) { p in ImageThumbView(source: .path(p, sessionId: sessionId), width: 240, maxHeight: 200, caption: true) }
                    }
                }
            }
        }
        .task(id: text) {
            let candidates = ImagePathScanner.paths(in: text).map { model.workspace.resolveFor(cwd: cwd, $0) }
            var ok: [String] = []
            for p in candidates {
                if let f = model.files, f.fileExists(p) { ok.append(p) }
                else if let f = model.files, !f.isLocal, (try? await f.meta(p, sessionId: sessionId)) != nil { ok.append(p) }
            }
            resolved = ok
        }
    }
}

extension WorkspaceModel {
    func resolveFor(cwd: String?, _ raw: String) -> String {
        var p = raw
        if p.hasPrefix("~") { p = NSHomeDirectory() + p.dropFirst() }
        if !p.hasPrefix("/"), let base = cwd ?? self.cwd { p = (base as NSString).appendingPathComponent(p) }
        return (p as NSString).standardizingPath
    }
}
