import AppKit

/// Renders the "Listening" and "Transcribing" overlays during dictation.
///
/// The dictation daemon lives in a separate Python process and publishes
/// state to small files in `~/.penny/`:
///
///   - `dictate.state` is one of `listening` / `transcribing` / `idle`.
///   - `dictate.transcript` is the running text Whisper has produced so far
///     while the user is still holding the key.
///
/// We poll both files on a fast timer (100 ms for state, same loop reads
/// the transcript) and render them. The transcript pane gives the user a
/// live view of what's being captured without us having to type into their
/// app during the hold (the Right Option modifier being physically held
/// would garble any synthesized keystrokes).
final class DictationOverlay {
    private static let statePath: String = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".penny/dictate.state")
    private static let transcriptPath: String = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".penny/dictate.transcript")

    private var panel: NSPanel?
    private var transcriptLabel: NSTextField?
    private var pollTimer: Timer?
    private var slowHintTimer: Timer?
    private var lastState: String = ""
    private var lastTranscript: String = ""

    /// How long the user has to wait before the "smaller model" tip fades
    /// in during a Transcribing overlay. Tuned to never fire on fast
    /// (tiny.en / base.en / small.en) transcriptions and almost always
    /// fire on distil-large-v3 or medium.en for longer recordings.
    private static let slowHintDelay: TimeInterval = 3.0

    init() {
        ensureStateFileExists()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
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
        guard let raw = try? String(contentsOfFile: Self.statePath, encoding: .utf8) else { return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value != lastState {
            lastState = value
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch value {
                case "listening":    self.show(.listening)
                case "transcribing": self.show(.transcribing)
                default:              self.hide()
                }
            }
        }

        // While listening, also pick up transcript updates and feed them
        // into the live preview label.
        if value == "listening", let transcript = try? String(contentsOfFile: Self.transcriptPath, encoding: .utf8) {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != lastTranscript {
                lastTranscript = trimmed
                DispatchQueue.main.async { [weak self] in
                    self?.transcriptLabel?.stringValue = trimmed
                }
            }
        }
    }

    // MARK: Presentation

    private enum Mode { case listening, transcribing }

    private func show(_ mode: Mode) {
        hide()
        lastTranscript = ""

        switch mode {
        case .listening:   showListening()
        case .transcribing: showTranscribing()
        }
    }

    private func showListening() {
        let width: CGFloat = 380
        let headerHeight: CGFloat = 38
        let transcriptHeight: CGFloat = 56
        let footerHeight: CGFloat = 22
        let totalHeight = headerHeight + transcriptHeight + footerHeight

        let p = makePanel(width: width, height: totalHeight)
        let content = Style.makeMaterialView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))

        // Header row: pulsing red dot + "Listening" label.
        content.addSubview(makePulsingDot(at: NSPoint(x: 18, y: totalHeight - headerHeight + 13)))
        let header = Style.plainLabel("Listening", size: 12, weight: .medium, color: .labelColor)
        header.frame = NSRect(x: 38, y: totalHeight - headerHeight + 11, width: 320, height: 16)
        content.addSubview(header)

        // Transcript pane: wrapping label below the header. Updates in
        // place as the streaming worker publishes new text.
        let transcript = NSTextField(wrappingLabelWithString: "")
        transcript.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        transcript.textColor = .secondaryLabelColor
        transcript.preferredMaxLayoutWidth = width - 36
        transcript.maximumNumberOfLines = 3
        transcript.lineBreakMode = .byTruncatingHead
        transcript.frame = NSRect(x: 18, y: footerHeight, width: width - 36, height: transcriptHeight)
        transcript.placeholderString = "Talk now…"
        content.addSubview(transcript)
        transcriptLabel = transcript

        // Footer caption: makes the speed/accuracy split unmistakable.
        // Live preview uses a small fast model; the actual paste on
        // release uses the higher-quality "Final transcription model"
        // configured in Preferences.
        let footer = Style.plainLabel(
            "Live preview · final paste is more accurate",
            size: 10, weight: .regular, color: .tertiaryLabelColor
        )
        footer.alignment = .center
        footer.frame = NSRect(x: 18, y: 4, width: width - 36, height: 14)
        content.addSubview(footer)

        p.contentView = content
        p.orderFrontRegardless()
        panel = p
    }

    private func showTranscribing() {
        let width: CGFloat = 380
        let height: CGFloat = 62
        let p = makePanel(width: width, height: height)
        let content = Style.makeMaterialView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Bouncing dots + "Transcribing" label sit at the top of the panel.
        let topY = height - 22
        for index in 0..<3 {
            content.addSubview(makeBouncingDot(at: NSPoint(x: 18 + CGFloat(index) * 11, y: topY),
                                               offset: Double(index) * 0.18))
        }
        let label = Style.plainLabel("Transcribing", size: 12, weight: .medium, color: .labelColor)
        label.frame = NSRect(x: 60, y: topY - 5, width: 240, height: 16)
        content.addSubview(label)

        // Hint sits at the bottom of the panel, invisible at first. Only
        // fades in if the transcription is still running after
        // `slowHintDelay` seconds — fast pastes never see it.
        let hint = Style.plainLabel(
            "Want it faster? Pick a smaller model in Preferences",
            size: 10, weight: .regular, color: .tertiaryLabelColor
        )
        hint.alignment = .center
        hint.frame = NSRect(x: 18, y: 8, width: width - 36, height: 14)
        hint.alphaValue = 0
        content.addSubview(hint)

        slowHintTimer?.invalidate()
        slowHintTimer = Timer.scheduledTimer(withTimeInterval: Self.slowHintDelay, repeats: false) { [weak hint] _ in
            guard let hint else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                hint.animator().alphaValue = 1.0
            }
        }

        p.contentView = content
        p.orderFrontRegardless()
        panel = p
    }

    private func hide() {
        slowHintTimer?.invalidate()
        slowHintTimer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        transcriptLabel = nil
    }

    private func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - width / 2, y: frame.minY + 100)

        let p = OverlayPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Style.configureOverlayPanel(p)
        return p
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
}
