import SwiftUI
import AppKit

/// Codex-style design tokens (see docs/03-ui-spec-codex.md).
enum Theme {
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    static let background = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surface = dynamic(light: 0xF4F4F5, dark: 0x2A2A2D)           // bubbles, composer, cards
    static let surfaceHover = dynamic(light: 0xEBEBED, dark: 0x343437)
    static let codeBackground = dynamic(light: 0xF6F6F7, dark: 0x252528)
    static let separator = Color.primary.opacity(0.09)
    static let sidebarSelection = Color.primary.opacity(0.09)
    static let sidebarHover = Color.primary.opacity(0.05)
    static let added = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    static let removed = dynamic(light: 0xCF222E, dark: 0xF85149)
    static let addedBackground = dynamic(light: 0x1A7F37, dark: 0x3FB950, lightAlpha: 0.12, darkAlpha: 0.16)
    static let removedBackground = dynamic(light: 0xCF222E, dark: 0xF85149, lightAlpha: 0.10, darkAlpha: 0.16)
    static let warning = Color.orange

    static let columnWidth: CGFloat = 760
    static let radiusComposer: CGFloat = 20
    static let radiusCard: CGFloat = 12
    static let radiusBubble: CGFloat = 16

    static func body(_ size: CGFloat = 14) -> Font { .system(size: size) }
    static func mono(_ size: CGFloat = 12.5) -> Font { .system(size: size, design: .monospaced) }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material; v.blendingMode = blending }
}

/// Lets the user drag the window by empty chrome (the title bar is hidden).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ v: NSView, context: Context) {}
}

struct HoverButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    var radius: CGFloat = 7
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, size: size, radius: radius)
    }
    private struct HoverBody: View {
        let configuration: Configuration
        let size: CGFloat
        let radius: CGFloat
        @State private var hover = false
        var body: some View {
            configuration.label
                .frame(minWidth: size, minHeight: size)
                .background(RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hover ? 0.08 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .onHover { hover = $0 }
        }
    }
}

struct Chip<Content: View>: View {
    var content: Content
    var action: (() -> Void)?
    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) { self.action = action; self.content = content() }
    @State private var hover = false
    var body: some View {
        content
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(hover ? 0.08 : 0)))
            .contentShape(Capsule())
            .onHover { hover = $0 }
            .onTapGesture { action?() }
    }
}

extension View {
    func cardSurface(radius: CGFloat = Theme.radiusCard) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface))
    }
    func hairline(radius: CGFloat = Theme.radiusCard) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }
}

func relativeTime(_ date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    if s < 86400 * 7 { return "\(s / 86400)d" }
    if s < 86400 * 60 { return "\(s / (86400 * 7))w" }
    return "\(s / (86400 * 30))mo"
}

func formatDuration(_ s: Double) -> String {
    let t = Int(s.rounded())
    if t < 60 { return "\(t)s" }
    if t < 3600 { return "\(t / 60)m \(t % 60)s" }
    return "\(t / 3600)h \((t % 3600) / 60)m"
}

func shortPath(_ p: String, home: String = NSHomeDirectory()) -> String {
    p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
}
