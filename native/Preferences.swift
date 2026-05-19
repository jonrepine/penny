import AppKit

/// Preferences window. Opened from the menu bar entry. Renders four sections
/// stacked vertically inside an `NSVisualEffectView`: Status, AI Provider,
/// General, and Modes. Saves are explicit per section.
final class PreferencesWindowController: NSWindowController {
    // Window + content metrics. Document view = window content width minus
    // the vertical scroller, so nothing horizontally clips. All inner
    // controls cap themselves at `contentWidth` so the layout never
    // overflows on the right or scrolls horizontally.
    private static let windowWidth: CGFloat = 620
    private static let windowHeight: CGFloat = 720
    private static let scrollerInset: CGFloat = 16
    private static let documentWidth: CGFloat = windowWidth - scrollerInset
    private static let outerInset: CGFloat = 24
    private static let contentWidth: CGFloat = documentWidth - outerInset * 2

    private let appDir: String
    private let helper: RefinerHelper
    private var styleEditor: StyleEditorWindowController?
    private var config: AppConfig

    // Provider section
    private var providerPicker: NSPopUpButton!
    private var apiKeyField: NSSecureTextField!
    private var modelPicker: NSPopUpButton!
    private var modelBlurb: NSTextField!
    private var customSlugField: NSTextField!

    // Dictation section
    private var whisperPicker: NSPopUpButton!
    private var whisperBlurb: NSTextField!

    // Modes / status
    private var modesTable: NSTableView!
    private var statusLabel: NSTextField!

