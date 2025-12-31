import AppKit
import SwiftUI

@MainActor
final class FloatingOutputWindow {
    private static var window: NSWindow?
    private static var hostingView: NSHostingView<AnyView>?
    
    static func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Now Speaking"
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
            window = w
            
            if let screen = NSScreen.main {
                let x = screen.frame.maxX - 420
                let y = screen.frame.maxY - 280
                w.setFrameOrigin(NSPoint(x: x, y: y))
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
                        FlowLayout(spacing: 4) {
                            ForEach(Array(state.wordTimings.enumerated()), id: \.offset) { index, timing in
                                Text(timing.word)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(index == state.currentWordIndex ? Color.accentColor.opacity(0.4) : Color.clear)
                                    .cornerRadius(4)
                                    .font(.system(size: 16))
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .onChange(of: state.currentWordIndex) { newIndex in
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
