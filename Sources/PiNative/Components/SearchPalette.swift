import SwiftUI
import PiKit

struct SearchPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [SessionInfo] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let all = model.sessions.sorted { $0.modified > $1.modified }
        if q.isEmpty { return Array(all.prefix(30)) }
        return Array(all.filter { $0.title.lowercased().contains(q) || $0.cwd.lowercased().contains(q) || $0.firstMessage.lowercased().contains(q) }.prefix(30))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search threads…", text: $query).textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                    .onSubmit { open(results.indices.contains(selected) ? results[selected] : nil) }
                    .onKeyPress(.downArrow) { selected = min(selected + 1, max(0, results.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
            }.padding(.horizontal, 16).frame(height: 52)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, s in
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
                            Text(s.title).font(.system(size: 13.5)).lineLimit(1)
                            Text(SidebarModel.folderName(s.projectRoot)).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
                            Spacer()
                            Text(relativeTime(s.modified)).font(.system(size: 11.5)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(i == selected ? Color.accentColor.opacity(0.16) : .clear))
                        .contentShape(Rectangle()).onTapGesture { open(s) }
                    }
                    if results.isEmpty { Text("No threads found").foregroundStyle(.secondary).padding(30) }
                }.padding(8)
            }.frame(height: 360)
        }
        .frame(width: 600)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private func open(_ s: SessionInfo?) {
        guard let s else { return }
        model.select(s.id); dismiss()
    }
}
