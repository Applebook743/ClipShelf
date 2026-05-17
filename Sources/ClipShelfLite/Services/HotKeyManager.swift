import Carbon
import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerUPP?
    private var handlerRef: EventHandlerRef?

    func register(configuration: HotKeyConfiguration = HotKeyDefaults.load()) {
        unregister()
        guard configuration.isValid else { return }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CLIP"), id: 1)
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            NSLog("ClipShelf failed to register hot key: \(status)")
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        if handler == nil {
            handler = { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.id == 1 else {
                    return status
                }

                DispatchQueue.main.async {
                    HotKeyManager.shared.action?()
                }

                return noErr
            }
        }

        if let handler {
            InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                1,
                &eventSpec,
                nil,
                &handlerRef
            )
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
