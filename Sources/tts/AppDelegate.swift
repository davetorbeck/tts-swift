import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

/// Application delegate handling window management, lifecycle events, and permissions.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var window: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make the app a regular app (shows in dock, can have windows)
        NSApp.setActivationPolicy(.regular)
        showWindow()
        AppState.shared.startBackgroundSetup()
        promptAccessibilityPermission()
    }

    private func promptAccessibilityPermission() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        AppState.shared.permissionStatus =
            trusted ? "Accessibility granted" : "Accessibility not granted"
    }

    /// Shows or creates the main application window.
    func showWindow() {
        if window == nil {
            let contentView = ContentView()
                .environmentObject(AppState.shared)
                .frame(minWidth: 560, minHeight: 420)

            let hostingView = NSHostingView(rootView: contentView)
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Kokoro TTS"
            newWindow.center()
            newWindow.contentView = hostingView
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }

        setAlwaysOnTop(AppState.shared.alwaysOnTop)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Sets whether the main window floats above other windows.
    func setAlwaysOnTop(_ enabled: Bool) {
        window?.level = enabled ? .floating : .normal
    }
}
