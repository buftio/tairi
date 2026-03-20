import AppKit
import SwiftUI

struct WorkspaceRenameField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isFocused: Bool
    let theme: GhosttyAppTheme
    let accessibilityIdentifier: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> WorkspaceRenameTextField {
        let textField = WorkspaceRenameTextField()
        textField.delegate = context.coordinator
        textField.onSubmit = onSubmit
        textField.onCancel = onCancel
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.configureAccessibility(
            identifier: accessibilityIdentifier,
            label: placeholder,
            role: .textField
        )
        return textField
    }

    func updateNSView(_ nsView: WorkspaceRenameTextField, context: Context) {
        context.coordinator.text = $text
        nsView.onSubmit = onSubmit
        nsView.onCancel = onCancel
        nsView.placeholderString = placeholder
        nsView.applyTheme(theme)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)

        if isFocused {
            DispatchQueue.main.async {
                guard nsView.window?.firstResponder !== nsView.currentEditor() else {
                    nsView.placeCursorAtEnd()
                    return
                }
                nsView.window?.makeFirstResponder(nsView)
                nsView.placeCursorAtEnd()
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        let onSubmit: () -> Void
        let onCancel: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                return false
            }
        }
    }
}

final class WorkspaceRenameTextField: NSTextField {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        lineBreakMode = .byTruncatingTail
        font = .systemFont(ofSize: 13, weight: .medium)
        cell?.wraps = false
        cell?.isScrollable = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        placeCursorAtEnd()
    }

    func applyTheme(_ theme: GhosttyAppTheme) {
        textColor = theme.primaryText
        placeholderAttributedString = NSAttributedString(
            string: placeholderString ?? "",
            attributes: [
                .foregroundColor: theme.secondaryText.withAlphaComponent(0.65),
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            ]
        )

        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = theme.primaryText.withAlphaComponent(0.82)
        editor.selectedTextAttributes = [
            .backgroundColor: theme.accent.withAlphaComponent(theme.isLightTheme ? 0.12 : 0.16),
            .foregroundColor: theme.primaryText,
        ]
    }

    func placeCursorAtEnd() {
        guard let editor = currentEditor() as? NSTextView else { return }
        let location = editor.string.count
        editor.selectedRange = NSRange(location: location, length: 0)
    }
}
