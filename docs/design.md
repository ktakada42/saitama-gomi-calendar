# 設計書

対象読者：このリポジトリに手を入れる開発者。「何を作るか」は[requirements.md](requirements.md)、
「どう作ってあるか／どう作るか」をここに書く。

## 0. 識別子

Bundle ID / applicationId は **`io.github.ktakada42.saitamagomicalendar`**（iOS・Android共通）。

- 逆ドメイン記法は実際に管理しているドメインを使う趣旨なので、GitHub Pages の
  `ktakada42.github.io` に基づく。市のドメインを騙る形（`jp.saitama.*`）は避ける
- **区切り文字は使えない**。iOSはハイフンが使えるがアンダースコアが使えず、
  Androidはその逆なので、両OSで通るのは英数字のみ
- 公開後は変更できない（Google Play が別アプリとして扱う）

## 1. アーキテクチャ概要

4層構成。依存の向きは上から下の一方向で、下位層は上位層を知らない。

```
lib/features/   画面（Widget）。Riverpodのproviderを watch/read する
lib/ui/         区分の配色・アイコン、画面をまたぐ部品
lib/providers.dart  Riverpod provider定義。data層とdomain層を画面につなぐ
lib/data/       永続化とアセット読み込み（I/O）
lib/domain/     判定ロジック。Flutter非依存の純粋なDart
```

domain層がFlutterに依存しないのは、日付計算のような「入力に対して出力が一意に決まる」
ロジックをUIの都合から切り離し、`flutter test`ではなく素のDartとして高速に単体テストする
ため。実際 `test/domain/` はウィジェットのビルドを介さない純粋なユニットテストになっている。

## 2. ドメインモデル

```
GarbageCategory (enum, 5値: burnable / nonBurnable / hazardous / recyclable1 / recyclable2)
  └ 表示順・正式名称・短縮名・代表品目・出し方をenum自身が持つ（データ的なenum）

CollectionRule
  └ weekday (1〜7) + weeksOfMonth (Set<int>?, nullなら毎週)
  └ matches(date) がこのルールの2要素だけで真偽を判定する

CollectionArea
  └ ward, name, rules: Map<GarbageCategory, List<CollectionRule>>, earlyMorning, note
  └ 1区分に複数ルールを持てる（もえるごみ週2回など）

CollectionCalendar(area)
  └ 日付 → その日の区分一覧、を引くための唯一の窓口
  └ dayOf / month / upcoming / nextFor
  └ 収集休止日（1/1〜1/3）の判定もここに閉じ込める

DateLabel
  └ 日付の日本語表記（相対表記「明日」「あさって」を含む）を作る純粋関数群

CollectionReminderPlanner(calendar)
  └ 「いつ何を通知すべきか」をCollectionReminderの一覧として計算する
  └ OSの通知APIには触らない純粋な計算だけ。通知の中身とタイミングの判断を
    単体テストで担保できるようにするため（next-phase.md B.4節）

WasteItem
  └ 分別早見表の1品目。品目名・かな行・出し先・注意点・印（markIds）
  └ 5区分に収まらない出し先（粗大ごみ・小型家電・電池・収集できないもの）も持つ
  └ searchKey / matches(query) で記号を無視した検索ができる

NoteMark
  └ 早見表の「★2」「▶P9参照」を、冊子を持たない人にも通じる言葉にする
  └ 印は抽出時に注意点の本文から切り出してある（scripts/extract_waste_dictionary.py）
  └ 知らない印は黙って捨てる。市が印を増やしても古いアプリが壊れないように

KanaRow
  └ 五十音の「行」。分別の一覧の見出しと索引に使う
  └ 濁音・半濁音は清音と同じ行として扱う（五十音順でも同じところに来るため）

DepositDeadline
  └ ごみを出せる時刻の期限。通常8:30、早朝収集地区のもえるごみは5:30
  └ isPassedAt(now) で「その日はもう出せないか」を判定する
  └ ちょうど期限の時刻はまだ出せる扱い

SortingChange
  └ 市の分別の決まりが変わる日と、その内容
  └ 分別データは同梱なので、決まりが変わってもアプリを更新しない利用者には
    古い分類が出続ける。切り替え日を過ぎたら知らせを出すために使う
  └ データを日付で切り替えることはしない（requirements.md 4.5節）
```

`CollectionCalendar`が「日付から区分を引く」ロジックの単一の入口になっており、画面側は
日付計算を一切持たない（`DateTime`の演算は`upcoming`/`nextFor`の中に閉じている）。

