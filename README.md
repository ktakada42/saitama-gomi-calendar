# さいたま市ゴミ収集カレンダー（非公式）

さいたま市の家庭ごみの収集日と分別を確認するアプリです。
（元々は [TenpAI](https://github.com/ktakada42/TenpAI) リポジトリ内で開発され、
無関係な別アプリのため本リポジトリに履歴ごと分離した）
**iPhone専用**（iOS 18以降）。Flutter実装なので将来Androidにも展開できます。

市の公式アプリと同じ情報を扱いますが、**トップページを開いた瞬間に「明日は何ごみか」が分かる**
ことだけを目的に組み直しています。

## ドキュメント

- [docs/requirements.md](docs/requirements.md) — 仕様書（何を作るか）
- [docs/design.md](docs/design.md) — 設計書（どう作ってあるか）
- [docs/next-phase.md](docs/next-phase.md) — 次フェーズの仕様・設計（地区表取り込み、ローカル通知）

以下はこのREADME内の要約。詳細は上記を参照。

## 画面

| 画面 | 役割 |
| --- | --- |
| 初回設定 | 郵便番号または一覧から地区を選ぶと曜日が自動で決まる。地区が見つからない場合のみ曜日を手入力する。設定するまで他の画面に進まない |
| ホーム | 明日の分別を最大サイズで表示。収集日の朝は、出す期限を過ぎるまで「今日」を出す。この先の予定・分別ごとの次回収集日 |
| カレンダー | 当月のごみ出し日を月表示。左右になぞって月を送れる（前1か月・後3か月）。日をタップで出し方 |
| 分別 | 498品目を五十音順に。品目名で検索、右端の索引をなぞって行へ飛ぶ |
| 設定 | 地区の変更、通知、画面の明るさ、設定中の曜日一覧、分別ごとの出し方 |
| このアプリについて | バージョン・出典・プライバシーポリシー・ライセンス |

## 設計方針

- **明日を最優先で出す**。ごみ出しは前夜に思い出す行動なので、
  トップページの主役は今日ではなく明日。今日は小さく添えるだけにしている。
  ただし収集日の朝は、出す期限（8:30、早朝収集地区のもえるごみは5:30）を
  過ぎるまで「今日」を出す。まだ間に合ううちに気づけるように
- **分別は色・アイコン・文字の三重符号化**。カレンダーのセルのように小さい場所でも、
  色覚特性によらず区別できるようにする。セルには短い名称（「もえる」「資源1」）を必ず添える
- **市の資料をそのまま出し、推測しない**。分別データは市のPDFマニュアルから機械的に
  抽出している。冊子向けの「★2」「▶P9参照」は、冊子を持たない利用者に通じないので
  アプリ側で言葉にする。市が示していないことは補わない
- **「区分ごとの次の収集」を独立して置く**。もえないごみのように月1回しかない区分は
  日付の並びを眺めても見つけにくく、これが実際にいちばん調べたい情報になる
- **縦画面固定**。カレンダーも一覧も縦に読む
- **通信しない**。収集ルールは端末内で完結し、設定も端末内にしか保存しない

## 収集ルールのモデル

さいたま市の収集日はすべて「◯曜日」を軸に決まっていて、毎週のものと
「第2・第4◯曜日」のように月内の週を限るものがある。日付そのもの（毎月15日など）で
決まる区分は無いため、`CollectionRule` は **曜日 + 月内の週番号の集合** の2要素だけを持つ。

```dart
const CollectionRule.weekly(DateTime.monday);            // 毎週月曜日
const CollectionRule.monthly(DateTime.thursday, {2, 4}); // 第2・第4木曜日
```

週番号は「その月で何回目のその曜日か」であって、カレンダーの行数ではない。
月初が日曜でも第1木曜はその月の最初の木曜になる。

地区（`CollectionArea`）は区分ごとにこのルールの一覧を持つ。もえるごみのように
週2回ある区分はルールが2つ並ぶ。`CollectionCalendar` がここから日付を引く。

収集を休むのは1月1日〜3日だけ。市は祝日も収集するので祝日カレンダーを持たない。

## 収集日データについて

収集曜日は利用者が決めるものではなく、住んでいる地区で市がすでに決めているもの。
`AreaPickerPage`（初回設定・地区の選び直しの入口）で郵便番号または一覧から地区を選ぶと、
5区分すべての曜日・早朝収集地区かどうかが自動で決まる。曜日の手入力は、地区が
見つからない場合の代替経路としてのみ残している（[docs/requirements.md](docs/requirements.md) 4.1節）。

`assets/data/areas.json` には次のデータが入っている（`scripts/update_areas_json.mjs`で
再取得できる。詳細は[docs/next-phase.md](docs/next-phase.md) A章）。

```jsonc
{
  "presets":     [ /* 曜日入力の出発点となる雛形。地区が見つからない代替経路でのみ使う */ ],
  "areas":       [ /* 市の公式PDFマニュアルの一覧表から取得した確定地区。320件 */ ],
  "postalAreas": { /* 郵便番号(7桁) → areasのid一覧。264件、うち32件は複数候補 */ }
}
```

郵便番号は地区の候補を絞り込むためだけに使い、`AreaPickerPage`はどこにも保存しない
（画面上にもその旨を明示している）。

同梱の雛形（`presets`）が持っているのは「もえるごみは週2回で、月・木か火・金のどちらか」
という市の案内どおりの情報で、地区が見つからない場合の入力の出発点としてのみ使う。

分別区分と出し方の文言も市の案内の要約であり、全文ではない。
アプリ内の「このアプリについて」から出典を示している。

## ディレクトリ構成

```
lib/domain/     純粋なDart（Flutter非依存）：区分・収集ルール・カレンダー計算・日付表記
lib/data/       同梱データの読み込みと設定の永続化
lib/features/   画面単位：home / calendar / dictionary / settings / area / about / shell
lib/ui/         区分の配色とアイコン、画面をまたぐ部品
assets/data/    地区データ・分別早見表
scripts/        assets/data/*.json を市の公開データから再生成するスクリプト
design/         アプリアイコンのマスターSVGと生成スクリプト
store_assets/   App Store用のスクリーンショット（素のものと装飾版）
test/           domain層の単体テストと画面のウィジェットテスト
.githooks/      pre-commitフック（CIと同じ3チェック）
.gwx.toml       gwxでworktreeを作ったときに走らせるもの
```

### アプリアイコン

`design/app_icon_master.svg`（縛ったゴミ袋、120×120のシンプルなベクター）が唯一の原本。
`bash design/generate_app_icons.sh`でiOS/Android向けの全サイズPNG（iOSはアルファチャンネル
無しのRGB）を書き出し、`ios/`・`android/`配下に配置し直せる。デザインを直すときは
マスターSVGを編集してこのスクリプトを再実行する。

## セットアップ

```bash
flutter pub get
flutter test
flutter run
```

### コミット前チェック

CIと同じ3つ（`dart format` / `flutter analyze` / `flutter test`）を
`.githooks/pre-commit` に置いてある。Gitは`core.hooksPath`を向けないとこれを見に行かないので、
cloneした直後に一度実行する。

```bash
git config core.hooksPath .githooks
```

書き込み先はworktreeごとではなく共有の設定ファイルなので、後からworktreeを増やしても効く。

新しいworktreeでは`flutter pub get`も先に済ませておく。`.dart_tool/`はworktreeごとに要り、
無いと`dart format`が`flutter_lints`を解決できず、触っていないファイルまで「変更あり」として
コミットが止まる。

[gwx](https://github.com/ktakada42/gwx)でworktreeを作るなら、この2つは`.gwx.toml`の
`post_create`に入れてあるので何もしなくてよい。worktreeの置き場所は各自の好みなので
そちらには書いていない。`~/.config/gwx/config.toml`に指定する。

```toml
[defaults]
base_dir = "~/worktrees/{repo}"
```

## 配布

TestFlightへの配信は1コマンドで行える。

```bash
scripts/build_testflight.sh <issuer-id>
```

issuer IDはこのリポジトリの持ち主に固有の値なので、公開リポジトリには書かず
引数で渡す（`ASC_ISSUER_ID` でも可）。APIキーのIDは
`~/.appstoreconnect/private_keys/AuthKey_*.p8` のファイル名から拾うので、
ふだんは省略してよい。

`flutter build ipa` を直接使わないのは、あれが自動署名を前提にしていてXcodeに
サインイン済みのアカウントを探しに行くため。アーカイブまでをflutterに任せ、
書き出しは手動署名で行っている。

App Store用のスクリーンショットは `store_assets/screenshots/`。装飾版（キャッチコピーの
帯を足したもの）は `scripts/make_store_screenshots.py` で生成する。

## 今後

次のリリースでは、分別のAI相談（GitHub issue #40〜#45）とホーム画面ウィジェット（#25）を
検討している。カレンダーへの取り込みは、iOSのカレンダーが共有シートの宛先にならず
実機で取り込めなかったため一度外した（#76でEventKitでの作り直しを検討）。

[docs/next-phase.md](docs/next-phase.md) は地区表の取り込みとローカル通知を扱った
一つ前のフェーズの記録で、どちらも実装済み。

## ライセンス

MIT License（[LICENSE](LICENSE)）。

ただし `assets/data/` の収集日・分別データはさいたま市の公開資料に由来し、
元の資料の権利は市に帰属する。同梱フォントはSIL OFL。
詳細は[LICENSE](LICENSE)の後半を参照。
