import AppKit

/// A floating HUD window for displaying brief status messages.
/// Shows a semi-transparent overlay that auto-hides after a duration.
@MainActor
final class HUDWindow {
    private static var window: NSWindow?
    private static var hideTask: Task<Void, Never>?

    /// Shows a HUD message centered on screen.
    /// - Parameters:
    ///   - message: The text to display.
    ///   - duration: How long to show the HUD before fading out (default: 1.5 seconds).
    static func show(message: String, duration: TimeInterval = 1.5) {
        // Cancel any pending hide animation
        hideTask?.cancel()

        // Create the label
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        // Calculate dimensions with padding
        let padding: CGFloat = 24
        let width = max(label.frame.width + padding * 2, 160)
        let height: CGFloat = 56

        // Create the visual effect background (frosted glass appearance)
        let visualEffect = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12

        // Center the label in the visual effect view
        label.frame = NSRect(
            x: padding,
            y: (height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )
        visualEffect.addSubview(label)

        // Create or reuse the window
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.ignoresMouseEvents = true
            window = w
        }

        window?.setContentSize(NSSize(width: width, height: height))
        window?.contentView = visualEffect

        // Position the window in the upper-center of the screen
        if let screen = NSScreen.main {
            let x = (screen.frame.width - width) / 2
            let y = screen.frame.height * 0.75
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Show the window
        window?.alphaValue = 1
        window?.orderFrontRegardless()

        // Schedule auto-hide with fade animation
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    window?.animator().alphaValue = 0
                } completionHandler: {
                    Task { @MainActor in
                        window?.orderOut(nil)
                    }
                }
            }
        }
    }
}