`CollectionRule.nthWeekdayOfMonth`は「月内で何回目のその曜日か」を`(day - 1) ~/ 7 + 1`で
求める。カレンダーの行位置（週の何行目か）とは意味が違う点に注意（月初の曜日オフセットの
影響を受けない）。

## 3. データ層

```
AreaCatalog.load()          assets/data/areas.json を読み込む（起動ごとに1回）
  areas:    確定地区の一覧。初回設定の主経路（地区を選ぶと曜日が決まる）が
            全面的に依存するデータ（320件投入済み。next-phase.md A章参照）
  presets:  曜日入力の雛形。地区が見つからない代替経路でのみ使う
  postalAreas: 郵便番号→areasのid一覧（264件）
  source / sourceUrl: 出典の名前とURL。設定画面に出す。タップできる範囲を
                       URLだけに限るため、名前とURLを分けて持つ
  areasForPostalCode(code)  postalAreasとareasを突き合わせてCollectionAreaを返す
                             （AreaPickerPageが使う唯一の郵便番号関連API）

WasteDictionary.load()       assets/data/dictionary.json を読み込む
  items:  品目ごとの出し先（446件）。かな行と印（marks）も持つ
  search(query)  記号を無視して絞り込む。前方一致を先に出す

SettingsRepository           shared_preferences 経由で利用者の設定を保存
  readArea() / writeArea() / clear()
    保存形式は CollectionArea.toJson() のJSON文字列まるごと。
    IDだけでは復元できない（ユーザーがプリセットから曜日を調整できるため）
  readThemeMode() / writeThemeMode()        外観（ライト/ダーク/システム）
  readNotificationSettings() / write...()   通知のON/OFFと時刻
    地区とは別キーにしてある。地区を選び直しても外観・通知の設定は保たれるべきなので。

NotificationRepository       OSの通知センターへの予約（abstract）
  requestPermission() / reschedule(reminders) / cancelAll()
  実装は _PluginNotificationRepository（flutter_local_notifications）。
  テストからは NoopNotificationRepository に差し替える
  （ウィジェットテストではOSの通知プラグインを初期化できないため）
```

`readArea()`は保存データが壊れていても例外を投げず`null`を返す。壊れ方には2種類あり、
両方を捕まえる。JSON構文自体が壊れている（`FormatException`）場合と、構文は正しいが
`CollectionArea`の形と違う（`TypeError`。フィールド欠落・型違い・トップレベルが配列など）
場合。片方しか捕まえないと、後者の壊れ方のときに例外が`_Root`まで漏れて
「設定を読み込めませんでした」の再試行画面になり、`readArea()`を呼び直すだけの
「もう一度試す」を押しても同じ壊れたデータを読むだけで直らない。壊れた保存データで
起動不能になるより、未設定（初回設定）として復旧できる方を優先している。

## 4. 状態管理（Riverpod）

`lib/providers.dart`がdata層・domain層を画面につなぐ唯一の場所。

```
settingsRepositoryProvider  FutureProvider<SettingsRepository>
areaCatalogProvider         FutureProvider<AreaCatalog>
wasteDictionaryProvider     FutureProvider<WasteDictionary>

selectedAreaProvider        AsyncNotifierProvider<SelectedArea, CollectionArea?>
  build()  起動時に SettingsRepository から読み込む。未設定なら null
  save(area) / clear()  書き込みと同時にstateも更新（永続化層を読み直さない）

nowProvider                  Provider<DateTime>
  DateTime.now()をここに集約。画面から直接呼ばないことで、
  テストで overrideWithValue して任意の時刻を固定できる

todayProvider                Provider<DateTime>
  nowProviderから日付だけを取り出す。二つが食い違わないよう、
  時刻を持つ側を唯一の出どころにしてある
  （「その日のごみをまだ出せるか」の判定に時刻が要る。requirements.md 4.2節）

packageInfoProvider          FutureProvider<PackageInfo>
  「このアプリについて」に出すバージョン。pubspec.yamlの値を焼き込まず、
  実際に入っているパッケージから読む

calendarProvider             Provider<CollectionCalendar?>
  selectedAreaProviderを購読し、areaがあればCollectionCalendarを作る。ないならnull

themeModeProvider            AsyncNotifierProvider<ThemeModeController, ThemeMode>
  外観設定。既定はライト（端末のダークモードに自動追従しない）

notificationProvider         AsyncNotifierProvider<NotificationController, NotificationSettings>
  通知のON/OFFと時刻。設定が変わるたび、また地区が変わるたびに
  CollectionReminderPlannerで直近30日分を計算し直してOSに予約し直す
```

