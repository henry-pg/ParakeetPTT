import AppKit
import ApplicationServices
import Foundation

enum TextInjector {
    @discardableResult
    static func paste(_ text: String, into targetApp: NSRunningApplication?) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSLog("ParakeetPTT copied transcript to pasteboard: \(text.count) chars")

        let isTerminal = isTerminalLike(targetApp)
        let isBrowser = isBrowserLike(targetApp)
        if !isTerminal, !isBrowser, insertIntoFocusedElement(text) {
            NSLog("ParakeetPTT inserted transcript through Accessibility focused element")
            return true
        }
        if isTerminal {
            NSLog("ParakeetPTT using text-typing path for terminal app: \(targetApp?.localizedName ?? "unknown")")
            runAfterModifiersReleased {
                typeText(text)
            }
            return AXIsProcessTrusted()
        }
        if isBrowser {
            NSLog("ParakeetPTT using clipboard paste path for browser app: \(targetApp?.localizedName ?? "unknown")")
            if let targetApp {
                NSLog("ParakeetPTT activating browser before paste: \(targetApp.localizedName ?? "unknown")")
                targetApp.activate(options: [.activateIgnoringOtherApps])
            }

            runAfterModifiersReleased(delay: 0.60) {
                NSLog("ParakeetPTT sending single Cmd-V paste event for browser")
                sendPasteShortcut(strategy: .singleHID)
            }
            return AXIsProcessTrusted()
        }

        if let targetApp {
            NSLog("ParakeetPTT activating target app before paste: \(targetApp.localizedName ?? "unknown")")
            targetApp.activate(options: [.activateIgnoringOtherApps])
        }

        runAfterModifiersReleased(delay: 0.60) {
            NSLog("ParakeetPTT falling back to Cmd-V paste event")
            sendPasteShortcut(strategy: .doubleFallback)
        }
        return AXIsProcessTrusted()
    }

    private enum PasteEventStrategy {
        case singleHID
        case doubleFallback
    }

    private static func isBrowserLike(_ app: NSRunningApplication?) -> Bool {
        guard let name = app?.localizedName?.lowercased() else { return false }
        return [
            "google chrome",
            "chrome",
            "chromium",
            "arc",
            "brave",
            "microsoft edge",
            "edge",
            "safari",
            "firefox"
        ].contains { name.contains($0) }
    }

    private static func isTerminalLike(_ app: NSRunningApplication?) -> Bool {
        guard let name = app?.localizedName?.lowercased() else { return false }
        return [
            "ghostty",
            "terminal",
            "iterm",
            "iterm2",
            "warp",
            "wezterm",
            "alacritty",
            "kitty"
        ].contains { name.contains($0) }
    }

    private static func insertIntoFocusedElement(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else {
            NSLog("ParakeetPTT Accessibility is not trusted; cannot insert directly")
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard focusedStatus == .success, let focusedObject else {
            NSLog("ParakeetPTT could not read focused UI element: \(focusedStatus.rawValue)")
            return false
        }

        let focusedElement = focusedObject as! AXUIElement
        let selectedTextStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedTextStatus == .success {
            return true
        }

        NSLog("ParakeetPTT focused element rejected selected-text insertion: \(selectedTextStatus.rawValue)")
        return false
    }

    private static func runAfterModifiersReleased(
        delay: TimeInterval = 0.05,
        attempts: Int = 0,
        action: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let modifierMask: CGEventFlags = [
                .maskAlternate,
                .maskCommand,
                .maskControl,
                .maskShift,
                .maskSecondaryFn
            ]

            if flags.intersection(modifierMask).isEmpty || attempts >= 30 {
                action()
            } else {
                runAfterModifiersReleased(delay: 0.05, attempts: attempts + 1, action: action)
            }
        }
    }

    private static func typeText(_ text: String) {
        guard AXIsProcessTrusted() else {
            NSLog("ParakeetPTT Accessibility is not trusted; cannot type transcript")
            return
        }

        NSLog("ParakeetPTT typing transcript as Unicode events: \(text.count) chars")
        let source = CGEventSource(stateID: .combinedSessionState)

        for character in text {
            var utf16 = Array(String(character).utf16)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.flags = []
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.flags = []
            up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up?.post(tap: .cghidEventTap)

            usleep(1_500)
        }
    }

    private static func sendPasteShortcut(strategy: PasteEventStrategy) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 9

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        guard strategy == .doubleFallback else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let secondDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            secondDown?.flags = .maskCommand
            let secondUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            secondUp?.flags = .maskCommand

            secondDown?.post(tap: .cgAnnotatedSessionEventTap)
            secondUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
