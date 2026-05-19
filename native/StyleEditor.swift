import AppKit

/// "Style examples & learned rules" editor for a single refinement mode.
///
/// Lets the user paste up to 5 examples of writing they want the LLM to
/// emulate for this mode, then re-extract style rules from those examples.
/// Rules are shown in plain English, editable in place, and persisted to
/// `~/.penny/style-rules.json` so the user has an auditable log of what's
/// influencing their refinements.
///
/// The actual extraction call is delegated to the Python helper via the
/// `extract_rules` action on `refiner_cli.py`. This file is purely UI +
/// persistence; nothing here talks to an LLM directly.
final class StyleEditorWindowController: NSWindowController {
    private let mode: Mode
    private let helper: RefinerHelper

    private var exampleFields: [NSTextField] = []
    private var rulesStack: NSStackView!
    private var ruleFields: [NSTextField] = []
    private var statusLabel: NSTextField!
    private var extractButton: NSButton!
    private var progress: NSProgressIndicator!

    private var loadedRules: [String] = []
    private var deletedRules: Set<String> = []
    private var extractedAt: String = ""

    init(mode: Mode, helper: RefinerHelper) {
        self.mode = mode
        self.helper = helper

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Style examples — \(mode.name)"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating

        super.init(window: window)
        window.contentView = buildContentView()
        loadRules()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildContentView() -> NSView {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 18
        outer.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        outer.translatesAutoresizingMaskIntoConstraints = false

        outer.addArrangedSubview(buildIntro())
        outer.addArrangedSubview(buildExamplesSection())
        outer.addArrangedSubview(buildExtractRow())
        outer.addArrangedSubview(buildRulesSection())
        outer.addArrangedSubview(buildFooter())

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: doc.topAnchor),
            outer.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalToConstant: 560),
        ])
        scroll.documentView = doc
        return scroll
    }

    private func buildIntro() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = Style.plainLabel("Teach Penny your style", size: 15, weight: .semibold, color: .controlAccentColor)
        stack.addArrangedSubview(title)

        let blurb = NSTextField(wrappingLabelWithString:
            "Paste up to 5 examples of writing you want Penny to emulate for the \"\(mode.name)\" mode (your real Slack messages, sent emails, a Notion report you liked, etc.). Click Re-extract and Penny will identify the patterns and apply them to every future \(mode.name) refinement.")
        blurb.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        blurb.textColor = .secondaryLabelColor
        blurb.preferredMaxLayoutWidth = 516
        stack.addArrangedSubview(blurb)

        let optionalNote = Style.plainLabel("Optional. Modes work fine with zero examples.", size: 11, weight: .regular, color: .tertiaryLabelColor)
        stack.addArrangedSubview(optionalNote)
        return stack
    }

    private func buildExamplesSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(Style.sectionHeader("Examples (up to 5)"))

        let existing = mode.examples + Array(repeating: "", count: max(0, 5 - mode.examples.count))
        for (index, text) in existing.prefix(5).enumerated() {
            let row = makeExampleRow(index: index, text: text)
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func makeExampleRow(index: Int, text: String) -> NSView {
        let label = Style.plainLabel("Example \(index + 1)", size: 11, weight: .medium, color: .secondaryLabelColor)

        let field = NSTextField(wrappingLabelWithString: "")
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.stringValue = text
        field.placeholderString = "Paste an example here…"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 516).isActive = true
        // Allow multi-line entry while keeping the height modest. A simple
        // NSTextField wraps but doesn't grow vertically, which is the
        // common Preferences look.
        field.cell?.wraps = true
        field.cell?.isScrollable = false

        let group = NSStackView(views: [label, field])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 2

        exampleFields.append(field)
        return group
    }

    private func buildExtractRow() -> NSView {
        extractButton = NSButton(title: "Re-extract style rules", target: self, action: #selector(extractRules))
        extractButton.bezelStyle = .rounded

        progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 16).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 16).isActive = true

        statusLabel = Style.plainLabel("", size: 11, weight: .regular, color: .tertiaryLabelColor)

        let row = NSStackView(views: [extractButton, progress, statusLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func buildRulesSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(Style.sectionHeader("Learned style rules"))

        let note = NSTextField(wrappingLabelWithString:
            "These rules are appended to the mode's prompt every time you refine. Edit any rule in place; delete with the ✕ button. Edits and deletions persist across re-extractions.")
        note.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 516
        stack.addArrangedSubview(note)

        rulesStack = NSStackView()
        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 4
        rulesStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(rulesStack)
        return stack
    }

    private func buildFooter() -> NSView {
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded

        let row = NSStackView(views: [closeButton, saveButton])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    // MARK: Persistence

    private func loadRules() {
        let store = StyleRulesStore.read()
        let entry = store.entries[String(mode.id)]
        loadedRules = entry?.rules ?? []
        deletedRules = Set(entry?.deletedRules ?? [])
        extractedAt = entry?.extractedAt ?? ""
        refreshRulesUI()
    }

    private func refreshRulesUI() {
        ruleFields.removeAll()
        for subview in rulesStack.arrangedSubviews { subview.removeFromSuperview() }

        if loadedRules.isEmpty {
            let none = NSTextField(labelWithString: "No rules yet. Add examples above and click Re-extract.")
            none.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            none.textColor = .tertiaryLabelColor
            rulesStack.addArrangedSubview(none)
        } else {
            for rule in loadedRules {
                rulesStack.addArrangedSubview(makeRuleRow(rule: rule))
            }
        }

        statusLabel.stringValue = extractedAt.isEmpty
            ? ""
            : "Last refreshed: \(extractedAt)"
    }

    private func makeRuleRow(rule: String) -> NSView {
        let field = NSTextField()
        field.stringValue = rule
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 480).isActive = true
        ruleFields.append(field)

        let deleteButton = NSButton(title: "✕", target: self, action: #selector(deleteRule(_:)))
        deleteButton.bezelStyle = .accessoryBarAction
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .tertiaryLabelColor
        deleteButton.tag = ruleFields.count - 1

        let row = NSStackView(views: [field, deleteButton])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        return row
    }

    @objc private func deleteRule(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < ruleFields.count else { return }
        let removed = ruleFields[index].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !removed.isEmpty { deletedRules.insert(removed) }
        loadedRules.remove(at: index)
        refreshRulesUI()
    }

    // MARK: Actions

    @objc private func extractRules() {
        let examples = exampleFields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !examples.isEmpty else {
            statusLabel.stringValue = "Add at least one example first."
            return
        }

        progress.isHidden = false
        progress.startAnimation(nil)
        extractButton.isEnabled = false
        statusLabel.stringValue = "Extracting rules…"

        // Persist the examples to ~/.penny/modes.json before extraction so
        // the rules and the examples-that-produced-them stay consistent.
        saveExamples(examples)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let extracted = self.helper.extractRules(
                mode: self.mode.id,
                modeName: self.mode.name,
                modeIntent: self.mode.detail,
                modeBasePrompt: self.mode.prompt,
                examples: examples
            )
            DispatchQueue.main.async {
                self.progress.stopAnimation(nil)
                self.progress.isHidden = true
                self.extractButton.isEnabled = true

                switch extracted {
                case .failure(let error):
                    self.statusLabel.stringValue = "Extraction failed: \(error)"
                case .success(let rules):
                    let filtered = rules.filter { !self.deletedRules.contains($0) }
                    self.loadedRules = filtered
                    self.extractedAt = ISO8601DateFormatter().string(from: Date())
                    StyleRulesStore.write(
                        modeId: self.mode.id,
                        rules: filtered,
                        deletedRules: Array(self.deletedRules),
                        extractedAt: self.extractedAt
                    )
                    self.refreshRulesUI()
                }
            }
        }
    }

    @objc private func save() {
        let examples = exampleFields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        saveExamples(examples)

        // Preserve any in-place edits to rule text fields before persisting.
        let rules = ruleFields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        StyleRulesStore.write(
            modeId: mode.id,
            rules: rules,
            deletedRules: Array(deletedRules),
            extractedAt: extractedAt
        )

        Picker.showToast("Saved")
        close()
    }

    @objc private func closeWindow() {
        close()
    }

    private func saveExamples(_ examples: [String]) {
        // Rewrite this mode's `examples` field in ~/.penny/modes.json.
        var modes = Modes.all
        guard let index = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        let updated = Mode(
            id: modes[index].id,
            name: modes[index].name,
            detail: modes[index].detail,
            isCustom: modes[index].isCustom,
            isCancel: modes[index].isCancel,
            locked: modes[index].locked,
            prompt: modes[index].prompt,
            examples: examples
        )
        modes[index] = updated
        try? Modes.save(modes)
    }
}

