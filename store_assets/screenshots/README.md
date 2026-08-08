# App Store用スクリーンショット

iPhone 6.9インチ（1320×2868、iPhone 17 Pro Max相当）のシミュレータで撮影。
App Storeが必須とするサイズ。

## 撮り方

シミュレータでは実機のように地区選択のUI操作を自動化するのが難しいため、
`NSUserDefaults`（`flutter.selected_area`キー）に地区データを直接書き込んで
状態を再現している。

```bash
SIM=<シミュレータのUDID>
CONTAINER=$(xcrun simctl get_app_container $SIM io.github.ktakada42.saitamagomicalendar data)
PLIST="$CONTAINER/Library/Preferences/io.github.ktakada42.saitamagomicalendar.plist"
# アプリを一度起動してplistを作らせてから、terminateして書き込む
```

使用した地区は「浦和区 大原1〜5丁目」（`assets/data/areas.json`の`manual-151`）。
5区分がバランスよく別々の曜日に散らばっており、カレンダー・ホームの
見た目が分かりやすいため選んだ。

タブの遷移はSystem Eventsのアクセシビリティ経由でボトムメニューの
`AXButton`を直接クリックしている（座標クリックは機種ごとの余白の違いで
ずれるため使っていない）。

## ファイル

| ファイル | 画面 |
|---|---|
| `00_onboarding.png` | 初回設定（地区選択） |
| `00_home.png` | ホーム |
| `01_calendar.png` | カレンダー |
| `02_dictionary.png` | 分別 |
| `03_settings.png` | 設定 |
