import SwiftUI
import PiKit

struct RightPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    var body: some View {
        VStack(spacing: 0) {
            Text("Side panel").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Theme.background)
    }
}
