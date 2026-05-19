import AppKit

/// Renders the small "Listening" and "Transcribing" overlays during a
/// dictation session. The dictation daemon lives in a separate Python
/// process; it writes its current state to ~/.penny/dictate.state and
/// this class watches that file with a low-frequency poll. Cheap, no
/// extra dependencies, no IPC permissions to deal with.
final class DictationOverlay {
    private static let statePath: String = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".penny/dictate.state")

    private var panel: NSPanel?
    private var pollTimer: Timer?
    private var lastState: String = ""

    init() {
        ensureStateFileExists()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Run once immediately so we don't wait 100 ms on startup.
        tick()
    }

    private func ensureStateFileExists() {
        let dir = (Self.statePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Self.statePath) {
            try? "idle".write(toFile: Self.statePath, atomically: true, encoding: .utf8)
        }
    }

    private func tick() {
        guard let text = try? String(contentsOfFile: Self.statePath, encoding: .utf8) else {
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == lastState { return }
        lastState = value

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch value {
            case "listening":   self.show(.listening)
            case "transcribing": self.show(.transcribing)
            default:             self.hide()
            }
        }
    }

    // MARK: Presentation

    private enum Mode { case listening, transcribing }

    private func show(_ mode: Mode) {
        hide()

        let width: CGFloat = 220
        let height: CGFloat = 38
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - width / 2, y: frame.minY + 100)

        let p = OverlayPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlay(p)

        let content = makeMaterial(frame: NSRect(x: 0, y: 0, width: width, height: height))

        switch mode {
        case .listening:
            content.addSubview(makePulsingDot(at: NSPoint(x: 16, y: 13)))
            let label = makeLabel("Listening", size: 12, weight: .medium, color: .labelColor)
            label.frame = NSRect(x: 36, y: 11, width: 180, height: 16)
            content.addSubview(label)

        case .transcribing:
            for index in 0..<3 {
                content.addSubview(makeBouncingDot(at: NSPoint(x: 18 + CGFloat(index) * 11, y: 16),
                                                   offset: Double(index) * 0.18))
            }
            let label = makeLabel("Transcribing", size: 12, weight: .medium, color: .labelColor)
            label.frame = NSRect(x: 60, y: 11, width: 150, height: 16)
            content.addSubview(label)
        }

        p.contentView = content
        p.orderFrontRegardless()
        panel = p
    }

    private func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    // MARK: Animated subviews

    /// A small filled circle whose opacity breathes in a 1.2 s loop.
    private func makePulsingDot(at origin: NSPoint) -> NSView {
        let dot = NSView(frame: NSRect(origin: origin, size: NSSize(width: 12, height: 12)))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.35
        anim.toValue = 1.0
        anim.duration = 0.6
        anim.autoreverses = true
        anim.repeatCount = .infinity
        dot.layer?.add(anim, forKey: "pulse")
        return dot
    }

    /// A small accent-coloured dot that bounces vertically. `offset` lets
    /// each of the three dots stagger so they appear to chase each other.
    private func makeBouncingDot(at origin: NSPoint, offset: Double) -> NSView {
        let dot = NSView(frame: NSRect(origin: origin, size: NSSize(width: 6, height: 6)))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor

        let anim = CAKeyframeAnimation(keyPath: "transform.translation.y")
        anim.values = [0, -5, 0]
        anim.keyTimes = [0, 0.5, 1.0]
        anim.duration = 0.9
        anim.timeOffset = offset
        anim.repeatCount = .infinity
        dot.layer?.add(anim, forKey: "bounce")
        return dot
    }

    // MARK: Window + view helpers (mirror of Picker.swift's private helpers)

    private func configureOverlay(_ panel: NSPanel) {
        panel.title = "Penny"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
    }

    private func makeMaterial(frame: NSRect) -> NSView {
        let view = NSVisualEffectView(frame: frame)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        return view
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.backgroundColor = .clear
        return field
    }
}
