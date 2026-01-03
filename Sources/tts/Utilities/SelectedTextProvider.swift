import AppKit
import ApplicationServices

enum SelectedTextProvider {
    static func getSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusedError == .success, let element = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        let axElement = element as! AXUIElement // swiftlint:disable:this force_cast
        let selectedError = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        guard selectedError == .success else { return nil }

        return selectedText as? String
    }
}

struct SystemTextProvider: TextProviding, Sendable {
    func getSelectedText() -> String? {
        SelectedTextProvider.getSelectedText()
    }
}
