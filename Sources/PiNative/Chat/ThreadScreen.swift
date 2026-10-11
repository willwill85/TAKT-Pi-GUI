import SwiftUI
import PiKit

struct ThreadScreen: View {
    let store: SessionStore
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 0) {
            ThreadHeader(store: store)
            MessageList(store: store)
            BottomArea(store: store)
        }
        .sheet(item: Binding(get: { store.dialogs.first }, set: { _ in })) { req in
            ExtensionDialog(store: store, request: req)
        }
    }
}

struct BottomArea: View {
    let store: SessionStore
    @AppStorage("chatWidth") private var chatWidth = 760.0
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.notices) { n in NoticeBar(notice: n) { store.dismissNotice(n.id) } }
            if let r = store.retry {
                BannerPill(icon: "arrow.clockwise", text: "Retrying (\(r.attempt)/\(r.maxAttempts))" + (r.message.map { " — \($0)" } ?? ""), tint: Theme.warning)
            }
            ForEach(store.widgets.filter { $0.placement != "belowEditor" }) { w in WidgetView(widget: w) }
            ComposerView(draftKey: store.sessionId, store: store)
            ForEach(store.widgets.filter { $0.placement == "belowEditor" }) { w in WidgetView(widget: w) }
        }
        .frame(maxWidth: CGFloat(chatWidth))
        .padding(.horizontal, 24).padding(.bottom, 12).padding(.top, 4)
        .frame(maxWidth: .infinity)
    }
}

struct NoticeBar: View {
    let notice: Notice
    let dismiss: () -> Void
    var body: some View {
        BannerPill(icon: notice.kind == .error ? "exclamationmark.circle.fill" : notice.kind == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill",
                   text: notice.text, tint: notice.kind == .error ? Theme.removed : notice.kind == .warning ? Theme.warning : .secondary, onClose: dismiss)
    }
}

struct BannerPill: View {
    let icon: String, text: String, tint: Color
    var onClose: (() -> Void)?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 12.5)).lineLimit(3).textSelection(.enabled)
            Spacer(minLength: 0)
            if let onClose { Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.tertiary) }
        }.padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.10)))
    }
}

struct WidgetView: View {
    let widget: WidgetItem
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(widget.lines.enumerated()), id: \.offset) { _, l in Text(l).font(Theme.mono(11.5)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }
}

struct ThreadHeader: View {
    let store: SessionStore
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var renaming = false
    @State private var nameDraft = ""

