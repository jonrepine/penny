import AppKit
import Carbon.HIToolbox

/// Synthesizes ⌘+`keyCode` as four separate events (cmd-down, key-down,
/// key-up, cmd-up) instead of a single key event with a modifier flag bitmask.
/// macOS interprets it the same as a physical keystroke this way, which is
/// what we need for ⌘C / ⌘V to actually trigger copy and paste in arbitrary
/// frontmost apps. Internally pynput does the same thing.
func sendCommandShortcut(keyCode: CGKeyCode) {
    let source = CGEventSource(stateID: .combinedSessionState)
    let cmd = CGKeyCode(kVK_Command)

    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmd, keyDown: true)
    cmdDown?.flags = .maskCommand
    cmdDown?.post(tap: .cghidEventTap)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)

    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = .maskCommand
    keyUp?.post(tap: .cghidEventTap)

    let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmd, keyDown: false)
    cmdUp?.flags = []
    cmdUp?.post(tap: .cghidEventTap)
}
