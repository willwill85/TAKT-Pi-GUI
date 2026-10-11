import SwiftUI
import AppKit

enum ComposerKey { case up, down, tab, escape, enter }

final class ComposerNSTextView: NSTextView {
    var onPasteImages: (([NSImage]) -> Bool)?
    var onPasteFileURLs: (([URL]) -> Bool)?
    var placeholder = ""

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty,
           onPasteFileURLs?(urls) == true { return }
        if pb.string(forType: .string) == nil || pb.types?.contains(.tiff) == true && pb.string(forType: .string)?.isEmpty != false,
           let imgs = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], !imgs.isEmpty, onPasteImages?(imgs) == true { return }
        pasteAsPlainText(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !placeholder.isEmpty, !hasMarkedText() {
            let attrs: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 14), .foregroundColor: NSColor.tertiaryLabelColor]
            let inset = textContainerInset
            (placeholder as NSString).draw(at: NSPoint(x: inset.width + (textContainer?.lineFragmentPadding ?? 0), y: inset.height), withAttributes: attrs)
        }
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
}

struct ComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var caret: Int
    var placeholder: String
    var enterToSend: Bool
    var focusToken: Int
    var maxHeight: CGFloat = 200
    var onSubmit: () -> Void
    var onKey: (ComposerKey) -> Bool
    var onPasteImages: ([NSImage]) -> Bool
    var onPasteFileURLs: ([URL]) -> Bool

    func makeNSView(context: Context) -> NSScrollView {
        let tv = ComposerNSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false; tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 14)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.placeholder = placeholder
        tv.onPasteImages = { context.coordinator.parent.onPasteImages($0) }
        tv.onPasteFileURLs = { context.coordinator.parent.onPasteFileURLs($0) }
        let style = NSMutableParagraphStyle(); style.lineSpacing = 3
        tv.defaultParagraphStyle = style
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        let sv = NSScrollView()
        sv.documentView = tv
        sv.drawsBackground = false
        sv.hasVerticalScroller = false
        sv.borderType = .noBorder
        context.coordinator.textView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = sv.documentView as? ComposerNSTextView else { return }
        tv.placeholder = placeholder
        if tv.string != text && !tv.hasMarkedText() {
            tv.string = text
            let loc = min(max(caret, 0), (text as NSString).length)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        context.coordinator.updateHeight()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        weak var textView: ComposerNSTextView?
        var lastFocusToken = -1
        init(_ p: ComposerTextEditor) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            parent.caret = tv.selectedRange().location
            updateHeight()
            tv.needsDisplay = true
        }
        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = textView else { return }
            let loc = tv.selectedRange().location
            if parent.caret != loc { DispatchQueue.main.async { self.parent.caret = loc } }
        }
        func updateHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = min(parent.maxHeight, max(24, ceil(lm.usedRect(for: tc).height) + 4))
            if abs(parent.height - h) > 0.5 { DispatchQueue.main.async { self.parent.height = h } }
            (tv.enclosingScrollView)?.hasVerticalScroller = lm.usedRect(for: tc).height + 4 > parent.maxHeight
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if tv.hasMarkedText() { return false }
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                if parent.onKey(.enter) { return true }
                let shift = NSEvent.modifierFlags.contains(.shift)
                let cmd = NSEvent.modifierFlags.contains(.command)
                if cmd || (parent.enterToSend && !shift) { parent.onSubmit(); return true }
                tv.insertNewlineIgnoringFieldEditor(nil); return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return false
            case #selector(NSResponder.moveUp(_:)): return parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.onKey(.down)
            case #selector(NSResponder.insertTab(_:)): return parent.onKey(.tab)
            case #selector(NSResponder.cancelOperation(_:)): return parent.onKey(.escape)
            default: return false
            }
        }
    }
}