`NotificationController`は通知を差分更新せず、毎回すべて取り消してから張り直す。
古い予約が残らないので、地区や時刻を変えたときの状態のずれを考えなくて済む。
地区の変更に追従するため`build()`で`selectedAreaProvider`を`ref.listen`している
（この経路での失敗は握りつぶす。通知が出ないだけで、収集日の確認という主目的は妨げない）。

## 5. 画面構成・遷移

```
SaitamaGomiApp (MaterialApp, ja固定)
 └ _Root  selectedAreaProviderを見て分岐
    ├ area == null            → AreaPickerPage(isOnboarding: true)
    ├ area != null            → HomeShell
    │   └ IndexedStack（タブ切り替えでカレンダーの表示月を失わないため）
    │       ├ HomePage       今日／明日を最大化、もう一方、この先6件、分別ごとの次回
    │       ├ CalendarPage   月表示。前1か月・後3か月まで送れる
    │       ├ DictionaryPage 498品目を五十音で。右端に行の索引
    │       └ SettingsPage   地区・通知・画面の明るさ・設定中の曜日・分別と出し方
    └ AsyncError             → エラー表示（設定読み込み失敗）

SettingsPage
  ├ 「お住まいの地区」        → push: AreaPickerPage(isOnboarding: false)
  ├ 「収集曜日を修正する」    → push: AreaEditorPage(initial: 現在のarea)
  └ 「バージョンと出典」      → push: AboutPage

DictionaryPage
  └ 品目をタップ（印を持つものだけ） → showWasteItemSheet

AreaPickerPage(isOnboarding: true)   … 初回設定の入口（_Rootから直接）
AreaPickerPage(isOnboarding: false)  … SettingsPage「お住まいの地区」から遷移
  └ 郵便番号 or 一覧で CollectionArea を選ぶ
     → push: AreaEditorPage(initial: 選んだarea, isOnboarding: 同じ値)
  └ 「自分の地区が見つからない」
     → push: AreaEditorPage(initial: null, isOnboarding: 同じ値)

AreaEditorPage(initial: area, isOnboarding: false)  … SettingsPage「収集曜日を修正する」
                                                        から遷移する、曜日を編集する画面
  └ 一覧から来たときは区・地区名を変えられない。市の地区で区だけ差し替えると
     「岩槻区高砂三丁目」のような実在しない地区ができるため（requirements.md 4.4節）
```

`AreaPickerPage`（`lib/features/area/area_picker_page.dart`）が「地区をどう特定するか」、
`AreaEditorPage`が「曜日をどう確認・調整するか」を担う。前者は必ず後者を
`Navigator.push`した先に手渡す構造で、`AreaEditorPage`自体は
[requirements.md](requirements.md) 4.1節の主経路・代替経路の両方で共有される
（渡す`initial`が「地区データそのまま」か「null（空欄）」かの違いだけ）。

`AreaEditorPage._save()`は保存後に`Navigator.popUntil((r) => r.isFirst)`で
いちばん最初の画面まで戻す。1つだけ戻すと、郵便番号で複数の候補が出た場合に
候補一覧へ着地してしまい、何の画面か・保存できたのかが分からなくなるため。
初回設定のときは、戻った先の`_Root`が`selectedAreaProvider`の更新を検知して
`HomeShell`に切り替わる。

`AreaPickerPage`が地区を選んだ結果は、`AreaEditorPage(initial: area)`の`initState`が
`initial.rulesFor(category)`から`_drafts`を組み立てる既存の仕組み（元々は設定変更時の
プリフィルのために存在した）にそのまま乗る。ピッカー側から`_applyPreset`等を
呼び出す必要はない。

**郵便番号の扱い**：`AreaPickerPage`は入力された郵便番号をローカルの`State`
（`TextEditingController`）にしか持たない。`AreaCatalog.areasForPostalCode()`に渡して
候補の`CollectionArea`を得たら、以降はその`CollectionArea`だけが`AreaEditorPage`に渡り、
郵便番号自体はどこにも渡らない・保存されない（`SettingsRepository`が保存する
`CollectionArea`にも郵便番号に相当するフィールドは無い）。画面上にもその旨の注記を出す
（[requirements.md](requirements.md) 4.1節）。

ホーム・カレンダーの日付タップは共通の`showDayDetailSheet`（`lib/ui/widgets/day_detail_sheet.dart`）
を呼ぶ、モーダルボトムシート1種類に集約している。

## 6. UI層の設計方針

- `CategoryStyle`（`lib/ui/category_style.dart`）が区分→色・アイコンの対応を一元管理する。
  画面側が区分ごとに色分岐を書かないようにするための唯一の変換点
