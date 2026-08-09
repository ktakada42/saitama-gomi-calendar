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

**初回設定の画面を撮るときは、アプリを`uninstall`してから入れ直す。**
plistを消すだけでは`cfprefsd`がキャッシュを持っていて効かず、
地区が設定されたままのホーム画面が撮れてしまう。

また、起動直後は描画が間に合わないので数秒待ってから撮る。

## ディレクトリ

| | |
|---|---|
| `6.9-inch/` | 素のスクリーンショット（撮ったまま） |
| `6.9-inch-decorated/` | App Store提出用。上にキャッチコピーの帯を足したもの |

装飾版は `scripts/make_store_screenshots.py` で生成する。

```bash
python3 scripts/make_store_screenshots.py
```

コピーの文言はスクリプト内の `STRIPS` にまとまっているので、
そこだけ直せば作り直せる。素のスクリーンショットを撮り直したときも
同じコマンドで装飾版が揃う。

画面の上端にあるステータスバー（時刻・電波・電池）は落としている。
帯のすぐ下にステータスバーが来ると、帯と二重の「上端」ができて
画面を貼り付けただけに見えるため。

## ファイル

| ファイル | 画面 | コピー |
|---|---|---|
| `00_onboarding.png` | 初回設定（地区選択） | 郵便番号だけで／すぐ使える |
| `00_home.png` | ホーム | 明日は何ごみ？ |
| `01_calendar.png` | カレンダー | 今月の収集日が／ひと目で |
| `02_dictionary.png` | 分別 | 443品目を／五十音で探せる |
| `03_settings.png` | 設定 | 前日の夜に／お知らせ |