    var body: some View {
        let title = (model.sessions.first { $0.id == store.sessionId } ?? store.info)?.title ?? "Thread"
        let ws = model.workspace
        HStack(spacing: 8) {
            if !ui.sidebarVisible {
                Button { withAnimation(.snappy(duration: 0.22)) { ui.sidebarVisible = true } } label: { Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundStyle(.secondary) }
                    .buttonStyle(HoverButtonStyle()).help("Show sidebar (⌘B)").padding(.leading, 74)
            }
            Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                .onTapGesture(count: 2) { nameDraft = title; renaming = true }
            if let cwd = store.info?.cwd {
                Text(SidebarModel.folderName(cwd)).font(.system(size: 12.5)).foregroundStyle(.tertiary).lineLimit(1).help(cwd)
            }
            ForEach(model.tagState.tags(forSession: store.sessionId).prefix(3)) { TagChip(tag: $0, small: true) }
            if store.isRunning { SpinnerView(size: 11) }
            Spacer()
            if let w = ws.worktree, w.isGit, let cur = w.worktrees.first(where: { $0.path == w.currentPath }) ?? w.worktrees.first {
                Chip { HStack(spacing: 4) { Image(systemName: "arrow.triangle.branch").foregroundStyle(cur.isMain ? Color.secondary : Color.primary); Text(cur.branch ?? "detached").font(.system(size: 12, design: .monospaced)) } }
                    .help(w.currentPath ?? "")
            }
            if let cwd = store.info?.cwd {
                Menu {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)]) }
                    Button("Open in Terminal") { NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration()) }
                    Button("Open in VS Code") { if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") { NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) } }
                } label: { Image(systemName: "arrow.up.forward.app").font(.system(size: 13)).frame(width: 26, height: 26) }.menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).frame(width: 30).help("Open in…")
            }
            Button { ui.showPanel(.terminal) } label: { Image(systemName: "terminal").font(.system(size: 13.5)).foregroundStyle(ws.tab == .terminal && ui.rightPanelVisible ? Color.primary : .secondary) }
                .buttonStyle(HoverButtonStyle()).help("Terminal")
            Button { ui.showPanel(.review) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plusminus.circle").font(.system(size: 13.5))
                    if !ws.git.files.isEmpty { Text("+\(ws.git.additions)").foregroundStyle(Theme.added); Text("−\(ws.git.deletions)").foregroundStyle(Theme.removed) }
                }.font(.system(size: 12, weight: .medium)).foregroundStyle(ws.tab == .review && ui.rightPanelVisible ? Color.primary : .secondary).padding(.horizontal, 4)
            }.buttonStyle(HoverButtonStyle()).help("Review changes")
            Menu {
                Button("Rename…") { nameDraft = title; renaming = true }
                Button("Fork") { Task { await model.fork(store.sessionId) } }
                Button("Generate Title") { Task { await model.autoName(store.sessionId) } }
                Divider()
                Button("Conversation Tree…") { ui.activeSheet = .sessionTree(store.sessionId) }
                Button("System Prompt & Tools…") { ui.activeSheet = .systemPrompt(store.sessionId) }
                if let key = (model.sessions.first { $0.id == store.sessionId })?.projectKey { Button("Project Settings…") { ui.activeSheet = .projectSettings(key) } }
                if !model.tagState.tags.isEmpty {
                    Menu("Tags") {
                        ForEach(model.tagState.tags) { t in
                            Toggle(t.name, isOn: Binding(get: { model.tagState.sessionAssignments[store.sessionId]?.contains(t.id) ?? false }, set: { _ in Task { await model.toggleSessionTag(store.sessionId, tag: t.id) } }))
                        }
                    }
                }
                Divider()
                Button("Copy Session ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.sessionId, forType: .string) }
                Button("Export as HTML…") { exportHTML() }
            } label: { Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 26, height: 26) }
                .menuStyle(.borderlessButton).tint(.secondary).menuIndicator(.hidden).frame(width: 30)
            Button { withAnimation(.snappy(duration: 0.22)) { ui.rightPanelVisible.toggle() } } label: { Image(systemName: "sidebar.right").font(.system(size: 14)).foregroundStyle(ui.rightPanelVisible ? Color.primary : .secondary) }
                .buttonStyle(HoverButtonStyle()).help("Toggle side panel (⌥⌘B)")
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(WindowDragArea())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .alert("Rename thread", isPresented: $renaming) {
            TextField("Name", text: $nameDraft)
            Button("Rename") { let n = nameDraft; Task { await model.rename(store.sessionId, to: n) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func exportHTML() {
        guard let client = model.client else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "thread.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { if let d = try? await client.raw("GET", "/api/sessions/\(store.sessionId)/export") { try? d.write(to: url); NSWorkspace.shared.open(url) } }
    }
}

struct MessageList: View {
    let store: SessionStore
    @AppStorage("chatWidth") private var chatWidth = 760.0
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true

    var body: some View {
        let items = TurnBuilder.build(messages: store.messages, streaming: store.streaming.message, isRunning: store.isRunning, liveResults: store.liveToolResults)
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.hasMore {
                        Button { Task { await store.loadOlder() } } label: {
                            HStack(spacing: 6) { if store.isLoading { SpinnerView(size: 10) }; Text("Load earlier messages") }.font(.system(size: 12.5)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                    ForEach(items) { item in ItemView(item: item, cwd: store.info?.cwd, sessionId: store.sessionId) }
                    if store.isRunning && store.streaming.message == nil && showWaiting(items) {
                        HStack(spacing: 8) { SpinnerView(size: 11); Text(phaseLabel).font(.system(size: 13)).foregroundStyle(.secondary).modifier(ShimmerIf(active: true)) }.id("waiting")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: CGFloat(chatWidth))
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: Bool.self) { g in g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 60 } action: { _, v in atBottom = v }
            .onChange(of: items.count) { _, _ in if atBottom { position.scrollTo(edge: .bottom) } }
            .onChange(of: store.streaming) { _, _ in if atBottom { position.scrollTo(edge: .bottom) } }
            .onChange(of: store.liveToolResults.count) { _, _ in if atBottom { position.scrollTo(edge: .bottom) } }
            .onChange(of: store.sessionId) { _, _ in position.scrollTo(edge: .bottom) }

            if !atBottom {
                Button { withAnimation { position.scrollTo(edge: .bottom) } } label: {
                    Image(systemName: "arrow.down").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                        .background(Circle().fill(.regularMaterial)).overlay(Circle().strokeBorder(Theme.separator))
                }.buttonStyle(.plain).padding(.bottom, 10).transition(.scale.combined(with: .opacity)).help("Jump to latest")
            }
            if store.isLoading && store.messages.isEmpty { ProgressView().controlSize(.small).frame(maxHeight: .infinity) }
        }
        .onAppear { position.scrollTo(edge: .bottom) }
    }

    private func showWaiting(_ items: [ThreadItem]) -> Bool {
        if case .work(_, _, let live)? = items.last, live { return false }
        return true
    }
    private var phaseLabel: String {
        switch store.phase {
        case .runningCommand: return "Running command…"
        case .runningTools(let t): return t.first.map { "Running \($0.name)…" } ?? "Working…"
        default: return store.isCompacting ? "Compacting…" : "Thinking…"
        }
    }
}

struct ItemView: View {
    let item: ThreadItem
    var cwd: String?
    var sessionId: String?
    var body: some View {
        switch item {
        case .user(let m): UserBubble(message: m).padding(.top, 6)
        case .text(_, let t, let live, _): AssistantText(text: t, live: live, cwd: cwd, sessionId: sessionId)
        case .work(_, let entries, let live): WorkGroupView(entries: entries, live: live)
        case .bash(let m): BashMessageCard(message: m)
        case .custom(let m): CustomMessageCard(message: m)
        case .error(_, let t): ErrorBanner(text: t)
        case .workedFor(_, let s): WorkedForDivider(seconds: s)
        case .changes(_, let files): ChangesCard(files: files)
        }
    }
}

struct ExtensionDialog: View {
    let store: SessionStore
    let request: ExtensionRequest
    @State private var text = ""
    @State private var picked: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title.isEmpty ? "Extension" : request.title).font(.system(size: 15, weight: .semibold))
            switch request.method {
            case "select":
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(request.options, id: \.self) { o in
                            Button { Task { await store.respond(to: request, value: o) } } label: {
                                HStack { Text(o).font(.system(size: 13.5)); Spacer() }.padding(.horizontal, 12).frame(height: 34)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 320)
            case "confirm":
                if !request.message.isEmpty { Text(request.message).font(.system(size: 13.5)).foregroundStyle(.secondary).textSelection(.enabled) }
            case "editor":
                TextEditor(text: $text).font(Theme.mono(12.5)).frame(height: 220).padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                    .onAppear { text = request.prefill ?? "" }
            default:
                TextField(request.placeholder ?? "", text: $text).textFieldStyle(.roundedBorder).onSubmit { Task { await store.respond(to: request, value: text) } }
            }
            HStack {
                Spacer()
                Button("Cancel") { Task { await store.respond(to: request, cancelled: true) } }.keyboardShortcut(.cancelAction)
                switch request.method {
                case "confirm":
                    Button("Confirm") { Task { await store.respond(to: request, confirmed: true) } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                case "select": EmptyView()
                default: Button("Submit") { Task { await store.respond(to: request, value: text) } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }.padding(22).frame(width: 440).interactiveDismissDisabled()
    }
}
