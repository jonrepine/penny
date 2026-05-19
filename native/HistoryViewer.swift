import AppKit

/// Searchable viewer for Penny's combined refinement + dictation history.
///
/// Data sources:
///   - `~/.penny/history.json`           (refinements; written by the
///     Python helper after every successful refine)
///   - `~/.penny/dictation-history.json` (dictations; written by
///     whisper-dictate after every successful transcription)
///
/// Both files cap themselves at a few hundred entries on the writer side,
/// so the viewer doesn't need to paginate.
final class HistoryViewerWindowController: NSWindowController {
    private var entries: [HistoryEntry] = []
    private var filtered: [HistoryEntry] = []
    private var searchField: NSSearchField!
    private var table: NSTableView!
    private var detailView: NSTextView!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Penny History"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating

        super.init(window: window)
        window.contentView = buildContentView()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Layout

    private func buildContentView() -> NSView {
        let container = NSView()

        // Top: search field
        searchField = NSSearchField()
        searchField.placeholderString = "Search…"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // Left: list of entries
        table = NSTableView()
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 50
        table.allowsMultipleSelection = false
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true

        let summaryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("summary"))
        summaryColumn.title = "History"
        summaryColumn.minWidth = 240
        table.addTableColumn(summaryColumn)
        table.headerView = nil

        let leftScroll = NSScrollView()
        leftScroll.hasVerticalScroller = true
        leftScroll.documentView = table
        leftScroll.translatesAutoresizingMaskIntoConstraints = false
        leftScroll.borderType = .lineBorder

        // Right: detail pane
        detailView = NSTextView()
        detailView.isEditable = false
        detailView.isSelectable = true
        detailView.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        detailView.textContainerInset = NSSize(width: 12, height: 12)

        let rightScroll = NSScrollView()
        rightScroll.hasVerticalScroller = true
        rightScroll.documentView = detailView
        rightScroll.translatesAutoresizingMaskIntoConstraints = false
        rightScroll.borderType = .lineBorder

        // Bottom toolbar
        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copySelected))
        copyButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "Clear history…", target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .rounded

        let toolbar = NSStackView(views: [clearButton, NSView(), copyButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(searchField)
        container.addSubview(leftScroll)
        container.addSubview(rightScroll)
        container.addSubview(toolbar)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            leftScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            leftScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            leftScroll.widthAnchor.constraint(equalToConstant: 280),
            leftScroll.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -12),

            rightScroll.topAnchor.constraint(equalTo: leftScroll.topAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: leftScroll.trailingAnchor, constant: 12),
            rightScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            rightScroll.bottomAnchor.constraint(equalTo: leftScroll.bottomAnchor),

            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            toolbar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])
        return container
    }

    // MARK: Data

    func reload() {
        let refinements = HistoryStore.refinements()
        let dictations = HistoryStore.dictations()
        entries = (refinements + dictations).sorted { $0.timestamp > $1.timestamp }
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        filtered = query.isEmpty ? entries : entries.filter { entry in
            entry.searchableText.lowercased().contains(query)
        }
        table?.reloadData()
        updateDetail()
    }

    private func updateDetail() {
        let row = table?.selectedRow ?? -1
        guard row >= 0, row < filtered.count else {
            detailView?.string = filtered.isEmpty ? "No history yet. Dictate or refine some text to populate this list." : "Select an entry on the left to see the full text."
            return
        }
        detailView?.string = filtered[row].detailText
    }

    // MARK: Actions

    @objc private func searchChanged() {
        applyFilter()
    }

    @objc private func copySelected() {
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filtered[row].copyableText, forType: .string)
        Picker.showToast("Copied")
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all Penny history?"
        alert.informativeText = "This deletes the refinement and dictation logs on disk. Cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear")
        alert.buttons.last?.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        HistoryStore.clear()
        reload()
    }
}

extension HistoryViewerWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("HistoryRow")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let title = NSTextField(labelWithString: "")
            title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            title.lineBreakMode = .byTruncatingTail
            title.translatesAutoresizingMaskIntoConstraints = false
            let subtitle = NSTextField(labelWithString: "")
            subtitle.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            subtitle.textColor = .secondaryLabelColor
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(title)
            cell.addSubview(subtitle)
            cell.textField = title
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
                subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
                subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            ])
        }
        cell.textField?.stringValue = entry.summary
        // Subtitle goes in the second NSTextField we added.
        if let subtitle = cell.subviews.compactMap({ $0 as? NSTextField }).last, subtitle != cell.textField {
            subtitle.stringValue = entry.subtitle
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetail()
    }
}

// MARK: HistoryEntry + HistoryStore

struct HistoryEntry {
    enum Kind { case refinement(mode: String), dictation }
    let timestamp: String
    let kind: Kind
    let original: String
    let refined: String

    var summary: String {
        switch kind {
        case .dictation: return refined.isEmpty ? original : refined
        case .refinement: return refined
        }
    }

    var subtitle: String {
        let date = humanDate(timestamp)
        switch kind {
        case .refinement(let mode): return "\(date) · Refine · \(mode)"
        case .dictation:            return "\(date) · Dictation"
        }
    }

    var detailText: String {
        switch kind {
        case .dictation:
            return "DICTATION\n\(humanDate(timestamp))\n\n\(refined)"
        case .refinement(let mode):
            return """
            REFINEMENT · \(mode)
            \(humanDate(timestamp))

            ── ORIGINAL ──
            \(original)

            ── REFINED ──
            \(refined)
            """
        }
    }

    var copyableText: String {
        switch kind {
        case .dictation: return refined.isEmpty ? original : refined
        case .refinement: return refined
        }
    }

    var searchableText: String {
        original + " " + refined + " " + subtitle
    }
}

enum HistoryStore {
    private static var refinementPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".penny/history.json")
    }
    private static var dictationPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".penny/dictation-history.json")
    }

    static func refinements() -> [HistoryEntry] {
        guard let array = readArray(at: refinementPath) else { return [] }
        return array.compactMap { dict in
            HistoryEntry(
                timestamp: (dict["timestamp"] as? String) ?? "",
                kind: .refinement(mode: modeLabel(dict["mode"])),
                original: (dict["original"] as? String) ?? "",
                refined: (dict["refined"] as? String) ?? ""
            )
        }
    }

    static func dictations() -> [HistoryEntry] {
        guard let array = readArray(at: dictationPath) else { return [] }
        return array.compactMap { dict in
            HistoryEntry(
                timestamp: (dict["timestamp"] as? String) ?? "",
                kind: .dictation,
                original: "",
                refined: (dict["text"] as? String) ?? ""
            )
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: refinementPath)
        try? FileManager.default.removeItem(atPath: dictationPath)
    }

    private static func readArray(at path: String) -> [[String: Any]]? {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return json
    }

    private static func modeLabel(_ raw: Any?) -> String {
        if let id = raw as? Int, let mode = Modes.all.first(where: { $0.id == id }) {
            return mode.name
        }
        if let s = raw as? String, let id = Int(s), let mode = Modes.all.first(where: { $0.id == id }) {
            return mode.name
        }
        return "\(raw ?? "?")"
    }
}

/// Convert "2026-05-19T15:32:11Z" into "19 May, 15:32".
private func humanDate(_ iso: String) -> String {
    let parsers: [ISO8601DateFormatter.Options] = [
        [.withInternetDateTime],
        [.withInternetDateTime, .withFractionalSeconds],
    ]
    let formatter = ISO8601DateFormatter()
    for options in parsers {
        formatter.formatOptions = options
        if let date = formatter.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "d MMM, HH:mm"
            return out.string(from: date)
        }
    }
    return iso
}
