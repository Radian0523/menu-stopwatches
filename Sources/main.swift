import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var stopwatches: [Stopwatch] = []
    private var ticker: Timer?
    private var historyWindow: HistoryWindowController?
    private let key = "stopwatches.v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        var states: [StopwatchState] = []
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([StopwatchState].self, from: data) {
            states = saved
        }
        if states.isEmpty {
            states = [
                StopwatchState(id: UUID().uuidString, name: "A", accumulated: 0, startedAt: nil),
                StopwatchState(id: UUID().uuidString, name: "B", accumulated: 0, startedAt: nil),
            ]
        }
        // 右側から並ぶので逆順に作って、左から A, B の順にする
        for s in states.reversed() {
            stopwatches.insert(Stopwatch(state: s, app: self), at: 0)
        }
        save()

        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.stopwatches.forEach { $0.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)   // メニューを開いている間も更新する
        ticker = t
    }

    /// Dock に出ないアプリでも入力欄で ⌘C / ⌘V などが効くように編集メニューを用意する
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func save() {
        let states = stopwatches.map(\.state)
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func addStopwatch() {
        let used = Set(stopwatches.map(\.state.name))
        let name = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init).first { !used.contains($0) } ?? ""
        let s = StopwatchState(id: UUID().uuidString, name: name, accumulated: 0, startedAt: nil)
        stopwatches.append(Stopwatch(state: s, app: self))
        save()
    }

    func remove(_ sw: Stopwatch) {
        guard stopwatches.count > 1 else { return }
        NSStatusBar.system.removeStatusItem(sw.item)
        stopwatches.removeAll { $0 === sw }
        save()
    }

    func showHistory() {
        if historyWindow == nil { historyWindow = HistoryWindowController() }
        historyWindow?.show()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // Dock に出さない
app.run()
