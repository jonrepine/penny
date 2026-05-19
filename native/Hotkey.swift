import AppKit
import Carbon.HIToolbox

/// Detects a double-tap on the Right Option key. A "tap" is Right Option going
/// down and back up without any other key pressed while it was held. Two taps
/// within `doubleTapWindow` fire the trigger.
final class DoubleTapDetector {
    private static let doubleTapWindow: TimeInterval = 0.45

    private let onTrigger: () -> Void
    private var eventTap: CFMachPort?
    private var rightOptionDown = false
    private var chordUsed = false
    private var lastTapAt = Date.distantPast

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Installs the CGEventTap. Requires Input Monitoring + Accessibility.
    /// Returns false if the tap couldn't be created.
    @discardableResult
    func install() -> Bool {
        let mask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: refcon
        ) else {
            log("Hotkey: failed to create event tap. Grant Input Monitoring + Accessibility.")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate var underlyingTap: CFMachPort? { eventTap }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged && keyCode == Int64(kVK_RightOption) {
            let isDown = event.flags.contains(.maskAlternate)
            handleOptionTransition(isDown: isDown)
            return
        }

        if type == .keyDown && rightOptionDown {
            chordUsed = true
        }
    }

    private func handleOptionTransition(isDown: Bool) {
        if isDown {
            if !rightOptionDown {
                rightOptionDown = true
                chordUsed = false
            }
            return
        }

        guard rightOptionDown else { return }
        rightOptionDown = false

        if chordUsed {
            chordUsed = false
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastTapAt) <= Self.doubleTapWindow {
            lastTapAt = .distantPast
            log("Double-tap Right Option detected")
            onTrigger()
        } else {
            lastTapAt = now
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let detector = Unmanaged<DoubleTapDetector>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = detector.underlyingTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            log("Event tap was disabled and has been re-enabled")
        }
        return Unmanaged.passUnretained(event)
    }

    detector.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
