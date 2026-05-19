import AppKit

/// Result of presenting the picker.
struct PickerChoice {
    let mode: Mode
    let customPrompt: String?
}

/// An NSPanel that can become the key window even though it's borderless and
/// non-activating. Without this override, digit shortcuts on buttons never
/// fire because the panel doesn't receive keyboard events.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the picker presentation. Builds a small AppKit panel that lives over
/// fullscreen Spaces and returns the chosen `Mode` (with an optional custom
/// prompt if the user picked Custom).
enum Picker {
    // Consistent metrics. All paddings come from here so nothing drifts.
    private enum Metrics {
        static let panelWidth: CGFloat = 420
        static let headerHeight: CGFloat = 36
        static let rowHeight: CGFloat = 44
        static let rowSpacing: CGFloat = 4
        static let topInset: CGFloat = 10
        static let bottomInset: CGFloat = 10
        static let sideInset: CGFloat = 12
        static let cornerRadius: CGFloat = 16
        static let rowCornerRadius: CGFloat = 10
    }

    static func chooseMode() -> PickerChoice? {
        let controller = ChoiceController()

        let listHeight = CGFloat(Modes.all.count) * Metrics.rowHeight
            + CGFloat(Modes.all.count - 1) * Metrics.rowSpacing
        let totalHeight = Metrics.topInset + Metrics.headerHeight + listHeight + Metrics.bottomInset

        let panel = makePanel(width: Metrics.panelWidth, height: totalHeight)
        controller.panel = panel

        let content = makeMaterialView(
            frame: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: totalHeight)
        )

        addHeader(to: content, height: totalHeight)
        addRows(to: content, controller: controller, totalHeight: totalHeight)

