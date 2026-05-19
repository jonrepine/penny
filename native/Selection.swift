import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Wraps the focused text element. The Accessibility-direct path is the
/// preferred way to read and write the selection; Electron-based apps usually
/// can't do it, so callers fall back to the clipboard helpers below.
enum Selection {
    /// Returns the focused UI element across all apps, or `nil` if the API is
    /// disabled or no element is focused. Caller should treat `nil` as
    /// "Accessibility unavailable — fall back to clipboard".
    static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success, let focused else {
            log("Accessibility focused-element lookup failed (\(result.rawValue))")
            return nil
        }
        return (focused as! AXUIElement)
    }

    /// Reads the currently selected text from an AX element, or `nil` if the
    /// element doesn't expose `kAXSelectedText`.
    static func readSelectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        if result == .success, let text = value as? String {
            return text
        }
        log("Accessibility selected-text read failed (\(result.rawValue))")
        return nil
    }

    /// Replaces the selected text in `element` with `text`. Returns whether
    /// the write succeeded.
    static func writeSelectedText(_ text: String, to element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if result == .success {
            return true
        }
        log("Accessibility selected-text write failed (\(result.rawValue))")
        return false
    }
}

/// Helpers for the clipboard fallback path. Synthesized ⌘C is the only way to
/// pull a selection out of an Electron app; we gate on `changeCount` so we
/// never silently reuse stale clipboard content.
enum Clipboard {
    /// Triggers ⌘C on the frontmost app and resolves with the new clipboard
    /// text, or `nil` if the pasteboard's change counter never bumped.
    static func grabSelection(timeout: TimeInterval = 1.4, completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let initial = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            sendCommandShortcut(keyCode: CGKeyCode(kVK_ANSI_C))
        }

        let deadline = Date().addingTimeInterval(timeout)
        pollPasteboard(initial: initial, deadline: deadline) { changed in
            guard changed else {
                completion(nil)
                return
            }
            let text = pasteboard.string(forType: .string) ?? ""
            completion(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text)
        }
    }

    /// Writes `text` and posts ⌘V to the frontmost app, after activating
    /// `sourceApp` so focus returns from the picker.
    static func paste(_ text: String, into sourceApp: NSRunningApplication?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        if let sourceApp {
            sourceApp.activate(options: [.activateAllWindows])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            sendCommandShortcut(keyCode: CGKeyCode(kVK_ANSI_V))
        }
    }

    private static func pollPasteboard(initial: Int, deadline: Date, completion: @escaping (Bool) -> Void) {
        if NSPasteboard.general.changeCount != initial {
            completion(true)
            return
        }
        if Date() >= deadline {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pollPasteboard(initial: initial, deadline: deadline, completion: completion)
        }
    }
}
