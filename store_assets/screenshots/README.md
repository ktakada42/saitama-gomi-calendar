# App Store用スクリーンショット

iPhone 6.9インチ（1320×2868、iPhone 17 Pro Max相当）のシミュレータで撮影。
App Storeが必須とするサイズ。

## 撮り方

シミュレータには`flutter build ios --simulator`のdebugビルドを入れる。
Releaseはシミュレータ向けに作れない（`flutter build`が断る）が、
`debugShowCheckedModeBanner: false`にしてあるので見た目は変わらない。

シミュレータでは実機のように地区選択のUI操作を自動化するのが難しいため、
`NSUserDefaults`（`flutter.selected_area`キー）に地区データを直接書き込んで
状態を再現している。

`plutil`や`defaults`で書くのではなく、**シミュレータを停止させてから
plistを丸ごと置き、起動し直す**。動いている間に書いても`cfprefsd`が
自分のキャッシュを正としてしまい、アプリからは読めない。
`xcrun simctl spawn <UDID> defaults write` も効かない。spawnした
プロセスはアプリのサンドボックスの外にいるので、書き込み先が
アプリのコンテナではなくシミュレータ側のルートになる。

```bash
SIM=<シミュレータのUDID>
BID=io.github.ktakada42.saitamagomicalendar
CONTAINER=$(xcrun simctl get_app_container $SIM $BID data)
xcrun simctl shutdown $SIM
# $CONTAINER/Library/Preferences/$BID.plist を作る（plistlibなど）
#   flutter.selected_area        … areas.json の地区をそのままJSON文字列で
#   flutter.notification_enabled … true（通知のコピーと画面を合わせるため）
#   flutter.notification_minutes … 1200（20:00）
#   flutter.theme_mode           … light
xcrun simctl boot $SIM
```

地区は撮る日によって選び直す。**翌日に何区分の収集があるかで、ホームの
「明日」とウィジェットの見え方が決まる**ため。1.1.1では日曜に撮ったので、
月曜が3区分（もえない・有害危険・資源物2類）ある「南区 南浦和1〜4丁目」
（`areas.json`の`manual-213`）を使った。1.1.0までは「浦和区 大原1〜5丁目」
（`manual-151`）で、こちらは月曜がもえるごみだけになる。

ステータスバーは`xcrun simctl status_bar`で揃える。再起動すると外れるので、
`boot`のたびに掛け直す。

```bash
xcrun simctl status_bar $SIM override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charging --batteryLevel 100
```

タブの遷移はSystem Events経由でボトムメニューを座標クリックする。
Flutterはアクセシビリティが要求されるまで意味づけの木を作らないので、
`AXButton`を名前で探しても出てこない。

画面の座標からMacの座標への変換は、Simulatorウィンドウの`group 1`
（＝端末の画面そのもの）の位置と大きさから出す。ウィンドウの位置や
表示倍率が変わっても、これなら追随する。

```bash
osascript -e 'tell application "System Events" to tell process "Simulator" \
  to return {position of group 1 of window 1, size of group 1 of window 1}'
# 画面(pt) → Mac = 位置 + 画面座標 × (group1の大きさ ÷ 440x956)
# タブの中心は y=879pt、x はホーム55 / カレンダー164 / 分別273 / 設定384
```

**初回設定の画面を撮るときは、アプリを`uninstall`してから入れ直す。**
plistを消すだけでは`cfprefsd`がキャッシュを持っていて効かず、
地区が設定されたままのホーム画面が撮れてしまう。

また、起動直後は描画が間に合わないので数秒待ってから撮る。

### ウィジェットを置いた画面の撮り方

**シミュレータ（iOS 26.5）のウィジェットギャラリーは空のまま開く。**
自作のものだけでなくマップやカレンダーなど標準のものも一切出てこないので、
「ホーム画面を長押し →編集 →ウィジェットを追加」からは置けない。
`chronod`はウィジェットを認識できている（ログに`GomiWidget`が出る）ので、
出せないのはギャラリーの描画側の問題。

代わりにSpringBoardのホーム画面の配置そのものを書き換える。
シミュレータを**停止してから**次のplistを編集し、起動し直すと置かれた状態になる。

```
~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/SpringBoard/IconState.plist
```

`iconLists`がページの配列で、その要素にこの形の辞書を混ぜるとウィジェットになる。
`widgetIdentifier`は`GomiWidget.swift`の`kind`、`gridSize`は`small`か`medium`。

```python
{
    "elementType": "widget",
    "widgetIdentifier": "GomiWidget",
    "containerBundleIdentifier": "io.github.ktakada42.saitamagomicalendar",
    "bundleIdentifier": "io.github.ktakada42.saitamagomicalendar.GomiWidget",
    "displayIdentifier": <UUID>,   # 大文字のUUID文字列。他と重複させない
    "uniqueIdentifier": <UUID>,
    "gridSize": "medium",
    "iconType": "custom",
    "allowsSuggestions": False,
    "allowsExternalSuggestions": False,
}
```

ウィジェットが読むのはApp Groupに書き出された共有データなので、
**書き換えたあとにアプリを一度起動してから**撮る。起動していないと
「地区が未設定」の見た目になる。

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
同じコマンドで装飾版が揃う。添え書きは `None` にできる。コピーだけで
言い切れているものに一行足すと、同じことを二度言うことになるため。

画面の上端にあるステータスバー（時刻・電波・電池）は落としている。
帯のすぐ下にステータスバーが来ると、帯と二重の「上端」ができて
画面を貼り付けただけに見えるため。

## ファイル

番号はApp Storeに並べる順。

| ファイル | 画面 | コピー |
|---|---|---|
| `00_home.png` | ホーム | 明日は何ごみ？ |
| `01_widget.png` | ホーム画面ウィジェット（中・小） | ホーム画面から／確認可能 |
| `02_calendar.png` | カレンダー | 今月の収集日が／ひと目で |
| `03_dictionary.png` | 分別 | 498品目を／五十音で探せる |
| `04_settings.png` | 設定 | 前日の夜に／お知らせ |

初回設定（地区選択）の画面は入れていない。地区を選ぶのは最初の一度きりで、
一覧に並べて選んでもらう場面で見せたいものではないため。撮る必要が出たら、
上の「撮り方」のとおりアプリを`uninstall`してから入れ直して撮る。