- `CategoryBadge`が区分の色・アイコン・短縮名をまとめた共通部品。ホームの一覧・カレンダーの
  凡例など、区分を小さく表示する箇所はすべてこれを使う
- カレンダーのセルだけは`CategoryBadge`を使わず`_CategoryStrip`という専用の帯表示にしている
  （セルの高さが74pxしかなく、バッジのpadding込みだと3件目が入らないため）。
  帯を並べる余白は`Column`の`spacing`で項目の間だけに入れる。各帯にpaddingで
  持たせると、ちょうど3段の日だけ末尾に使わない1pxが残って溢れる
- `CategoryPill`は分別の一覧で使う。5区分に入らない出し先（粗大ごみ・小型家電・
  電池・収集できないもの）にも同じ形を使う。利用者から見ればどれも「どこに出すか」で
  区別はないため
- `SectionHeader`（区切り線＋見出し）と`ExternalLinkTile`（外部ブラウザへ出る項目）は
  設定と「このアプリについて」で共用する
- `paren_wrap.dart`の`keepParenthesesTogether`は、括弧の中で行が折り返されないようにする。
  括弧の中の文字どうしを`WORD JOINER`（U+2060）でつなぐと、行送りが括弧の手前まで戻り、
  括弧全体が次の行へ回る
- `note_format.dart`の`formatNote`は、注意点の「※」の手前で改行する。早見表は1つの欄に
  複数の但し書きを詰め込んでいて、そのままだと前の文と地続きになって読みにくい

## 7. テスト方針

```
test/domain/    domain層の純粋な単体テスト（Widgetを一切使わない）
test/data/      AreaCatalogのJSONパースのテスト
test/features/  ウィジェットテスト。test/support/test_app.dart で
                ProviderScope + overrideWithValue した MaterialAppを組み立て、
                日付と時刻を固定して検証する
test/ui/        配色のコントラスト（WCAG AA）と、文字列の折り返しの検証
```

日付に依存する画面（ホーム・カレンダー）のテストは`nowProvider`／`todayProvider`を
固定値でオーバーライドすることで、実行日時に左右されない再現可能なテストにしている。
`pumpApp`の`now`を省略すると「その日の正午」になる（＝出す期限を過ぎた状態）。
期限前の表示を試すときだけ朝の時刻を渡す。

配色は`test/ui/category_style_test.dart`でWCAG AAのコントラスト比を検証している。
地の色は`SaitamaGomiApp.surfaceOf(brightness)`から取る。`ColorScheme.fromSeed`の
既定値ではなく実際に使う色の上で測らないと意味がないため。
`test/ui/surface_tint_test.dart`は、地の上に重なる面（`surfaceContainer`系）が
緑に寄っていないかを総なめで見る。役割ごとに1色ずつ潰していくと漏れるため。

## 8. CI / ローカルフック

- `.github/workflows/ci.yml`：push（main）・PR時に`flutter pub get` → `dart format
  --set-exit-if-changed` → `flutter analyze` → `flutter test` をUbuntu上で実行
- `.githooks/pre-commit`：同じ3チェックをコミット前にローカルで実行する任意フック。
  `git config core.hooksPath .githooks`で有効化
- 実機/シミュレータ向けの`flutter build ios`はCIに含めていない（macOSランナーは
  Actionsの無料枠消費が大きいため、必要になった段階で別ジョブに切り出す）
- `scripts/build_testflight.sh`：TestFlightへの配信を1コマンドで行う。
  `flutter build ipa`を使わないのは、あれが自動署名を前提にしていてXcodeに
  サインイン済みのアカウントを探しに行くため。アーカイブまでをflutterに任せ、
  書き出しは手動署名で行う。ビルドした瞬間のコミットと作業ツリーの状態を
  `store_assets/app_store/BUILDS.md`に自動で記録する（詳細は同ファイル）
- 配信に要るApp Store Connectの識別子は`~/.appstoreconnect/`から拾う。key IDは
  `private_keys/AuthKey_*.p8`のファイル名から、issuer IDは`issuers`
  （`<key-id> <issuer-id>`の並び）から。リポジトリ内に置かないのは、公開リポジトリで
  Appleアカウントを晒さないためと、worktreeを作るたびに用意し直すのを避けるため。
  他のアプリからも同じ場所を読めばよい。issuer ID自体は秘密ではない（Keysページに
  平文で出る値で、`.p8`秘密鍵が無ければ使えない）

## 9. ホーム画面ウィジェット

iOSのウィジェットは**アプリとは別プロセス**で動くので、Flutter側の保存領域からは
読めない。App Groupで共有した領域を通して内容を渡す。

