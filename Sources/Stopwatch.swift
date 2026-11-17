import Cocoa
import ServiceManagement

// 1つのストップウォッチの保存用データ
struct StopwatchState: Codable {
    var id: String
    var name: String
    var accumulated: TimeInterval   // 一時停止までに貯まった時間
    var startedAt: Date?            // 動いている間だけ値が入る
    var sessionStart: Date?         // 0 から最初に開始した時刻（履歴用）
}

enum Settings {
    static var showSeconds: Bool {
        get { UserDefaults.standard.object(forKey: "showSeconds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showSeconds") }
    }
}

enum TimeFormat {
    /// メニューバー用。秒を隠す設定のときは「時:分」だけにする
    static func menuBar(_ t: TimeInterval) -> String {
        let total = Int(max(0, t))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        if !Settings.showSeconds { return String(format: "%d:%02d", h, m) }
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// 常に秒まで出す（メニューの見出し・履歴用）
    static func full(_ t: TimeInterval) -> String {
        let total = Int(max(0, t))
        return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    /// 「1:23:45」「23:45」「45」（分）を秒に変換する
    static func parse(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "：", with: ":")
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let n = parts.map { $0! }
        switch n.count {
        case 1: return TimeInterval(n[0] * 60)                       // 分
        case 2: return TimeInterval(n[0] * 60 + n[1])                // 分:秒
        case 3: return TimeInterval(n[0] * 3600 + n[1] * 60 + n[2]) // 時:分:秒
        default: return nil
        }
    }
}

// メニューバーのアイコン1個 = ストップウォッチ1個
final class Stopwatch: NSObject, NSMenuDelegate {
    var state: StopwatchState
    let item: NSStatusItem
    unowned let app: AppDelegate

    init(state: StopwatchState, app: AppDelegate) {
        self.state = state
        self.app = app
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = "stopwatch-\(state.id)"   // ⌘ドラッグで並べ替えた位置を覚える
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
    }

    var isRunning: Bool { state.startedAt != nil }

    var elapsed: TimeInterval {
        state.accumulated + (state.startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    var displayName: String { state.name.isEmpty ? "ストップウォッチ" : state.name }

    func refresh() {
        guard let button = item.button else { return }
        let time = TimeFormat.menuBar(elapsed)
        let text = state.name.isEmpty ? time : "\(state.name) \(time)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // 止まっている間は灰色にして、動いているものと見分けやすくする
        let color: NSColor = isRunning ? .labelColor : .tertiaryLabelColor
        button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        button.toolTip = "クリック: 開始/一時停止　右クリック: メニュー"
    }

    // MARK: 状態の変更

    func toggle() {
        if let started = state.startedAt {
            state.accumulated += Date().timeIntervalSince(started)
            state.startedAt = nil
        } else {
            let now = Date()
            if state.sessionStart == nil { state.sessionStart = now.addingTimeInterval(-state.accumulated) }
            state.startedAt = now
        }
        changed()
    }

    /// 経過時間を指定した値にする（動いている場合はそのまま動き続ける）
    func setElapsed(_ value: TimeInterval) {
        let target = max(0, value)
        let running = state.startedAt.map { Date().timeIntervalSince($0) } ?? 0
        state.accumulated = target - running
        // 時間を調整したら「その分だけ前（後）から始めていた」ことにする
        state.sessionStart = (target > 0 || isRunning) ? Date().addingTimeInterval(-target) : nil
        changed()
    }

    func reset(record: Bool) {
        let duration = elapsed
        if record, duration >= 1 {
            let end = Date()
            HistoryStore.shared.add(HistoryEntry(
                id: UUID(), name: displayName,
                start: state.sessionStart ?? end.addingTimeInterval(-duration),
                end: end, duration: duration))
        }
        state.accumulated = 0
        state.startedAt = nil
        state.sessionStart = nil
        changed()
    }

    private func changed() {
        app.save()
        refresh()
    }

    // MARK: クリックとメニュー

    @objc func clicked() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRight {
            let menu = buildMenu()
            menu.delegate = self
            item.menu = menu
            item.button?.performClick(nil)   // メニューを開く
        } else {
            toggle()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil   // 左クリックが再び開始/停止になるように外す
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: "\(displayName)  \(TimeFormat.full(elapsed))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(makeItem(isRunning ? "一時停止" : "開始", #selector(menuToggle)))
        menu.addItem(makeItem("リセット（履歴に保存）", #selector(menuReset)))
        menu.addItem(makeItem("履歴に残さずリセット", #selector(menuResetNoRecord)))

        // 時間の調整
        let adjust = NSMenuItem(title: "時間を調整", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in [1, 5, 10, 30] { sub.addItem(makeItem("+\(m)分", #selector(menuAdjust(_:)), tag: m * 60)) }
        sub.addItem(.separator())
        for m in [1, 5, 10, 30] { sub.addItem(makeItem("−\(m)分", #selector(menuAdjust(_:)), tag: -m * 60)) }
        sub.addItem(.separator())
        sub.addItem(makeItem("時間を指定…", #selector(menuSetTime)))
        adjust.submenu = sub
        menu.addItem(adjust)

        menu.addItem(makeItem("名前を変更…", #selector(menuRename)))
        menu.addItem(.separator())
        menu.addItem(makeItem("ストップウォッチを追加", #selector(menuAdd)))
        let remove = makeItem("このストップウォッチを削除", #selector(menuRemove))
        remove.isEnabled = app.stopwatches.count > 1
        menu.addItem(remove)
        menu.addItem(.separator())
        menu.addItem(makeItem("履歴を表示…", #selector(menuHistory)))
        let seconds = makeItem("秒を表示", #selector(menuToggleSeconds))
        seconds.state = Settings.showSeconds ? .on : .off
        menu.addItem(seconds)
        let login = makeItem("ログイン時に起動", #selector(menuLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(makeItem("終了", #selector(menuQuit)))
        return menu
    }

    private func makeItem(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.tag = tag
        return mi
    }

    @objc func menuToggle() { toggle() }
    @objc func menuReset() { reset(record: true) }
    @objc func menuResetNoRecord() { reset(record: false) }
    @objc func menuAdjust(_ sender: NSMenuItem) { setElapsed(elapsed + TimeInterval(sender.tag)) }

    @objc func menuSetTime() {
        guard let text = prompt(title: "時間を指定",
                                info: "「1:23:45」（時:分:秒）、「23:45」（分:秒）、「45」（分）の形で入力してください。",
                                value: TimeFormat.full(elapsed)) else { return }
        if let value = TimeFormat.parse(text) {
            setElapsed(value)
        } else {
            NSSound.beep()
        }
    }

    @objc func menuRename() {
        guard let text = prompt(title: "名前を変更",
                                info: "メニューバーで時間の前に表示されます（空欄なら時間だけ）。",
                                value: state.name) else { return }
        state.name = text.trimmingCharacters(in: .whitespaces)
        changed()
    }

    private func prompt(title: String, info: String, value: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    @objc func menuAdd() { app.addStopwatch() }
    @objc func menuRemove() { app.remove(self) }
    @objc func menuHistory() { app.showHistory() }

    @objc func menuToggleSeconds() {
        Settings.showSeconds.toggle()
        app.stopwatches.forEach { $0.refresh() }
    }

    @objc func menuLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "ログイン項目を変更できませんでした"
            alert.informativeText = "\(error.localizedDescription)\nアプリを「アプリケーション」フォルダに入れてから試してください。"
            alert.runModal()
        }
    }

    @objc func menuQuit() { NSApp.terminate(nil) }
}
