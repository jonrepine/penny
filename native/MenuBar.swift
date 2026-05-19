import AppKit

/// The macOS menu bar entry for Penny. Lives in the status bar at the
/// top right of the screen, with a small menu for preferences and quit.
final class MenuBar: NSObject {
    private let statusItem: NSStatusItem
    private weak var prefsController: PreferencesWindowController?

    init(prefsController: PreferencesWindowController) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.prefsController = prefsController
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            // Stylised mark: "T·R" in a small monospaced cap. Keeps the icon
            // recognisable even when there's no SF Symbol available.
            button.image = renderIcon()
            button.image?.isTemplate = true
            button.toolTip = "Penny"
        }

        let menu = NSMenu()
        menu.addItem(buildItem(
            title: "Preferences\u{2026}",
            keyEquivalent: ",",
            action: #selector(openPreferences)
        ))
        menu.addItem(buildItem(
            title: "Open Log",
            keyEquivalent: "",
            action: #selector(openLog)
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildItem(
            title: "Quit Penny",
            keyEquivalent: "q",
            action: #selector(quit)
        ))
        statusItem.menu = menu
    }

    private func buildItem(title: String, keyEquivalent: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func renderIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
            let text = NSAttributedString(string: "TR", attributes: attrs)
            let textSize = text.size()
            let origin = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2
            )
            text.draw(at: origin)
            return true
        }
        return image
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        prefsController?.showWindow(nil)
        prefsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openLog() {
        let logPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".penny/refiner.log")
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Defensive: dismiss our status menu before showing the picker. macOS
    /// will sometimes leave the dropdown tracked if the user just opened
    /// (and didn't dismiss) the menu before triggering the shortcut, which
    /// caused both menus to compete for input.
    func dismissMenu() {
        statusItem.menu?.cancelTracking()
    }
}
