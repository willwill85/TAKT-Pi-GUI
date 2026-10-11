import SwiftUI
import PiKit

/// Headless browser in the side panel. Frames come from a local Playwright Chromium; clicks and keys
/// are forwarded to it. The user's Chrome is never opened.
struct BrowserPanel: View {
    @State private var browser = BrowserSession()
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.6)
            ZStack {
                if let data = browser.image, let img = NSImage(data: data) {
                    GeometryReader { geo in
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in
                                let scale = min(geo.size.width / img.size.width, geo.size.height / img.size.height)
                                let shown = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                                let origin = CGPoint(x: (geo.size.width - shown.width) / 2, y: (geo.size.height - shown.height) / 2)
                                let x = (value.location.x - origin.x) / scale
                                let y = (value.location.y - origin.y) / scale
                                guard x >= 0, y >= 0, x <= img.size.width, y <= img.size.height else { return }
                                browser.click(x: x, y: y)
                            })
                            .gesture(TapGesture().onEnded { addressFocused = false })
                    }
                    .onScrollWheel { browser.scroll(dy: $0) }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "globe").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text(browser.status).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .focusable()
            .onKeyPress { press in
                guard !addressFocused else { return .ignored }
                if let key = press.characters.first, !key.isWhitespace || key == " " { browser.type(String(key)); return .handled }
                return .ignored
            }
        }
        .onAppear { browser.start() }
        .onChange(of: browser.url) { _, url in if !addressFocused { address = url } }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button { browser.back() } label: { Image(systemName: "chevron.left") }.buttonStyle(HoverButtonStyle(size: 24))
            Button { browser.forward() } label: { Image(systemName: "chevron.right") }.buttonStyle(HoverButtonStyle(size: 24))
            Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(HoverButtonStyle(size: 24))
            TextField("https://", text: $address)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($addressFocused)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                .onSubmit { browser.go(address) }
            Button { browser.go(address) } label: { Image(systemName: "arrow.right") }.buttonStyle(HoverButtonStyle(size: 24)).help("Go")
        }
        .padding(.horizontal, 8).frame(height: 40)
    }
}

private extension View {
    /// Forwards the scroll wheel without a visible scroller, since the page scrolls remotely.
    func onScrollWheel(_ handler: @escaping (Double) -> Void) -> some View {
        background(ScrollWheelCatcher(handler: handler))
    }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    let handler: (Double) -> Void
    func makeNSView(context: Context) -> WheelView { let v = WheelView(); v.handler = handler; return v }
    func updateNSView(_ v: WheelView, context: Context) { v.handler = handler }
    final class WheelView: NSView {
        var handler: ((Double) -> Void)?
        override func scrollWheel(with event: NSEvent) { handler?(event.scrollingDeltaY * -3) }
    }
}