        panel.contentView = content
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                controller.cancel()
                return nil
            }
            return event
        }

        NSApp.runModal(for: panel)
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        return controller.choice
    }

    /// Brief bottom-center toast for completion confirmations. Auto-dismisses
    /// quickly so it doesn't feel like the picker is still on screen.
    static func showToast(_ text: String, duration: TimeInterval = 0.9) {
        let width: CGFloat = 220
        let height: CGFloat = 32
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - width / 2, y: frame.minY + 80)

        let panel = OverlayPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlay(panel)

        let content = makeMaterialView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let textLabel = makeLabel(text, size: 12, weight: .medium, color: .labelColor)
        textLabel.alignment = .center
        textLabel.frame = NSRect(x: 10, y: 8, width: width - 20, height: 16)
        content.addSubview(textLabel)

        panel.contentView = content
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            panel.orderOut(nil)
            panel.close()
        }
    }

    /// Brief status overlay shown while we wait for the LLM. Stored so callers
    /// can dismiss it. All access happens on the main thread.
    nonisolated(unsafe) private static var statusPanel: NSPanel?

    static func showStatus(_ text: String) {
        closeStatus()
        let width: CGFloat = 260
        let height: CGFloat = 44
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - width / 2, y: frame.minY + 130)

        let panel = OverlayPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlay(panel)

        let content = makeMaterialView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Small native spinner. Lightweight, system-rendered, follows the
        // user's appearance automatically.
        let spinner = NSProgressIndicator(frame: NSRect(x: 16, y: (height - 16) / 2, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        content.addSubview(spinner)

        let textLabel = makeLabel(text, size: 12, weight: .medium, color: .labelColor)
        textLabel.alignment = .left
        textLabel.frame = NSRect(x: 40, y: 14, width: width - 56, height: 16)
        content.addSubview(textLabel)

        panel.contentView = content
        statusPanel = panel
        panel.orderFrontRegardless()
    }

    static func closeStatus() {
        statusPanel?.orderOut(nil)
        statusPanel?.close()
        statusPanel = nil
    }

    static func askForCustomPrompt() -> String? {
        let alert = NSAlert()
        alert.messageText = "Custom Instruction"
        alert.informativeText = "Enter the instruction to apply to the selected text."
        alert.addButton(withTitle: "Refine")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Construction helpers

    private static func addHeader(to content: NSView, height totalHeight: CGFloat) {
        // Single, deliberate use of the system accent colour: the wordmark.
        // Everything else uses standard label colours so the panel inherits
        // the user's Light/Dark appearance cleanly.
        let title = makeLabel("Penny", size: 14, weight: .semibold, color: .controlAccentColor)
        title.frame = NSRect(
            x: Metrics.sideInset + 4,
            y: totalHeight - Metrics.topInset - 22,
            width: 160, height: 18
        )
        content.addSubview(title)

        let hint = makeLabel(
            "Double-tap Right Option",
            size: 11, weight: .regular, color: .tertiaryLabelColor
        )
        hint.alignment = .right
        hint.frame = NSRect(
            x: Metrics.panelWidth - 200 - Metrics.sideInset,
            y: totalHeight - Metrics.topInset - 20,
            width: 200, height: 14
        )
        content.addSubview(hint)
    }

    private static func addRows(to content: NSView, controller: ChoiceController, totalHeight: CGFloat) {
        var y = totalHeight - Metrics.topInset - Metrics.headerHeight - Metrics.rowHeight

        for mode in Modes.all {
            let row = makeRow(mode: mode, controller: controller, y: y)
            content.addSubview(row)
            y -= Metrics.rowHeight + Metrics.rowSpacing
        }
    }

    private static func makeRow(mode: Mode, controller: ChoiceController, y: CGFloat) -> NSView {
        let row = NSButton(frame: NSRect(
            x: Metrics.sideInset,
            y: y,
            width: Metrics.panelWidth - Metrics.sideInset * 2,
            height: Metrics.rowHeight
        ))
        row.tag = mode.id
        row.target = controller
        row.action = #selector(ChoiceController.choose(_:))
        row.isBordered = false
        row.title = "" // we use child labels instead so we can use the accent color
        row.keyEquivalent = String(mode.id)
        row.wantsLayer = true
        row.layer?.cornerRadius = Metrics.rowCornerRadius
        row.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(mode.isCancel ? 0.16 : 0.28).cgColor

        // Digit on the left. Subtle (tertiary label) so it doesn't compete
        // with the mode name; the accent colour is reserved for the header.
        let digit = makeLabel(
            String(mode.id),
            size: 13, weight: .medium,
            color: mode.isCancel ? .quaternaryLabelColor : .tertiaryLabelColor
        )
        digit.alignment = .center
        digit.frame = NSRect(x: 14, y: (Metrics.rowHeight - 16) / 2, width: 18, height: 16)
        row.addSubview(digit)

        // Mode name.
        let name = makeLabel(
            mode.name,
            size: 13, weight: mode.isCancel ? .regular : .medium,
            color: mode.isCancel ? .secondaryLabelColor : .labelColor
        )
        name.frame = NSRect(
            x: 44, y: (Metrics.rowHeight - 16) / 2,
            width: 180, height: 16
        )
        row.addSubview(name)

        // Right-aligned detail.
        let detail = makeLabel(
            mode.detail,
            size: 11, weight: .regular, color: .secondaryLabelColor
        )
        detail.alignment = .right
        detail.frame = NSRect(
            x: Metrics.panelWidth - Metrics.sideInset * 2 - 220 - 12,
            y: (Metrics.rowHeight - 14) / 2,
            width: 220, height: 14
        )
        row.addSubview(detail)

        return row
    }

    // MARK: Panel + visual helpers

    private static func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let x = min(max(mouse.x + 12, frame.minX + 12), frame.maxX - width - 12)
        let y = min(max(mouse.y - height - 12, frame.minY + 12), frame.maxY - height - 12)

        let panel = OverlayPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlay(panel)
        return panel
    }

    private static func configureOverlay(_ panel: NSPanel) {
        panel.title = "Penny"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
    }

    private static func makeMaterialView(frame: NSRect) -> NSView {
        let visualEffect = NSVisualEffectView(frame: frame)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Metrics.cornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        return visualEffect
    }

    private static func makeLabel(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.backgroundColor = .clear
        return field
    }
}

/// Bridges Cocoa button actions back into the picker's choice handling.
final class ChoiceController: NSObject {
    var choice: PickerChoice?
    weak var panel: NSPanel?

    @objc func choose(_ sender: NSButton) {
        guard let mode = Modes.all.first(where: { $0.id == sender.tag }) else {
            close()
            return
        }

        if mode.isCancel {
            close()
            return
        }

        if mode.isCustom {
            if let prompt = Picker.askForCustomPrompt() {
                choice = PickerChoice(mode: mode, customPrompt: prompt)
                close()
            }
            return
        }

        choice = PickerChoice(mode: mode, customPrompt: nil)
        close()
    }

    @objc func cancel() {
        close()
    }

    private func close() {
        NSApp.stopModal()
        panel?.orderOut(nil)
        panel?.close()
    }
}
