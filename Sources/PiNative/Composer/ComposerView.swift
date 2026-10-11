import SwiftUI
import UniformTypeIdentifiers
import PiKit

struct CompletionItem: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var insert: String
    var icon: String
    /// Set for a file mention, so the row shows the file-type icon instead of a generic one.
    var path: String? = nil
}

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    let draftKey: String
    let store: SessionStore?
    var placeholder = "Ask Pi anything…   / for commands, @ for files"

    @State private var text = ""
    @State private var caret = 0
    @State private var height: CGFloat = 24
    @State private var attachments: [ImageAttachment] = []
    @State private var selectedCompletion = 0
    /// Set when Escape closes the panel; cleared as soon as the text changes.
    @State private var completionDismissed = false
    @State private var fileIndex: [String] = []
    @State private var fileIndexCwd: String?
    @State private var sending = false
    @State private var historyIndex: Int?
    @State private var dropTargeted = false

    private var cwd: String? { store?.info?.cwd ?? model.newThreadCwd }
    private var isRunning: Bool { store?.isRunning ?? false }
    private var currentModel: ModelRef? { store?.model ?? model.newThreadModel }
    private var currentThinking: String? { store?.thinkingLevel ?? model.newThreadThinking }
    private var canSend: Bool { !(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty) }

    // MARK: Completions
    private static let builtins: [CompletionItem] = [
        .init(id: "b-compact", title: "/compact", detail: "Summarise the conversation to free context", insert: "/compact", icon: "arrow.down.right.and.arrow.up.left"),
        .init(id: "b-auto", title: "/auto-compact", detail: "Toggle automatic compaction", insert: "/auto-compact", icon: "arrow.triangle.2.circlepath"),
        .init(id: "b-reload", title: "/reload", detail: "Reload skills, extensions and commands", insert: "/reload", icon: "arrow.clockwise"),
        .init(id: "b-name", title: "/name", detail: "Rename this thread", insert: "/name ", icon: "pencil"),
        .init(id: "b-session", title: "/session", detail: "Show this thread's id and path", insert: "/session", icon: "info.circle"),
        .init(id: "b-mcp", title: "/mcp", detail: "Show the MCP servers this thread sees", insert: "/mcp", icon: "server.rack"),
        .init(id: "b-copy", title: "/copy", detail: "Copy the last assistant message", insert: "/copy", icon: "doc.on.doc"),
        .init(id: "b-clone", title: "/clone", detail: "Fork this thread", insert: "/clone", icon: "arrow.triangle.branch"),
    ]

    private var completions: [CompletionItem] {
        let upto = String(text.prefix(caret))
        if upto.hasPrefix("/"), !upto.contains(" "), !upto.contains("\n") {
            let q = String(upto.dropFirst()).lowercased()
            let known = (store?.commands.isEmpty == false ? store?.commands : nil) ?? model.slashCommands
            let ext = known.map { CompletionItem(id: "c-" + $0.id, title: "/" + $0.name, detail: $0.description, insert: "/" + $0.name + " ", icon: iconFor($0.source)) }
            let all = Self.builtins + ext
            return Array(all.filter { q.isEmpty || $0.title.lowercased().dropFirst().contains(q) }.prefix(12))
        }
        if let at = upto.lastIndex(of: "@") {
            let token = upto[upto.index(after: at)...]
            let before = upto[..<at]
            if !token.contains(where: \.isWhitespace), (before.isEmpty || before.last!.isWhitespace) {
                let q = String(token).lowercased()
                let matches = fileIndex.filter { q.isEmpty || $0.lowercased().contains(q) }
                    .sorted { rank($0, q) < rank($1, q) }.prefix(10)
                return matches.map { CompletionItem(id: "f-" + $0, title: ($0 as NSString).lastPathComponent, detail: ($0 as NSString).deletingLastPathComponent, insert: "@" + $0 + " ", icon: "", path: $0) }
            }
        }
        return []
    }
    private func rank(_ p: String, _ q: String) -> Int {
        let name = (p as NSString).lastPathComponent.lowercased()
        if q.isEmpty { return p.count }
        if name == q { return 0 }
        if name.hasPrefix(q) { return 1 + p.count / 1000 }
        if name.contains(q) { return 2 }
        return 3
    }
    private func iconFor(_ source: String) -> String { source == "skill" ? "sparkles" : source == "prompt" ? "text.quote" : "terminal" }

    var body: some View {
        VStack(spacing: 8) {
            if let store, !store.queued.isEmpty { QueueStrip(store: store) }
            ZStack(alignment: .bottom) {
                card
                if !completions.isEmpty && !completionDismissed {
                    CompletionList(items: completions, selected: min(selectedCompletion, completions.count - 1)) { accept($0) }
                        .offset(y: -(cardHeight + 8)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: completions.map(\.id)) { _, _ in selectedCompletion = 0 }
            contextRow
        }
        .task { text = DraftStore.shared.get(draftKey); caret = text.count; await loadFileIndex() }
        .onChange(of: text) { _, new in DraftStore.shared.set(draftKey, new); completionDismissed = false }
        .onChange(of: cwd) { _, _ in Task { await loadFileIndex() } }
        .onChange(of: ui.mentionRequest) { _, v in
            guard let v else { return }
            let sep = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
            text += sep + "@" + v + " "; caret = text.count; ui.mentionRequest = nil
        }
        .onChange(of: store?.editorTextRequest) { _, v in if let v { text = v; caret = v.count; store?.editorTextRequest = nil } }
    }

    private var cardHeight: CGFloat { height + 70 + (attachments.isEmpty ? 0 : 76) }

    private var card: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(attachments) { a in AttachmentChip(a: a) { attachments.removeAll { $0.id == a.id } } } }
                        .padding(.horizontal, 14).padding(.top, 12)
                }
            }
            ComposerTextEditor(
                text: $text, height: $height, caret: $caret,
                placeholder: placeholder, enterToSend: ui.enterToSend, focusToken: ui.focusComposer,
                onSubmit: { Task { await submit() } },
                onKey: handleKey,
                onPasteImages: { imgs in imgs.forEach(attach(image:)); return true },
                onPasteFileURLs: { urls in attach(urls: urls); return true })
                .frame(height: height)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            HStack(spacing: 4) {
                attachMenu
                Spacer(minLength: 8)
                modelMenu
                thinkingMenu
                ContextRing(usage: store?.contextUsage).padding(.horizontal, 4)
                sendButton
            }.padding(.horizontal, 10).padding(.bottom, 10)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusComposer, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusComposer, style: .continuous).strokeBorder(dropTargeted ? Color.accentColor : Theme.separator, lineWidth: dropTargeted ? 2 : 1))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 4)
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
    }

    // MARK: Pieces

    private var attachMenu: some View {
        Menu {
            Button("Add photos & files…") { pickFiles() }
            if let store { Button("Compact conversation") { Task { await store.compact() } } }
        } label: { Image(systemName: "plus").font(.system(size: 14, weight: .medium)).frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).frame(width: 28).help("Attach")
    }

    private var modelMenu: some View {
        ModelPickerButton(
            models: model.catalog.models,
            current: currentModel,
            defaultModel: model.catalog.defaultModel,
            price: { model.priceTiers.price($0) },
            tier: { model.priceTiers.tier($0) },
            label: modelLabel,
            onPick: { selectModel($0) },
            onSetDefault: { setDefaultModel($0) })
    }

    private var modelLabel: String {
        guard let m = currentModel else { return "Model" }
        return model.catalog.info(for: m)?.name.replacingOccurrences(of: #" \(.*\)$"#, with: "", options: .regularExpression) ?? m.modelId
    }

    @ViewBuilder private var thinkingMenu: some View {
        let levels = model.catalog.levels(for: currentModel)
        if levels.count > 1 || (levels.count == 1 && levels[0] != "off") {
            Menu {
                ForEach(levels, id: \.self) { l in
                    Button { selectThinking(l) } label: { if l == currentThinking { Label(l.capitalized, systemImage: "checkmark") } else { Text(l.capitalized) } }
                }
            } label: {
                HStack(spacing: 3) {
                    Text((currentThinking ?? "—").capitalized)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 6).frame(height: 26)
            }.menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).fixedSize().help("Reasoning effort")
        }
    }

    private var sendButton: some View {
        Button {
            if isRunning && !canSend { Task { await store?.abort() } } else { Task { await submit() } }
        } label: {
            ZStack {
                Circle().fill(isRunning && !canSend ? Color.primary : (canSend ? Color.accentColor : Color.primary.opacity(0.18)))
                if isRunning && !canSend { RoundedRectangle(cornerRadius: 2).fill(Theme.background).frame(width: 9, height: 9) }
                else { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(canSend ? .white : Color.primary.opacity(0.35)) }
            }.frame(width: 28, height: 28)
        }
        .buttonStyle(.plain).disabled(!canSend && !isRunning)
        .help(isRunning ? (canSend ? "Send as steering message" : "Stop (⌘.)") : "Send (↩)")
        .animation(.easeOut(duration: 0.15), value: isRunning)
    }

    private var contextRow: some View {
        HStack(spacing: 10) {
            if store == nil {
                Chip(action: chooseFolder) { HStack(spacing: 5) { Image(systemName: "folder"); Text(cwd.map { SidebarModel.folderName($0) } ?? "Choose folder") } }
                    .help(cwd ?? "")
            } else if let cwd {
                Chip { HStack(spacing: 5) { Image(systemName: "folder"); Text(SidebarModel.folderName(cwd)) } }.help(cwd)
            }
            if let store { ForEach(store.statuses) { s in Text(s.text).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1) } }
            Spacer()
            if store?.isCompacting == true { Label("Compacting…", systemImage: "arrow.down.right.and.arrow.up.left").font(.system(size: 11.5)).foregroundStyle(.secondary) }
        }.padding(.horizontal, 6).frame(height: 24)
    }

    // MARK: Actions

    private func handleKey(_ k: ComposerKey) -> Bool {
        let items = completions
        if !items.isEmpty {
            switch k {
            case .down: selectedCompletion = (selectedCompletion + 1) % items.count; return true
            case .up: selectedCompletion = (selectedCompletion - 1 + items.count) % items.count; return true
            case .tab, .enter: accept(items[min(selectedCompletion, items.count - 1)]); return true
            case .escape: completionDismissed = true; return true
            }
        }
        if k == .up, text.isEmpty || historyIndex != nil {
            let h = PromptHistory.shared.items
            guard !h.isEmpty else { return false }
            let next = min((historyIndex ?? h.count) - 1, h.count - 1)
            guard next >= 0 else { return true }
            historyIndex = next; text = h[next]; caret = text.count; return true
        }
        if k == .down, let i = historyIndex {
            let h = PromptHistory.shared.items
            if i + 1 < h.count { historyIndex = i + 1; text = h[i + 1] } else { historyIndex = nil; text = "" }
            caret = text.count; return true
        }
        if k == .escape, isRunning { Task { await store?.abort() }; return true }
        return false
    }

    private func accept(_ item: CompletionItem) {
        let upto = String(text.prefix(caret)), rest = String(text.dropFirst(caret))
        var head = upto
        if item.id.hasPrefix("f-"), let at = upto.lastIndex(of: "@") { head = String(upto[..<at]) } else { head = "" }
        text = head + item.insert + rest
        caret = (head + item.insert).count
    }

    /// Handles a built-in slash command. Returns false when the text should be sent to the model instead.
    private func runSlash(_ cmd: String, args: String, store: SessionStore) async -> Bool {
        switch cmd {
        case "compact":
            await store.compact(); model.toast = "Compacting…"
        case "auto-compact":
            do {
                let st = try await model.client?.command(store.sessionId, ["type": "get_state"])
                let next = !(st?["autoCompactionEnabled"]?.bool ?? true)
                try await model.client?.command(store.sessionId, ["type": "set_auto_compaction", "enabled": next])
                model.toast = next ? "Auto-compaction on" : "Auto-compaction off"
            } catch { model.toast = error.localizedDescription }
        case "reload":
            do {
                try await model.client?.command(store.sessionId, ["type": "reload"])
                await store.loadCommands(); await store.refreshState()
                model.toast = "Reloaded"
            } catch { model.toast = error.localizedDescription }
        case "name":
            guard !args.isEmpty else { model.toast = "Usage: /name <name>"; return true }
            await model.rename(store.sessionId, to: args)
        case "session":
            let path = store.info?.path ?? ""
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.sessionId, forType: .string)
            model.toast = path.isEmpty ? "Copied session id" : "Copied id · \(path)"
        case "mcp":
            let servers = store.statuses.filter { $0.key.lowercased().contains("mcp") }
            model.toast = servers.isEmpty ? "No MCP status reported" : servers.map(\.text).joined(separator: " · ")
        case "copy":
            if let t = store.messages.last(where: { $0.role == .assistant })?.text, !t.isEmpty {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string); model.toast = "Copied"
            } else { model.toast = "Nothing to copy yet" }
        case "clone":
            await model.fork(store.sessionId)
        default:
            return false
        }
        return true
    }

    private func setDefaultModel(_ m: ModelRef) {
        guard let client = model.client else { return }
        Task {
            var body: [String: Any] = ["provider": m.provider, "modelId": m.modelId]
            if let cwd { body["cwd"] = cwd }
            do { _ = try await client.send("PUT", "/api/models/default", body: body); model.toast = "Default model saved"; await model.loadModels(cwd: cwd) }
            catch { model.toast = error.localizedDescription }
        }
    }

    private func selectModel(_ m: ModelRef) {
        if let store { Task { await store.setModel(m) } } else {
            model.newThreadModel = m
            let lv = model.catalog.levels(for: m)
            if let t = model.newThreadThinking, !lv.contains(t) { model.newThreadThinking = lv.first(where: { $0 == "medium" }) ?? lv.first }
        }
    }
    private func selectThinking(_ l: String) { if let store { Task { await store.setThinking(l) } } else { model.newThreadThinking = l } }

    private func submit() async {
        let raw = text
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !sending else { return }
        // Built-in slash commands
        if let store, attachments.isEmpty, trimmed.hasPrefix("/") {
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            let cmd = String(parts[0].dropFirst())
            let args = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            if await runSlash(cmd, args: args, store: store) { text = ""; return }
        }
        sending = true; defer { sending = false }
        let imgs = attachments
        text = ""; attachments = []; historyIndex = nil
        PromptHistory.shared.add(trimmed)
        let ok: Bool
        if let store { ok = await store.send(raw, images: imgs, whileRunning: NSEvent.modifierFlags.contains(.option) ? "followUp" : "steer") }
        else { ok = await model.sendFromNewThread(raw, images: imgs) != nil }
        if !ok { text = raw; attachments = imgs }
    }

    private func loadFileIndex() async {
        guard let cwd, cwd != fileIndexCwd, let client = model.client else { return }
        fileIndexCwd = cwd
        if let d = try? await client.get("/api/file-index", query: ["cwd": cwd]) { fileIndex = (d["files"]?.array ?? []).compactMap(\.string) }
    }

    private func pickFiles() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true
        if p.runModal() == .OK { attach(urls: p.urls) }
    }
    private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.directoryURL = cwd.map { URL(fileURLWithPath: $0) }
        if p.runModal() == .OK, let u = p.url { model.newThreadCwd = u.path; Task { await model.loadModels(cwd: u.path) } }
    }

    private func attach(image: NSImage) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        attachments.append(ImageAttachment(mimeType: "image/png", base64: png.base64EncodedString(), name: "Pasted image"))
    }
    private func attach(urls: [URL]) {
        for u in urls {
            let type = UTType(filenameExtension: u.pathExtension)
            if type?.conforms(to: .image) == true, let data = try? Data(contentsOf: u), data.count < 20_000_000 {
                attachments.append(ImageAttachment(mimeType: type?.preferredMIMEType ?? "image/png", base64: data.base64EncodedString(), name: u.lastPathComponent))
            } else {
                let sep = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
                text += sep + "@" + u.path + " "; caret = text.count
            }
        }
    }
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { attach(urls: [url]) } } }
        }
        return handled
    }
}

