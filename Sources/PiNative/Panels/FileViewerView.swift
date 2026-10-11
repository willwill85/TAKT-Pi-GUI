import SwiftUI
import PDFKit
import AVKit
import PiKit
import Textual

struct FileViewerView: View {
    let file: OpenFile
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var state: LoadState = .loading
    @State private var wrap = false
    @State private var markdownRendered = true
    @State private var lastSize = -1

    enum LoadState {
        case loading
        case text(String, language: String, truncated: Bool)
        case image(NSImage)
        case pdf(Data)
        case csv(String)
        case docx(NSAttributedString)
        case media(URL)
        case unsupported(String)
        case failed(String)
    }

    var body: some View {
        let cls = FileClass.of(path: file.path)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FileIcon(path: file.path)
                Text(shortPath(file.path)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head).help(file.path)
                Spacer()
                if cls == .markdown { Picker("", selection: $markdownRendered) { Text("Preview").tag(true); Text("Source").tag(false) }.pickerStyle(.segmented).frame(width: 130).labelsHidden() }
                if case .text = state { Toggle(isOn: $wrap) { Image(systemName: "text.word.spacing") }.toggleStyle(.button).buttonStyle(HoverButtonStyle()).help("Wrap lines") }
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.path, forType: .string) } label: { Image(systemName: "link") }.help("Copy path")
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) } label: { Image(systemName: "folder") }.help("Reveal in Finder")
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) } label: { Image(systemName: "arrow.up.forward.square") }.help("Open with default app")
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
            }.buttonStyle(HoverButtonStyle(size: 24)).padding(.horizontal, 10).frame(height: 34)
            Divider().opacity(0.6)
            content(cls)
        }
        .task(id: file.path) { await load(); await watch() }
    }

    @ViewBuilder private func content(_ cls: FileClass) -> some View {
        switch state {
        case .loading: ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let m): Message(icon: "exclamationmark.triangle", text: m)
        case .unsupported(let m): Message(icon: "doc", text: m, action: ("Open with default app", { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }))
        case .text(let t, let lang, let truncated):
            if cls == .markdown && markdownRendered {
                ScrollView { MarkdownText(text: t, size: 13.5).padding(20).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity) }
            } else {
                VStack(spacing: 0) {
                    CodeTextView(text: t, language: lang, wrap: wrap, scrollToLine: file.line)
                    if truncated { Text("File truncated for preview").font(.system(size: 11.5)).foregroundStyle(.secondary).padding(6) }
                }
            }
        case .image(let img):
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: max(img.size.width, 200), maxHeight: .infinity).padding(16)
                    .onTapGesture { ui.lightbox = LightboxItem(image: img, title: file.name, path: file.path) }
            }
        case .pdf(let d): PDFRepresentable(data: d)
        case .csv(let t): CSVTableView(text: t, delimiter: file.path.lowercased().hasSuffix(".tsv") ? "\t" : ",")
        case .docx(let a): ScrollView { Text(AttributedString(a)).textSelection(.enabled).padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity) }
        case .media(let u): MediaPlayerView(url: u).id(u)
        }
    }

    private func load() async {
        guard let files = model.files else { return }
        let sid = model.workspace.sessionId
        do {
            switch FileClass.of(path: file.path) {
            case .image:
                if file.path.lowercased().hasSuffix(".svg") { // NSImage renders SVG on macOS 14+
                    let d = try await files.data(file.path, sessionId: sid)
                    if let i = NSImage(data: d) { state = .image(i) } else { state = .unsupported("This SVG can't be previewed.") }
                } else {
                    let d = try await files.data(file.path, sessionId: sid)
                    if let i = NSImage(data: d) { state = .image(i) } else { state = .unsupported("Unsupported image format.") }
                }
            case .pdf: state = .pdf(try await files.data(file.path, sessionId: sid))
            case .docx:
                let d = try await files.data(file.path, sessionId: sid)
                if let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) { state = .docx(a) }
                else { state = .unsupported("This document can't be previewed.") }
            case .media:
                if files.isLocal { state = .media(URL(fileURLWithPath: file.path)) }
                else { state = .unsupported("Media preview needs a local server.") }
            case .binary: state = .unsupported("No preview for this file type.")
            case .text, .markdown, .csv:
                var out = ""; var offset = 0; var lang = "text"; var truncated = false
                for _ in 0..<8 {
                    let c = try await files.readText(file.path, offset: offset, sessionId: sid)
                    out += c.content; lang = c.language; offset = c.nextOffset; lastSize = c.size
                    if !c.truncated { break }
                    truncated = true
                }
                if FileClass.of(path: file.path) == .csv { state = .csv(out) } else { state = .text(out, language: lang, truncated: truncated && out.utf8.count < lastSize) }
            }
        } catch { state = .failed(error.localizedDescription) }
    }

    /// Reload when the file changes on disk.
    private func watch() async {
        guard let files = model.files else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.5))
            if let m = try? await files.meta(file.path), m.size != lastSize, lastSize >= 0 { await load() }
        }
    }
}

private struct Message: View {
    let icon: String, text: String
    var action: (String, () -> Void)?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary)
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action { Button(action.0, action: action.1).controlSize(.small) }
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PDFRepresentable: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.displayMode = .singlePageContinuous; v.displaysPageBreaks = true
        v.document = PDFDocument(data: data); return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}

struct CSVTableView: View {
    let text: String
    let delimiter: Character
    var body: some View {
        let rows = parse()
        let cols = rows.map(\.count).max() ?? 0
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(rows.prefix(2000).enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 0) {
                        Text("\(i + 1)").font(Theme.mono(10.5)).foregroundStyle(.tertiary).frame(width: 36, alignment: .trailing).padding(.trailing, 6)
                        ForEach(0..<cols, id: \.self) { c in
                            Text(c < r.count ? r[c] : "").font(.system(size: 12, weight: i == 0 ? .semibold : .regular)).lineLimit(1)
                                .frame(width: 150, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 4)
                                .overlay(alignment: .trailing) { Rectangle().fill(Theme.separator).frame(width: 1) }
                        }
                    }
                    .background(i == 0 ? Theme.surface : (i % 2 == 0 ? Color.primary.opacity(0.02) : .clear))
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
                }
            }
        }
    }

    private func parse() -> [[String]] {
        var rows: [[String]] = []; var row: [String] = []; var field = ""; var inQ = false
        let chars = Array(text)
        var i = 0
        while i < chars.count && rows.count < 5000 {
            let ch = chars[i]
            if inQ {
                if ch == "\"" { if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQ = false } } else { field.append(ch) }
            } else if ch == "\"" { inQ = true }
            else if ch == delimiter { row.append(field); field = "" }
            else if ch == "\n" || ch == "\r\n" { row.append(field); field = ""; rows.append(row); row = [] }
            else if ch == "\r" { }
            else { field.append(ch) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

/// Plays a local audio or video file. The AVPlayer is created once per URL and held in state; building
/// `VideoPlayer(player: AVPlayer(url:))` inline made a new player on every view update, and AVKit's
/// SwiftUI bridge crashed while instantiating its metadata on macOS 27.
struct MediaPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                NativeVideoView(player: player)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .onAppear { if player == nil { player = AVPlayer(url: url) } }
        .onDisappear { player?.pause(); player = nil }
    }
}

/// AppKit's AVPlayerView, used directly so AVKit's SwiftUI bridge is not involved at all.
struct NativeVideoView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}
