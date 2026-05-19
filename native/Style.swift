import AppKit

/// All visual constants and reusable AppKit factories for Penny's overlays.
///
/// Centralising these means the picker, the toast, the dictation overlays,
/// and the preferences/onboarding windows can't drift apart visually as we
/// edit them. macOS HIG conventions:
///
/// - System font sizes: 11 (caption), 12 (body), 13 (default control), 15 (headings).
/// - `NSStackView` spacing is the dominant gutter between siblings.
/// - Window paddings are uniform on all four sides for non-document windows.
/// - System colors (`.labelColor`, `.secondaryLabelColor`, `.controlAccentColor`,
///   etc.) only — no custom hex values.
enum Style {
    enum Metrics {
        static let cornerRadiusOverlay: CGFloat = 16
        static let cornerRadiusRow: CGFloat = 10

        static let sectionSpacing: CGFloat = 18
        static let rowSpacing: CGFloat = 12
        static let tightSpacing: CGFloat = 8

        static let windowInset: CGFloat = 20
        static let panelSideInset: CGFloat = 12
        static let panelTopInset: CGFloat = 10
    }

    // MARK: Overlay window styling

    static func configureOverlayPanel(_ panel: NSPanel) {
        panel.title = "Penny"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
    }

    static func makeMaterialView(frame: NSRect, cornerRadius: CGFloat = Metrics.cornerRadiusOverlay) -> NSView {
        let view = NSVisualEffectView(frame: frame)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        return view
    }

    // MARK: Labels

    static func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .controlAccentColor
        return label
    }

    static func bodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        return label
    }

    static func captionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }

    static func plainLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.backgroundColor = .clear
        return field
    }
}