    init(appDir: String, helper: RefinerHelper) {
        self.appDir = appDir
        self.helper = helper
        self.config = ConfigStore.load(appDir: appDir)

        let window = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Penny Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.contentView = buildContentView()
        refreshStatus()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Layout

    private func buildContentView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(
            top: Self.outerInset,
            left: Self.outerInset,
            bottom: Self.outerInset,
            right: Self.outerInset
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(buildStatusSection())
        stack.addArrangedSubview(buildProviderSection())
        stack.addArrangedSubview(buildDictationSection())
        stack.addArrangedSubview(buildGeneralSection())
        stack.addArrangedSubview(buildModesSection())

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalToConstant: Self.documentWidth),
        ])
        scroll.documentView = documentView

        return scroll
    }

    private func buildSectionHeader(_ title: String) -> NSView {
        // Header uses the system accent colour as the one functional pop of
        // colour, consistent with the picker title.
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .controlAccentColor
        return label
    }

    /// Builds a field row: an optional caption above, the control, and an
    /// optional wrapping help-text caption below. All elements share the
    /// same leading edge inside their stack so columns line up across
    /// sections.
    private func buildField(_ label: String, control: NSView, helpText: String? = nil) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        labelView.textColor = .labelColor
        stack.addArrangedSubview(labelView)

        stack.addArrangedSubview(control)

        if let helpText {
            let help = NSTextField(wrappingLabelWithString: helpText)
            help.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            help.textColor = .secondaryLabelColor
            help.preferredMaxLayoutWidth = Self.contentWidth
            stack.addArrangedSubview(help)
        }
        return stack
    }

    // MARK: Status section

    private func buildStatusSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(buildSectionHeader("Status"))

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .labelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.preferredMaxLayoutWidth = Self.contentWidth
        stack.addArrangedSubview(statusLabel)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshStatus))
        let openPrefs = NSButton(title: "Open Privacy Settings", target: self, action: #selector(openPrivacyPane))
        row.addArrangedSubview(refresh)
        row.addArrangedSubview(openPrefs)
        stack.addArrangedSubview(row)

        return stack
    }

    @objc private func refreshStatus() {
        let a11y = Permissions.isGranted(.accessibility)
        let im   = Permissions.isGranted(.inputMonitoring)
        let mic  = Permissions.isGranted(.microphone)
        let dot: (Bool) -> String = { $0 ? "\u{2713}" : "\u{2717}" }
        let lines = [
            "\(dot(a11y)) Accessibility",
            "\(dot(im)) Input Monitoring",
            "\(dot(mic)) Microphone",
        ]
        statusLabel.stringValue = lines.joined(separator: "    ")
    }

    @objc private func openPrivacyPane() {
        // Accessibility is the most common one users need to revisit.
        Permissions.openSystemSettings(for: .accessibility)
    }

    // MARK: Provider section

    private func buildProviderSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(buildSectionHeader("AI Provider"))

        // Provider picker — populated from Providers.all.
        providerPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        for provider in Providers.all {
            providerPicker.addItem(withTitle: provider.label)
            providerPicker.lastItem?.representedObject = provider.id
        }
        if let current = Providers.provider(id: config.llmProvider),
           let item = providerPicker.itemArray.first(where: { ($0.representedObject as? String) == current.id }) {
            providerPicker.select(item)
        }
        providerPicker.target = self
        providerPicker.action = #selector(providerChanged(_:))
        stack.addArrangedSubview(buildField("Provider", control: providerPicker))

        // API key field + Save button on one row. "Get an API key…" sits
        // below as a subtle accessory link so the row width never exceeds
        // the available content area.
        apiKeyField = NSSecureTextField()
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.widthAnchor.constraint(equalToConstant: Self.contentWidth - 96).isActive = true

        let saveKey = NSButton(title: "Save key", target: self, action: #selector(saveAPIKey))
        saveKey.bezelStyle = .rounded

        let apiRow = NSStackView(views: [apiKeyField, saveKey])
        apiRow.orientation = .horizontal
        apiRow.spacing = 8
        apiRow.alignment = .firstBaseline

        stack.addArrangedSubview(buildField(
            "API Key (stored only in macOS Keychain)",
            control: apiRow,
            helpText: "Saved under service “penny”, account = provider name. Not written to disk."
        ))

        let getKey = NSButton(title: "Get an API key for this provider →", target: self, action: #selector(openSignupURL))
        getKey.bezelStyle = .accessoryBarAction
        getKey.isBordered = false
        getKey.contentTintColor = .controlAccentColor
        stack.addArrangedSubview(getKey)

        // Model picker for the selected provider.
        modelPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPicker.target = self
        modelPicker.action = #selector(modelChanged(_:))
        stack.addArrangedSubview(buildField("Model", control: modelPicker))

        // Recommendation blurb that updates with the selected model.
        modelBlurb = NSTextField(wrappingLabelWithString: "")
        modelBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        modelBlurb.textColor = .secondaryLabelColor
        modelBlurb.preferredMaxLayoutWidth = Self.contentWidth
        stack.addArrangedSubview(modelBlurb)

        // Custom slug input (revealed when "Custom slug…" is chosen).
        customSlugField = NSTextField()
        customSlugField.placeholderString = "exact model identifier"
        customSlugField.translatesAutoresizingMaskIntoConstraints = false
        customSlugField.widthAnchor.constraint(equalToConstant: Self.contentWidth - 96).isActive = true
        customSlugField.target = self
        customSlugField.action = #selector(customSlugChanged(_:))
        customSlugField.isHidden = true
        stack.addArrangedSubview(customSlugField)

        applyCurrentProvider()
        return stack
    }

    /// Reset the API key field, model dropdown, and blurb to reflect whichever
    /// provider is currently selected.
    private func applyCurrentProvider() {
        guard let providerID = currentProviderID,
              let provider = Providers.provider(id: providerID)
        else { return }

        // API key for this provider, pulled from Keychain.
        apiKeyField.placeholderString = provider.placeholder
        apiKeyField.stringValue = Keychain.read(account: provider.id) ?? ""

        // Repopulate model dropdown.
        modelPicker.removeAllItems()
        for option in provider.models {
            modelPicker.addItem(withTitle: option.label)
            modelPicker.lastItem?.representedObject = option.id
        }
        modelPicker.addItem(withTitle: "Custom slug…")
        modelPicker.lastItem?.representedObject = "__custom__"

        // Pick whichever item matches the current `config.model`, otherwise
        // fall back to the provider's first (recommended) option.
        if let match = modelPicker.itemArray.first(where: { ($0.representedObject as? String) == config.model }) {
            modelPicker.select(match)
            customSlugField.isHidden = true
        } else if !config.model.isEmpty {
            modelPicker.selectItem(withTitle: "Custom slug…")
            customSlugField.stringValue = config.model
            customSlugField.isHidden = false
        } else {
            modelPicker.selectItem(at: 0)
            config.model = provider.models.first?.id ?? ""
            customSlugField.isHidden = true
            persist()
        }
        updateModelBlurb()
    }

    private func updateModelBlurb() {
        guard let providerID = currentProviderID,
              let provider = Providers.provider(id: providerID),
              let selectedID = modelPicker.selectedItem?.representedObject as? String
        else {
            modelBlurb.stringValue = ""
            return
        }
        if selectedID == "__custom__" {
            modelBlurb.stringValue = "Type the model slug exactly as the provider expects."
            return
        }
        modelBlurb.stringValue = provider.models.first { $0.id == selectedID }?.blurb ?? ""
    }

    private var currentProviderID: String? {
        providerPicker.selectedItem?.representedObject as? String
    }

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        config.llmProvider = id
        // Reset to provider's recommended model on switch.
        if let recommended = Providers.provider(id: id)?.models.first {
            config.model = recommended.id
        }
        persist()
        applyCurrentProvider()
    }

    @objc private func openSignupURL() {
        guard let id = currentProviderID,
              let provider = Providers.provider(id: id),
              let url = URL(string: provider.signupURL)
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func saveAPIKey() {
        guard let provider = currentProviderID else { return }
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            Picker.showToast("Enter an API key first", duration: 1.4)
            return
        }
        if Keychain.write(account: provider, value: key) {
            Picker.showToast("API key saved", duration: 1.0)
        } else {
            Picker.showToast("Couldn’t save to Keychain", duration: 1.6)
        }
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        if id == "__custom__" {
            customSlugField.isHidden = false
            customSlugField.window?.makeFirstResponder(customSlugField)
            updateModelBlurb()
            return
        }
        customSlugField.isHidden = true
        config.model = id
        updateModelBlurb()
        persist()
    }

    @objc private func customSlugChanged(_ sender: NSTextField) {
        let value = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        config.model = value
        persist()
    }

    // MARK: Dictation section

    private func buildDictationSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(buildSectionHeader("Dictation (Whisper)"))

        whisperPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        for option in WhisperModels.all {
            whisperPicker.addItem(withTitle: option.label)
            whisperPicker.lastItem?.representedObject = option.id
        }
        if let item = whisperPicker.itemArray.first(where: { ($0.representedObject as? String) == config.whisperModel }) {
            whisperPicker.select(item)
        }
        whisperPicker.target = self
        whisperPicker.action = #selector(whisperModelChanged(_:))
        stack.addArrangedSubview(buildField("Whisper model", control: whisperPicker))

        whisperBlurb = NSTextField(wrappingLabelWithString: "")
        whisperBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        whisperBlurb.textColor = .secondaryLabelColor
        whisperBlurb.preferredMaxLayoutWidth = Self.contentWidth
        stack.addArrangedSubview(whisperBlurb)

        let ramText = NSTextField(labelWithString:
            String(format: "Detected %.0f GB of RAM. Larger models give better accuracy but use more memory and disk.", SystemInfo.totalRAMGigabytes()))
        ramText.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        ramText.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(ramText)

        updateWhisperBlurb()
        return stack
    }

    private func updateWhisperBlurb() {
        guard let id = whisperPicker.selectedItem?.representedObject as? String,
              let option = WhisperModels.option(id: id) else { return }
        whisperBlurb.stringValue = option.blurb
    }

    @objc private func whisperModelChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        config.whisperModel = id
        persist()
        updateWhisperBlurb()
        // Restart the dictation daemon so it reloads the new model.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(getuid())/com.penny.dictate"]
        try? task.run()
    }

    // MARK: General section

    private func buildGeneralSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(buildSectionHeader("General"))

        let tokensRow = buildSteppedNumberField(
            label: "Max tokens",
            value: config.maxTokens,
            range: 32...8192
        ) { [weak self] value in
            self?.config.maxTokens = value
            self?.persist()
        }
        stack.addArrangedSubview(tokensRow)

        let timeoutRow = buildSteppedNumberField(
            label: "Timeout (seconds)",
            value: config.timeoutSeconds,
            range: 5...180
        ) { [weak self] value in
            self?.config.timeoutSeconds = value
            self?.persist()
        }
        stack.addArrangedSubview(timeoutRow)

        let historySwitch = NSSwitch()
        historySwitch.state = config.saveHistory ? .on : .off
        historySwitch.target = self
        historySwitch.action = #selector(historyToggled(_:))
        let historyRow = NSStackView()
        historyRow.orientation = .horizontal
        historyRow.spacing = 12
        historyRow.addArrangedSubview(historySwitch)
        let historyLabel = NSTextField(labelWithString: "Save history (~/.penny/history.json)")
        historyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        historyRow.addArrangedSubview(historyLabel)
        stack.addArrangedSubview(historyRow)

        let historyLimitRow = buildSteppedNumberField(
            label: "History limit",
            value: config.historyLimit,
            range: 0...500
        ) { [weak self] value in
            self?.config.historyLimit = value
            self?.persist()
        }
        stack.addArrangedSubview(historyLimitRow)

        let toastSwitch = NSSwitch()
        toastSwitch.state = config.showToasts ? .on : .off
        toastSwitch.target = self
        toastSwitch.action = #selector(toastsToggled(_:))
        let toastRow = NSStackView()
        toastRow.orientation = .horizontal
        toastRow.spacing = 12
        toastRow.addArrangedSubview(toastSwitch)
        let toastLabel = NSTextField(labelWithString: "Show confirmation toasts")
        toastLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        toastRow.addArrangedSubview(toastLabel)
        stack.addArrangedSubview(toastRow)

        return stack
    }

    private func buildSteppedNumberField(
        label: String,
        value: Int,
        range: ClosedRange<Int>,
        onChange: @escaping (Int) -> Void
    ) -> NSView {
        let field = NSTextField()
        field.stringValue = String(value)
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let stepper = NSStepper()
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.integerValue = value

        let handler = StepperHandler(field: field, stepper: stepper, range: range, onChange: onChange)
        field.target = handler
        field.action = #selector(StepperHandler.fieldChanged(_:))
        stepper.target = handler
        stepper.action = #selector(StepperHandler.stepperChanged(_:))
        // Retain the handler via associated objects on the stepper.
        objc_setAssociatedObject(stepper, &StepperHandler.key, handler, .OBJC_ASSOCIATION_RETAIN)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.addArrangedSubview(field)
        row.addArrangedSubview(stepper)

        return buildField(label, control: row)
    }

    @objc private func historyToggled(_ sender: NSSwitch) {
        config.saveHistory = sender.state == .on
        persist()
    }

    @objc private func toastsToggled(_ sender: NSSwitch) {
        config.showToasts = sender.state == .on
        persist()
    }

    // MARK: Modes section

    private func buildModesSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(buildSectionHeader("Modes"))

        modesTable = NSTableView()
        modesTable.dataSource = self
        modesTable.delegate = self
        modesTable.rowHeight = 24
        modesTable.allowsMultipleSelection = false
        modesTable.usesAlternatingRowBackgroundColors = true
        modesTable.style = .inset

        let idColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("id"))
        idColumn.title = "#"
        idColumn.width = 28
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 180
        let detailColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
        detailColumn.title = "Description"
        detailColumn.width = 300
        let lockedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("locked"))
        lockedColumn.title = ""
        lockedColumn.width = 32
        modesTable.addTableColumn(idColumn)
        modesTable.addTableColumn(nameColumn)
        modesTable.addTableColumn(detailColumn)
        modesTable.addTableColumn(lockedColumn)

        let scroll = NSScrollView()
        scroll.documentView = modesTable
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 260).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        stack.addArrangedSubview(scroll)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        let addButton = NSButton(title: "Add…", target: self, action: #selector(addMode))
        let editButton = NSButton(title: "Edit…", target: self, action: #selector(editMode))
        let stylesButton = NSButton(title: "Examples & rules…", target: self, action: #selector(editStyleExamples))
        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteMode))
        buttonRow.addArrangedSubview(addButton)
        buttonRow.addArrangedSubview(editButton)
        buttonRow.addArrangedSubview(stylesButton)
        buttonRow.addArrangedSubview(deleteButton)
        stack.addArrangedSubview(buttonRow)

        return stack
    }

    @objc private func addMode() {
        let nextId = (0...9).first { id in
            !Modes.all.contains(where: { $0.id == id })
        }
        guard let id = nextId else {
            Picker.showToast("Picker already has 10 modes", duration: 1.6)
            return
        }
        let blank = Mode(id: id, name: "New mode", detail: "", prompt: "")
        ModeEditor.present(mode: blank, parent: window) { [weak self] edited in
            guard let self, let edited else { return }
            var updated = Modes.all
            updated.append(edited)
            self.save(modes: updated)
        }
    }

    @objc private func editMode() {
        let row = modesTable.selectedRow
        guard row >= 0, row < Modes.all.count else { return }
        let mode = Modes.all[row]
        ModeEditor.present(mode: mode, parent: window) { [weak self] edited in
            guard let self, let edited else { return }
            var updated = Modes.all
            updated[row] = edited
            self.save(modes: updated)
        }
    }

    @objc private func editStyleExamples() {
        let row = modesTable.selectedRow
        guard row >= 0, row < Modes.all.count else {
            Picker.showToast("Pick a mode first", duration: 1.4)
            return
        }
        let mode = Modes.all[row]
        if mode.isCancel || mode.isCustom {
            Picker.showToast("This mode doesn’t take style examples", duration: 1.6)
            return
        }
        styleEditor = StyleEditorWindowController(mode: mode, helper: helper)
        styleEditor?.showWindow(nil)
        styleEditor?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func deleteMode() {
        let row = modesTable.selectedRow
        guard row >= 0, row < Modes.all.count else { return }
        let mode = Modes.all[row]

        if mode.locked {
            Picker.showToast("That mode is locked", duration: 1.4)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete “\(mode.name)”?"
        alert.informativeText = "This removes the mode from your picker."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var updated = Modes.all
        updated.remove(at: row)
        save(modes: updated)
    }

    private func save(modes: [Mode]) {
        do {
            try Modes.save(modes)
            modesTable.reloadData()
        } catch {
            Picker.showToast("Failed to save modes", duration: 1.8)
            log("Failed to save modes: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            try ConfigStore.save(config)
        } catch {
            log("Failed to save config: \(error.localizedDescription)")
        }
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        Modes.all.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let mode = Modes.all[row]
        let identifier = NSUserInterfaceItemIdentifier("cell-\(column.identifier.rawValue)")
        let cell: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
            cell = reused
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = identifier
            cell.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        }
        switch column.identifier.rawValue {
        case "id":     cell.stringValue = String(mode.id)
        case "name":   cell.stringValue = mode.name
        case "detail": cell.stringValue = mode.detail
        case "locked": cell.stringValue = mode.locked ? "\u{1F512}" : ""
        default:       cell.stringValue = ""
        }
        cell.textColor = mode.locked ? .secondaryLabelColor : .labelColor
        return cell
    }
}

/// Helper that links an NSStepper and NSTextField so they stay in sync and
/// invoke `onChange` whenever the user adjusts the value.
final class StepperHandler: NSObject {
    static var key: UInt8 = 0
    private weak var field: NSTextField?
    private weak var stepper: NSStepper?
    private let range: ClosedRange<Int>
    private let onChange: (Int) -> Void

    init(field: NSTextField, stepper: NSStepper, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) {
        self.field = field
        self.stepper = stepper
        self.range = range
        self.onChange = onChange
    }

    @objc func fieldChanged(_ sender: NSTextField) {
        let raw = Int(sender.stringValue) ?? range.lowerBound
        let clamped = max(range.lowerBound, min(range.upperBound, raw))
        sender.stringValue = String(clamped)
        stepper?.integerValue = clamped
        onChange(clamped)
    }

    @objc func stepperChanged(_ sender: NSStepper) {
        let clamped = max(range.lowerBound, min(range.upperBound, sender.integerValue))
        field?.stringValue = String(clamped)
        onChange(clamped)
    }
}

/// Modal sheet for editing a single mode. Locked modes only allow detail and
/// prompt edits; protected modes (`isCustom` / `isCancel`) cannot have their
/// flags changed via this UI.
enum ModeEditor {
    static func present(mode: Mode, parent: NSWindow?, onComplete: @escaping (Mode?) -> Void) {
        let alert = NSAlert()
        alert.messageText = mode.id == -1 ? "New Mode" : "Edit Mode “\(mode.name)”"
        alert.informativeText = "Name, description, and the system prompt this mode sends to the LLM."

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        func labeledField(_ title: String, _ field: NSView) -> NSView {
            let lbl = NSTextField(labelWithString: title)
            lbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            lbl.textColor = .secondaryLabelColor
            let group = NSStackView()
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 4
            group.addArrangedSubview(lbl)
            group.addArrangedSubview(field)
            return group
        }

        let nameField = NSTextField()
        nameField.stringValue = mode.name
        nameField.isEnabled = !mode.locked
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 420).isActive = true

        let detailField = NSTextField()
        detailField.stringValue = mode.detail
        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.widthAnchor.constraint(equalToConstant: 420).isActive = true

        let promptView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        promptView.isRichText = false
        promptView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        promptView.string = mode.prompt
        promptView.isEditable = !mode.isCancel && !mode.isCustom

        let promptScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        promptScroll.hasVerticalScroller = true
        promptScroll.documentView = promptView
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        promptScroll.heightAnchor.constraint(equalToConstant: 200).isActive = true

        stack.addArrangedSubview(labeledField("Name", nameField))
        stack.addArrangedSubview(labeledField("Description (shown on the right side of the row)", detailField))
        stack.addArrangedSubview(labeledField("System prompt", promptScroll))

        if mode.locked {
            let note = NSTextField(labelWithString: "This mode is locked. The name and core behaviour can’t be changed.")
            note.font = NSFont.systemFont(ofSize: 11)
            note.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(note)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 320))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        alert.accessoryView = container

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response: NSApplication.ModalResponse
        if let parent {
            response = alert.beginSheetSync(for: parent)
        } else {
            response = alert.runModal()
        }
        guard response == .alertFirstButtonReturn else {
            onComplete(nil)
            return
        }

        let edited = Mode(
            id: mode.id,
            name: mode.locked ? mode.name : nameField.stringValue,
            detail: detailField.stringValue,
            isCustom: mode.isCustom,
            isCancel: mode.isCancel,
            locked: mode.locked,
            prompt: (mode.isCancel || mode.isCustom) ? mode.prompt : promptView.string
        )
        onComplete(edited)
    }
}

extension NSAlert {
    /// Runs the alert as a sheet attached to `window` and blocks until the
    /// user responds. Used so the mode editor stays modal over the
    /// preferences window without freezing the rest of the app.
    func beginSheetSync(for window: NSWindow) -> NSApplication.ModalResponse {
        var result: NSApplication.ModalResponse = .cancel
        beginSheetModal(for: window) { response in
            result = response
            NSApp.stopModal()
        }
        NSApp.runModal(for: window)
        return result
    }
}
