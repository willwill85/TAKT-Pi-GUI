import SwiftUI

/// TAKT Pi GUI mark: a bold "π" whose right foot is a terminal cursor block.
/// Single source of truth for the app icon (rendered by IconGen) and in-app branding.
public struct PiGlyph: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        // Design on a 1000×1000 grid; the glyph occupies x 215…785, y 290…730.
        let s = min(rect.width, rect.height) / 1000
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: rect.minX + x * s, y: rect.minY + y * s, width: w * s, height: h * s), cornerRadius: radius * s, style: .continuous)
        }
        var p = Path()
        p.addPath(r(215, 290, 570, 84, 42))          // top bar
        p.addPath(r(318, 330, 86, 400, 43))          // left leg
        p.addPath(r(560, 330, 86, 250, 43))          // right leg (shortened, cursor sits below)
        return p
    }
}

public struct CursorBlock: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1000
        return Path(roundedRect: CGRect(x: rect.minX + 560 * s, y: rect.minY + 622 * s, width: 100 * s, height: 108 * s), cornerRadius: 20 * s, style: .continuous)
    }
}

public extension Color {
    static let taktAccent = Color(red: 1.0, green: 0.42, blue: 0.24)
    static let taktAccent2 = Color(red: 1.0, green: 0.62, blue: 0.20)
}

/// The mark without a plate, for small in-app use.
/// Drawn in a single Canvas on a fixed 1000-unit grid so the glyph and the cursor block always keep
/// their proportions, whatever size the surrounding layout proposes.
public struct PiMark: View {
    public var size: CGFloat
    public var monochrome: Bool
    public init(size: CGFloat = 28, monochrome: Bool = false) { self.size = size; self.monochrome = monochrome }
    public var body: some View {
        Canvas { ctx, canvas in
            let side = min(canvas.width, canvas.height)
            let rect = CGRect(x: (canvas.width - side) / 2, y: (canvas.height - side) / 2, width: side, height: side)
            let ink: Color = monochrome ? .primary : .white
            ctx.fill(PiGlyph().path(in: rect), with: .color(ink))
            let cursor = CursorBlock().path(in: rect)
            if monochrome {
                ctx.fill(cursor, with: .color(.primary))
            } else {
                ctx.fill(cursor, with: .linearGradient(Gradient(colors: [.taktAccent2, .taktAccent]),
                                                       startPoint: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.62),
                                                       endPoint: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.73)))
            }
        }
        .frame(width: size, height: size)
        .fixedSize()
    }
}

/// App icon artwork (1024×1024 canvas, macOS squircle with margin).
public struct AppIconArtwork: View {
    public init() {}
    public var body: some View {
        ZStack {
            Color.clear
            ZStack {
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.19, green: 0.19, blue: 0.23), Color(red: 0.07, green: 0.07, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 3)
                // soft glow behind the cursor
                Circle().fill(Color.taktAccent.opacity(0.35)).frame(width: 340, height: 340).blur(radius: 80).offset(x: 40, y: 150)
                PiGlyph().fill(LinearGradient(colors: [.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
                CursorBlock().fill(LinearGradient(colors: [.taktAccent2, .taktAccent], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .taktAccent.opacity(0.6), radius: 22, y: 0)
            }
            .frame(width: 824, height: 824)
            .shadow(color: .black.opacity(0.4), radius: 22, y: 14)
        }
        .frame(width: 1024, height: 1024)
    }
}
