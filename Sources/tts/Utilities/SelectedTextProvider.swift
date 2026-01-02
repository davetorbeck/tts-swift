import AppKit
import ApplicationServices

/// Utility for retrieving selected text from the frontmost application using Accessibility APIs.
/// Requires Accessibility permission to be granted to the app.
enum SelectedTextProvider {

    /// Retrieves the currently selected text from the frontmost application.
    /// - Returns: The selected text, or nil if no text is selected or accessibility is not granted.
    static func getSelectedText() -> String? {
        // Get the frontmost application
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused UI element (e.g., text field, text view)
        var focusedElement: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusedError == .success, let element = focusedElement else { return nil }

        // Get the selected text from the focused element
        var selectedText: CFTypeRef?
        let selectedError = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        guard selectedError == .success else { return nil }

        return selectedText as? String
    }
}
