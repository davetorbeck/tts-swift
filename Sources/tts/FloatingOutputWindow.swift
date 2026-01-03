import AppKit
import SwiftUI

@MainActor
final class FloatingOutputWindow {
    private static var window: NSWindow?
    private static var hostingView: NSHostingView<AnyView>?

    static func show() {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Now Speaking"
            newWindow.titlebarAppearsTransparent = true
            newWindow.isMovableByWindowBackground = true
            newWindow.level = .floating
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newWindow.isReleasedWhenClosed = false
            newWindow.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            window = newWindow

            if let screen = NSScreen.main {
                let originX = screen.frame.maxX - 420
                let originY = screen.frame.maxY - 280
                newWindow.setFrameOrigin(NSPoint(x: originX, y: originY))
            }
        }

        updateContent()
        window?.orderFront(nil)
    }

    static func updateContent() {
        let content = FloatingOutputContent()
            .environmentObject(AppState.shared)

        if let existingHosting = hostingView {
            existingHosting.rootView = AnyView(content)
        } else {
            let hosting = NSHostingView(rootView: AnyView(content))
            hostingView = hosting
            window?.contentView = hosting
        }
    }

    static func hide() {
        window?.orderOut(nil)
    }

    static var isVisible: Bool {
        window?.isVisible ?? false
    }
}

struct FloatingOutputContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if state.wordTimings.isEmpty {
                Text("Waiting for speech...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        FlowLayout(spacing: 2) {
                            ForEach(Array(state.wordTimings.enumerated()), id: \.offset) { index, timing in
                                Text(timing.word)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        index == state.currentWordIndex
                                            ? Color.accentColor.opacity(0.4) : Color.clear
                                    )
                                    .cornerRadius(3)
                                    .font(.system(size: 15))
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .onChange(of: state.currentWordIndex) { _, newIndex in
                        if let idx = newIndex {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(idx, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 300, minHeight: 100)
    }
}
