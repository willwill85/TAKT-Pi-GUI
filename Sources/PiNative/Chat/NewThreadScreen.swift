import SwiftUI
import PiKit

struct NewThreadScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !ui.sidebarVisible {
                    Button { withAnimation(.snappy(duration: 0.22)) { ui.sidebarVisible = true } } label: { Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundStyle(.secondary) }
                        .buttonStyle(HoverButtonStyle()).padding(.leading, 74)
                }
                Spacer()
            }.frame(height: 44).background(WindowDragArea())
            Spacer(minLength: 0)
            VStack(spacing: 22) {
                Image(systemName: "sparkle").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                Text("What should we build\(projectSuffix)?").font(.system(size: 26, weight: .semibold)).multilineTextAlignment(.center)
                ComposerView(draftKey: "__new__:" + (model.newThreadCwd ?? ""), store: nil, placeholder: "Ask Pi to build, fix, or explain something…")
                    .frame(maxWidth: Theme.columnWidth)
            }.padding(.horizontal, 24)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
    }

    private var projectSuffix: String {
        guard let cwd = model.newThreadCwd, cwd != model.homeDirectory else { return "" }
        return " in \(SidebarModel.folderName(cwd))"
    }
}
