# MenuStopwatches

macOS のメニューバーにストップウォッチを複数並べて、それぞれ独立して動かせるアプリです。

```
A 12:34   B 03:21
```

## 使い方

- **クリック**: そのストップウォッチを開始 / 一時停止（止まっている間は灰色表示）
- **右クリック**: メニュー
  - リセット（履歴に保存） / 履歴に残さずリセット
  - 時間を調整: ±1・5・10・30 分、時間を直接指定（`1:23:45` / `23:45` / `45`＝分）
  - 名前を変更、ストップウォッチを追加・削除
  - 履歴を表示（一覧、合計時間、選択削除、CSV 書き出し）
  - 秒を表示 / 隠す、ログイン時に起動、終了
- **⌘ + ドラッグ**: メニューバー上の並び順を変更（位置は保存されます）

アプリを終了・再起動しても計測中の時間は保持されます。

## ビルド

Xcode Command Line Tools（`swiftc`）があればビルドできます。

```bash
./build.sh
```

`build/MenuStopwatches.app` ができるので、`/Applications` に移して起動してください（「ログイン時に起動」は `/Applications` に置いたときに使えます）。

```bash
cp -R build/MenuStopwatches.app /Applications/
```

動作環境: macOS 13 以降（Apple Silicon）

## データの保存場所

- ストップウォッチの状態: `defaults read local.menustopwatches`
- 履歴: `~/Library/Application Support/MenuStopwatches/history.json`
