import AppKit

enum PasteController {
    static func paste() {
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            postPasteShortcut()
        }
    }

    private static func postPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
