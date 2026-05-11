import ApplicationServices
import Carbon
import Foundation

final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isPressed = false

    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    @discardableResult
    func start() -> OSStatus {
        guard hotKeyRef == nil, eventHandlerRef == nil else { return noErr }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
            controller.handle(eventKind: GetEventKind(event))
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            NSLog("ParakeetPTT failed to install hotkey handler: \(handlerStatus)")
            return handlerStatus
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("PKPT"), id: 1)
        let hotkeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Slash),
            UInt32(optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if hotkeyStatus != noErr {
            NSLog("ParakeetPTT failed to register Option-/ hotkey: \(hotkeyStatus)")
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            eventHandlerRef = nil
            hotKeyRef = nil
        }
        return hotkeyStatus
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        isPressed = false
    }

    private func handle(eventKind: UInt32) {
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            press()
        case UInt32(kEventHotKeyReleased):
            release()
        default:
            break
        }
    }

    private func press() {
        guard !isPressed else { return }
        isPressed = true
        NSLog("ParakeetPTT Option-/ hotkey pressed")
        DispatchQueue.main.async { self.onPressed?() }
    }

    private func release() {
        guard isPressed else { return }
        isPressed = false
        NSLog("ParakeetPTT Option-/ hotkey released")
        DispatchQueue.main.async { self.onReleased?() }
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { code, character in
            (code << 8) + OSType(character)
        }
    }
}
