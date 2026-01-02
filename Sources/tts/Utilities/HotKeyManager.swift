import Carbon
import Foundation

/// Manages global hotkey registration using Carbon Event APIs.
/// Registers ⌃⌘A (Control+Command+A) as the global hotkey for speaking selected text.
final class HotKeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: @Sendable () -> Void

    /// Creates a new hotkey manager and registers the global hotkey.
    /// - Parameter handler: Closure to call when the hotkey is pressed.
    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        register()
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef = handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    /// Unregisters and re-registers the hotkey.
    /// Useful after accessibility permissions are granted.
    func reregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef = handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        register()
    }

    /// Registers the global hotkey (⌃⌘A).
    private func register() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // 'KOKO' as a 4-character signature
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4F_4B4F), id: 1)

        // Control + Command modifiers
        let modifiers = UInt32(cmdKey | controlKey)
        // Key code for 'A'
        let keyCodeA: UInt32 = 0x00

        let status = RegisterEventHotKey(
            keyCodeA,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { return }

        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let handler = manager.handler
                DispatchQueue.main.async {
                    handler()
                }
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &installedHandler
        )

        if handlerStatus == noErr {
            handlerRef = installedHandler
        }
    }
}
