import SwiftUI
import AppKit

/// AppKit owns field editing so Return, Shift+Return and Escape behave consistently.
struct NativeFindField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let next: () -> Void
    let previous: () -> Void
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> FocusedSearchField {
        let field = FocusedSearchField()
        field.placeholderString = "Find in document"
        field.setAccessibilityLabel("Find in document")
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        return field
    }
    func updateNSView(_ field: FocusedSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            field.requestFocus()
        }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeFindField
        var lastFocusRequest: Int?
        init(_ parent: NativeFindField) { self.parent = parent }
        @objc func changed(_ field: NSSearchField) { parent.text = field.stringValue }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { changed(field) }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) { parent.previous() } else { parent.next() }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.dismiss(); return true
            }
            return false
        }
    }
}

final class FocusedSearchField: NSSearchField {
    private var needsFocus = false
    func requestFocus() {
        needsFocus = true
        DispatchQueue.main.async { [weak self] in self?.applyFocus() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if needsFocus { requestFocus() }
    }
    private func applyFocus() {
        guard needsFocus, let window else { return }
        needsFocus = false
        window.makeFirstResponder(self)
    }
}
