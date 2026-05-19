import AppKit

/// Shown on first launch (gated by `~/.penny/.onboarded` flag). Walks
/// the user through granting Accessibility, granting Input Monitoring, and
/// adding an API key. Each step has a status dot that flips green once the
/// corresponding requirement is satisfied.
///
/// Closing the window without finishing is fine: the flag isn't written, so
/// it reappears on next launch.
final class OnboardingWindowController: NSWindowController {
    private let prefsController: PreferencesWindowController
    private var rows: [StepRow] = []
    private var refreshTimer: Timer?

    init(prefsController: PreferencesWindowController) {
        self.prefsController = prefsController

        let window = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Penny"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.contentView = buildContentView()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    static func shouldShow() -> Bool {
        !FileManager.default.fileExists(atPath: flagPath())
    }

    static func markOnboarded() {
        let path = flagPath()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data())
    }

    private static func flagPath() -> String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent(".penny/.onboarded")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Poll every 1.5s so the green dots flip without the user clicking.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    // MARK: Layout

    private func buildContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Welcome to Penny")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = .controlAccentColor
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "Three quick steps and you’re set. We’ll let you know when each is done.")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        let accessibilityRow = StepRow(
            number: 1,
            title: "Grant Accessibility",
            detail: "Lets Penny detect Right Option and replace selected text in any app.",
            actionTitle: "Grant…",
            action: #selector(grantAccessibility),
            target: self
        )
        let inputRow = StepRow(
            number: 2,
            title: "Grant Input Monitoring",
            detail: "Lets Penny listen for the trigger key. macOS requires this in addition to Accessibility.",
            actionTitle: "Grant…",
            action: #selector(grantInputMonitoring),
            target: self
        )
        let micRow = StepRow(
            number: 3,
            title: "Grant Microphone access",
            detail: "Used only while you hold Right Option to dictate. Audio is transcribed locally on your Mac.",
            actionTitle: "Grant…",
            action: #selector(grantMicrophone),
            target: self
        )
        let apiRow = StepRow(
            number: 4,
            title: "Add your Anthropic API key",
            detail: "Stored only in macOS Keychain. Opens the Preferences window so you can paste it in.",
            actionTitle: "Open…",
            action: #selector(openPreferences),
            target: self
        )
        rows = [accessibilityRow, inputRow, micRow, apiRow]

        for row in rows {
            stack.addArrangedSubview(row.view)
        }

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "You can finish later — this window reappears next launch until you press Done.")
        hint.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        hint.textColor = .tertiaryLabelColor

        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.identifier = NSUserInterfaceItemIdentifier("done")

        footer.addArrangedSubview(hint)
        footer.addArrangedSubview(NSView()) // spacer
        footer.addArrangedSubview(done)

        stack.addArrangedSubview(footer)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
        ])

        return container
    }

    // MARK: Actions

    @objc private func grantAccessibility() {
        Permissions.requestPrompt(for: .accessibility)
        Permissions.openSystemSettings(for: .accessibility)
    }

    @objc private func grantInputMonitoring() {
        Permissions.requestPrompt(for: .inputMonitoring)
        Permissions.openSystemSettings(for: .inputMonitoring)
    }

    @objc private func grantMicrophone() {
        Permissions.requestPrompt(for: .microphone)
        Permissions.openSystemSettings(for: .microphone)
    }

    @objc private func openPreferences() {
        prefsController.showWindow(nil)
        prefsController.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func finish() {
        OnboardingWindowController.markOnboarded()
        close()
    }

    // MARK: Refresh

    private func refresh() {
        rows[0].isComplete = Permissions.isGranted(.accessibility)
        rows[1].isComplete = Permissions.isGranted(.inputMonitoring)
        rows[2].isComplete = Permissions.isGranted(.microphone)
        rows[3].isComplete = (Keychain.read(account: "anthropic")?.isEmpty == false)
    }
}

/// One row of the onboarding checklist. Holds its own status dot, labels,
/// and action button. `isComplete` toggles the dot colour and tones the
/// row down once the step has been satisfied.
final class StepRow {
    let view: NSView
    private let dot: NSView

    var isComplete: Bool = false {
        didSet {
            dot.layer?.backgroundColor = (isComplete
                ? NSColor.systemGreen
                : NSColor.tertiaryLabelColor).cgColor
        }
    }

    init(
        number: Int,
        title: String,
        detail: String,
        actionTitle: String,
        action: Selector,
        target: AnyObject
    ) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        dot.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        self.dot = dot

        let titleLabel = NSTextField(labelWithString: "\(number). \(title)")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 360
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let actionButton = NSButton(title: actionTitle, target: target, action: action)
        actionButton.bezelStyle = .rounded
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(dot)
        container.addSubview(titleLabel)
        container.addSubview(detailLabel)
        container.addSubview(actionButton)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),
            dot.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dot.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),

            titleLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            actionButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            container.widthAnchor.constraint(equalToConstant: 470),
        ])

        self.view = container
    }
}