struct AttachmentChip: View {
    let a: ImageAttachment
    let remove: () -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let d = Data(base64Encoded: a.base64), let img = NSImage(data: d) {
                Image(nsImage: img).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Button(action: remove) { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)) }
                .buttonStyle(.plain).offset(x: 5, y: -5)
        }.padding(.top, 5)
    }
}

struct CompletionList: View {
    let items: [CompletionItem]
    let selected: Int
    let pick: (CompletionItem) -> Void
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        HStack(spacing: 10) {
                            Group { if let path = it.path { FileIcon(path: path) } else { Image(systemName: it.icon).font(.system(size: 12)).foregroundStyle(.secondary) } }.frame(width: 18)
                            Text(it.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(it.detail).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(i == selected ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle()).onTapGesture { pick(it) }.id(it.id)
                    }
                }.padding(5)
            }
            .frame(maxHeight: 280).fixedSize(horizontal: false, vertical: true)
            .onChange(of: selected) { _, s in if items.indices.contains(s) { proxy.scrollTo(items[s].id) } }
        }
        .frame(width: 460)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.separator))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }
}

struct ContextRing: View {
    let usage: ContextUsage?
    var body: some View {
        if let p = usage?.percent, p > 0 {
            let frac = min(1, p / 100)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.2)
                Circle().trim(from: 0, to: frac).stroke(frac > 0.85 ? Theme.removed : frac > 0.65 ? Theme.warning : Color.secondary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round)).rotationEffect(.degrees(-90))
            }.frame(width: 15, height: 15)
                .help("Context \(Int(p))% used" + (usage?.contextWindow.map { " of \($0 / 1000)K" } ?? ""))
        }
    }
}