// MARK: Style-rules persistence

/// Read/write for `~/.penny/style-rules.json`. Layout matches the spec:
/// keyed by mode id (string), each entry holds rules, deleted_rules, and
/// timestamps.
enum StyleRulesStore {
    struct Entry {
        var rules: [String]
        var deletedRules: [String]
        var extractedAt: String
    }

    struct Store {
        var entries: [String: Entry]
    }

    private static var path: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".penny/style-rules.json")
    }

    static func read() -> Store {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else {
            return Store(entries: [:])
        }
        var entries: [String: Entry] = [:]
        for (key, value) in json {
            entries[key] = Entry(
                rules: value["rules"] as? [String] ?? [],
                deletedRules: value["deleted_rules"] as? [String] ?? [],
                extractedAt: value["extracted_at"] as? String ?? ""
            )
        }
        return Store(entries: entries)
    }

    static func write(modeId: Int, rules: [String], deletedRules: [String], extractedAt: String) {
        var existing = read()
        existing.entries[String(modeId)] = Entry(
            rules: rules,
            deletedRules: deletedRules,
            extractedAt: extractedAt
        )
        var raw: [String: [String: Any]] = [:]
        for (key, entry) in existing.entries {
            raw[key] = [
                "rules": entry.rules,
                "deleted_rules": entry.deletedRules,
                "extracted_at": entry.extractedAt,
            ]
        }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
