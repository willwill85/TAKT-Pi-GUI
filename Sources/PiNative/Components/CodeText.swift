import SwiftUI
import AppKit
import Highlightr

/// Shared syntax highlighter (highlight.js through JavaScriptCore).
@MainActor
final class CodeHighlighter {
    static let shared = CodeHighlighter()
    private let hl = Highlightr()
    private var currentTheme = ""

    func highlight(_ code: String, language: String?, dark: Bool) -> NSAttributedString {
        let theme = dark ? "atom-one-dark" : "xcode"
        if theme != currentTheme { _ = hl?.setTheme(to: theme); currentTheme = theme }
        hl?.theme.setCodeFont(NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        let lang = Self.map(language)
        if code.utf8.count < 300_000, let out = hl?.highlight(code, as: lang, fastRender: true) { 
            let m = NSMutableAttributedString(attributedString: out)
            m.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: m.length))
            return m
        }
        return NSAttributedString(string: code, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor])
    }

    static func map(_ l: String?) -> String? {
        guard let l, l != "text" else { return nil }
        switch l { case "dockerfile": return "dockerfile"; case "makefile": return "makefile"; case "hcl": return "ini"; case "word", "pdf": return nil; default: return l }
    }
}

/// Read-only code view with line numbers, backed by NSTextView (fast for large files).
struct CodeTextView: NSViewRepresentable {
    var text: String
    var language: String?
    var wrap: Bool = false
    var scrollToLine: Int?
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true; sv.hasHorizontalScroller = true
        sv.drawsBackground = false; sv.borderType = .noBorder
        sv.autohidesScrollers = true
        let tv = NSTextView()
        tv.isEditable = false; tv.isSelectable = true; tv.isRichText = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = true
        tv.autoresizingMask = []
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        sv.documentView = tv
        sv.hasVerticalRuler = true; sv.rulersVisible = true
        sv.verticalRulerView = LineNumberRuler(textView: tv)
        context.coordinator.textView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        let key = "\(text.hashValue)|\(language ?? "")|\(scheme == .dark)"
        if context.coordinator.key != key {
            context.coordinator.key = key
            let attr = CodeHighlighter.shared.highlight(text, language: language, dark: scheme == .dark)
            tv.textStorage?.setAttributedString(attr)
            (sv.verticalRulerView as? LineNumberRuler)?.invalidateLines()
        }
        if wrap != context.coordinator.wrap {
            context.coordinator.wrap = wrap
            tv.textContainer?.widthTracksTextView = wrap
            tv.isHorizontallyResizable = !wrap
            tv.textContainer?.containerSize = NSSize(width: wrap ? max(sv.contentSize.width - 60, 200) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if wrap { tv.autoresizingMask = [.width] } else { tv.autoresizingMask = [] }
            tv.sizeToFit()
        }
        if let line = scrollToLine, context.coordinator.scrolledLine != line {
            context.coordinator.scrolledLine = line
            DispatchQueue.main.async {
                let ns = tv.string as NSString
                var idx = 0, cur = 1
                while cur < line, idx < ns.length { let r = ns.lineRange(for: NSRange(location: idx, length: 0)); idx = NSMaxRange(r); cur += 1 }
                let r = ns.lineRange(for: NSRange(location: min(idx, max(ns.length - 1, 0)), length: 0))
                tv.scrollRangeToVisible(r)
                tv.showFindIndicator(for: r)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var key = ""; var wrap = false; var scrolledLine: Int?; weak var textView: NSTextView? }
}

final class LineNumberRuler: NSRulerView {
    private weak var tv: NSTextView?
    private var lineStarts: [Int] = [0]

    init(textView: NSTextView) {
        self.tv = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView)
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func redraw() { needsDisplay = true }

    func invalidateLines() {
        guard let s = tv?.string as NSString? else { return }
        var starts = [0]; starts.reserveCapacity(s.length / 40)
        var i = 0
        while i < s.length { let r = s.lineRange(for: NSRange(location: i, length: 0)); i = NSMaxRange(r); if i < s.length { starts.append(i) } }
        lineStarts = starts
        let digits = max(3, String(starts.count).count)
        ruleThickness = CGFloat(digits) * 8 + 22
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv, let lm = tv.layoutManager, let tc = tv.textContainer, let sv = tv.enclosingScrollView else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
        let visible = sv.contentView.bounds
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if lineStarts[mid] <= charRange.location { lo = mid } else { hi = mid - 1 } }
        var line = lo
        while line < lineStarts.count {
            let start = lineStarts[line]
            if start > NSMaxRange(charRange) { break }
            let gi = lm.glyphIndexForCharacter(at: min(start, max(tv.string.utf16.count - 1, 0)))
            let r = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            let y = r.minY + tv.textContainerInset.height - visible.minY
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + (r.height - size.height) / 2), withAttributes: attrs)
            line += 1
        }
    }
}
