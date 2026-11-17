import Cocoa
import UniformTypeIdentifiers

struct HistoryEntry: Codable {
    var id: UUID
    var name: String
    var start: Date
    var end: Date
    var duration: TimeInterval
}

/// 履歴を ~/Library/Application Support/MenuStopwatches/history.json に保存する
final class HistoryStore {
    static let shared = HistoryStore()
    static let didChange = Notification.Name("HistoryStoreDidChange")

    private(set) var entries: [HistoryEntry] = []   // 新しいものが先頭
    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuStopwatches", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func remove(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: HistoryStore.didChange, object: nil)
    }

    func csv(_ list: [HistoryEntry]) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["名前,開始,終了,時間,秒数"]
        for e in list {
            lines.append([esc(e.name), f.string(from: e.start), f.string(from: e.end),
                          TimeFormat.full(e.duration), String(Int(e.duration))].joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"   // BOM 付きで Excel でも文字化けしない
    }
}

/// 履歴の一覧ウィンドウ
final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "")
    private let deleteButton = NSButton(title: "選択を削除", target: nil, action: nil)
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d (E) HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    private var entries: [HistoryEntry] { HistoryStore.shared.entries }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "履歴"
        window.minSize = NSSize(width: 420, height: 240)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: HistoryStore.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let columns: [(String, String, CGFloat)] = [
            ("name", "名前", 140), ("start", "開始", 130), ("end", "終了", 130), ("duration", "時間", 90),
        ]
        for (id, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let exportButton = NSButton(title: "CSVに書き出す…", target: self, action: #selector(exportCSV))
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        summary.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        summary.textColor = .secondaryLabelColor

        let bar = NSStackView(views: [summary, NSView(), deleteButton, exportButton])
        bar.orientation = .horizontal
        bar.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(bar)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        updateSummary()
    }

    @objc func reload() {
        table.reloadData()
        updateSummary()
    }

    private var selectedEntries: [HistoryEntry] {
        table.selectedRowIndexes.compactMap { $0 < entries.count ? entries[$0] : nil }
    }

    private func updateSummary() {
        let selected = selectedEntries
        let list = selected.isEmpty ? entries : selected
        let total = list.reduce(0) { $0 + $1.duration }
        summary.stringValue = (selected.isEmpty ? "全 \(list.count) 件" : "選択 \(list.count) 件")
            + "　合計 \(TimeFormat.full(total))"
        deleteButton.isEnabled = !selected.isEmpty
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, row < entries.count else { return nil }
        let e = entries[row]
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField
            ?? {
                let f = NSTextField(labelWithString: "")
                f.identifier = id
                f.lineBreakMode = .byTruncatingTail
                return f
            }()
        switch id.rawValue {
        case "name": cell.stringValue = e.name
        case "start": cell.stringValue = dateFormatter.string(from: e.start)
        case "end": cell.stringValue = dateFormatter.string(from: e.end)
        default:
            cell.stringValue = TimeFormat.full(e.duration)
            cell.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateSummary() }

    // MARK: Actions

    @objc func deleteSelected() {
        let ids = Set(selectedEntries.map(\.id))
        guard !ids.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "\(ids.count) 件の履歴を削除しますか？"
        alert.informativeText = "元に戻せません。"
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        HistoryStore.shared.remove(ids: ids)
    }

    @objc func exportCSV() {
        let selected = selectedEntries
        let list = selected.isEmpty ? entries : selected
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = "stopwatch-history-\(f.string(from: Date())).csv"
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try HistoryStore.shared.csv(list).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