struct QueueStrip: View {
    let store: SessionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Queued").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.tertiary)
                Spacer()
                Button("Clear") { Task { await store.clearQueue() } }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(Array((store.queued.steering.map { ("Steer", $0) } + store.queued.followUp.map { ("Follow-up", $0) }).enumerated()), id: \.offset) { _, q in
                HStack(spacing: 8) {
                    Text(q.0).font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.primary.opacity(0.08)))
                    Text(q.1).font(.system(size: 12.5)).lineLimit(1).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 8).cardSurface().hairline()
    }
}

/// The model selector: a searchable list grouped by provider, with the price tier and a star for the
/// default. A native menu cannot hold a search field, so this is its own panel.
struct ModelPickerButton: View {
    let models: [ModelInfo]
    let current: ModelRef?
    let defaultModel: ModelRef?
    let price: (String) -> ModelPrice?
    let tier: (String) -> Int?
    let label: String
    let onPick: (ModelRef) -> Void
    let onSetDefault: (ModelRef) -> Void

    @State private var open = false
    @State private var query = ""

    private var filtered: [ModelInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return models }
        return models.filter { $0.name.lowercased().contains(q) || $0.modelId.lowercased().contains(q) || $0.provider.lowercased().contains(q) }
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 3) {
                Text(label).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 6).frame(height: 26)
        }
        .buttonStyle(.plain).help("Model")
        .popover(isPresented: $open, arrowEdge: .top) { panel }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.tertiary)
                TextField("Search models", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain) }
            }.padding(.horizontal, 10).frame(height: 34)
            Divider().opacity(0.6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groups = Dictionary(grouping: filtered, by: \.provider)
                    ForEach(groups.keys.sorted(), id: \.self) { p in
                        Text(p).font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                        ForEach(groups[p] ?? []) { m in row(m) }
                    }
                    if filtered.isEmpty { Text("No matching models").font(.system(size: 12.5)).foregroundStyle(.tertiary).padding(16) }
                }.padding(.bottom, 6)
            }.frame(maxHeight: 360)
        }
        .frame(width: 360)
        .onExitCommand { open = false }
    }

    private func row(_ m: ModelInfo) -> some View {
        let ref = ModelRef(provider: m.provider, modelId: m.modelId)
        let selected = ref == current
        let isDefault = ref == defaultModel
        return HStack(spacing: 8) {
            Group {
                if selected { Image(systemName: "checkmark") }
                else if let t = tier(m.id) { Image(systemName: "circle.fill").foregroundStyle(Theme.priceColor(t)) }
                else { Image(systemName: "circle").foregroundStyle(.quaternary) }
            }.font(.system(size: 10)).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 13)).lineLimit(1)
                if let p = price(m.id) { Text(priceText(p)).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Button { onSetDefault(ref) } label: {
                Image(systemName: isDefault ? "star.fill" : "star").font(.system(size: 11)).foregroundStyle(isDefault ? Theme.warning : Color.secondary.opacity(0.5))
            }.buttonStyle(.plain).help(isDefault ? "Default for new threads" : "Make default for new threads")
        }
        .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
        .background(selected ? Color.primary.opacity(0.06) : .clear)
        .onTapGesture { onPick(ref); open = false; query = "" }
    }
}