```
lib/domain/widget_payload.dart   ウィジェットに渡す内容を組み立てる（純粋なDart）
lib/data/widget_bridge.dart      共有領域への書き出しを頼む口（MethodChannel）
ios/Runner/AppDelegate.swift     受け取ったJSONをApp Groupに置き、再描画を促す
ios/GomiWidget/                  ウィジェット本体（SwiftUI）
```

**収集日の計算はDartに一本化する。** ロジックをSwiftにも書くと、片方だけ直したときに
アプリとウィジェットで表示が食い違う。アプリを開いたときに先60日ぶんを計算して
書き出し、ウィジェットはそれを読んで並べるだけにする（通知機能と同じ考え方）。

例外は**分別の名前・色・アイコン**で、これはSwift側にも持つ（`GomiData.swift`）。
共有領域に載せるとデータが増えるうえ、配色を変えるたび書き直しが要る。
区分そのものは市の制度なのでそう変わらない。

「収集日の朝は期限を過ぎるまで今日を出す」規則はウィジェット側にも要る
（アプリが起動していなくても時間は進むため）。`GomiPayload.featured(at:)` が
`CollectionCalendar.featuredDay` と対応している。

タイムラインは**表示が切り替わる時刻にだけ**更新する。切り替わるのは
「日付が変わったとき」と「出す期限を過ぎたとき」の2つだけなので、
その節目をタイムラインに並べる。

### Xcodeプロジェクトへの組み込み

ターゲットの追加は`scripts/add_widget_target.rb`（`xcodeproj` gem）で行う。
何度流しても同じ結果になるので、`ios/Runner.xcodeproj`を作り直したときも再実行できる。

はまりどころが2つある。

- **埋め込みフェーズは`Thin Binary`より前に置く**。後ろに置くと依存が循環して
  ビルドが失敗する（`Cycle inside Runner`）
- **ウィジェットにもFlutterのxcconfigを参照させる**。`FLUTTER_BUILD_NUMBER`が
  解決されず`CFBundleVersion`が空になると、拡張のインストールに失敗する
  （`Failed to create app extension placeholder`）

### 署名

App Groupを使うので、配信の署名まわりに要件が増えた。

- **Release構成は手動署名に固定する**（`CODE_SIGN_STYLE = Manual` と
  `PROVISIONING_PROFILE_SPECIFIER`）。自動署名のままだと
  `iOS Team Provisioning Profile: *` が選ばれ、App Groupを含まないので
  アーカイブが落ちる
- **アーカイブは署名ありで作る**。`--no-codesign`だとentitlementsが
  アーカイブに残らず、後から書き出しても署名に入らない。
  ウィジェットが共有領域を読めなくなる
- **プロファイルは2つ要る**（アプリ本体・ウィジェット）。
  書き出しの`ExportOptions.plist`に両方書く

App Group自体（`group.io.github.ktakada42.saitamagomicalendar`）の作成と、
各Bundle IDへの割り当ては**Developerサイトでの手作業**。App Store Connect API
には`appGroups`のエンドポイントが無い。Bundle IDの登録と
App Groups capabilityの有効化まではAPIでできる。

## 10. 配布

- **iPhone専用**（`TARGETED_DEVICE_FAMILY = 1`）。画面はすべて縦1カラムの前提で
  作っており、iPadの広い画面では余白ばかりが広がって使いやすくならない。
  App Storeへの提出でiPad用スクリーンショットを求められなくなる利点もある
- `ITSAppUsesNonExemptEncryption = false` を`Info.plist`に書いてある。
  書いておかないとアップロードのたびに手作業の申告を求められ、それまで
  TestFlightの配信が止まる。HTTPS以外の暗号化は使っていないので輸出規制の対象外
- App Store用のスクリーンショットは`store_assets/screenshots/`。素のものと、
  キャッチコピーの帯を足した提出用の両方を置いてある。
  装飾版は`scripts/make_store_screenshots.py`で生成する

## 11. 意図的にやっていないこと

- 状態管理をRiverpodの`Notifier`以上に複雑なもの（Bloc等）にしていない。画面数・状態の
  複雑さに対してRiverpodのAsyncNotifier + Providerで十分なため
- ルーティングパッケージ（go_router等）を導入していない。画面遷移は
  `Navigator.push`と`IndexedStack`の切り替えだけで表現できる規模のため
- ドメイン層の`CollectionRule`/`CollectionArea`はfreezed等のコード生成を使わず手書き。
  `==`/`toJson`/`fromJson`の量が少なく、生成コストに見合わないため
