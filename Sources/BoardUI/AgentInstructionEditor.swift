import AppKit
import SwiftUI

/// Placeholder and caret use exactly the same text container and font metrics.
struct AgentInstructionEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let editor = PlaceholderTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .labelColor
        editor.insertionPointColor = .controlAccentColor
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 9, height: 9)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.isFocused = focused
        }
        editor.string = text
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PlaceholderTextView else { return }
        // Never replace marked text while the input method is composing.
        if !editor.hasMarkedText(), editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        editor.needsDisplay = true
        if !isFocused, editor.window?.firstResponder === editor {
            editor.window?.makeFirstResponder(nil)
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentInstructionEditor
        init(_ parent: AgentInstructionEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            editor.needsDisplay = true
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }
    override var string: String { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.placeholderTextColor]
        let origin = textContainerOrigin
        let rect = NSRect(x: origin.x + (textContainer?.lineFragmentPadding ?? 0), y: origin.y,
                          width: max(0, bounds.width - origin.x * 2 - 10), height: bounds.height)
        ("写下要做的事，或补充任务说明…" as NSString).draw(in: rect, withAttributes: attributes)
    }
}
