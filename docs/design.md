# 設計書

対象読者：このリポジトリに手を入れる開発者。「何を作るか」は[requirements.md](requirements.md)、
「どう作ってあるか／どう作るか」をここに書く。

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

CalendarExport(area)
  └ 収集日をiCalendar（.ics）形式の文字列にする
  └ 日付ごとに個別イベントを並べず、繰り返しルール（RRULE）で表すのでイベント数が少ない
  └ 文字列を作るだけの純粋なDart。ファイル書き出しと共有はdata層（CalendarShare）
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

CalendarShare                収集日を.icsに書き出して共有シートに渡す（abstract）
  実装は_FileCalendarShare（path_provider + share_plus）。
  テストからは NoopCalendarShare に差し替える

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

`readArea()`は保存データのJSONパースに失敗しても例外を投げず`null`を返す。壊れた保存データで
起動不能になるより、未設定（初回設定）として復旧できる方を優先している。

## 4. 状態管理（Riverpod）

`lib/providers.dart`がdata層・domain層を画面につなぐ唯一の場所。

```
settingsRepositoryProvider  FutureProvider<SettingsRepository>
areaCatalogProvider         FutureProvider<AreaCatalog>

selectedAreaProvider        AsyncNotifierProvider<SelectedArea, CollectionArea?>
  build()  起動時に SettingsRepository から読み込む。未設定なら null
  save(area) / clear()  書き込みと同時にstateも更新（永続化層を読み直さない）

todayProvider                Provider<DateTime>
  DateTime.now()をここに集約。画面から直接呼ばないことで、
  テストで overrideWithValue して任意の日付を固定できる

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
    │       ├ HomePage      明日を最大化、今日、この先6件、区分ごとの次回
    │       ├ CalendarPage  月表示、前後月に送れる
    │       └ SettingsPage  地区変更・設定中の曜日・区分ごとの出し方
    └ AsyncError             → エラー表示（設定読み込み失敗）

AreaPickerPage(isOnboarding: true)   … 初回設定の入口（_Rootから直接）
AreaPickerPage(isOnboarding: false)  … SettingsPage「地区を選び直す」から遷移
  └ 郵便番号 or 一覧で CollectionArea を選ぶ
     → push: AreaEditorPage(initial: 選んだarea, isOnboarding: 同じ値)
  └ 「自分の地区が見つからない」
     → push: AreaEditorPage(initial: null, isOnboarding: 同じ値)

AreaEditorPage(initial: area, isOnboarding: false)  … SettingsPage「お住まいの地区」から
                                                        遷移する、曜日を直接編集する画面
```

`AreaPickerPage`（`lib/features/area/area_picker_page.dart`）が「地区をどう特定するか」、
`AreaEditorPage`が「曜日をどう確認・調整するか」を担う。前者は必ず後者を
`Navigator.push`した先に手渡す構造で、`AreaEditorPage`自体は
[requirements.md](requirements.md) 4.1節の主経路・代替経路の両方で共有される
（渡す`initial`が「地区データそのまま」か「null（空欄）」かの違いだけ）。

`AreaEditorPage._save()`は保存後に必ず`Navigator.pop()`する。初回設定でも
`AreaPickerPage`からのpushを経由するようになったため、pop先は常に存在する
（pop後、その下に隠れていた`_Root`が`selectedAreaProvider`の更新を検知して
`HomeShell`に切り替わる）。

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
  （セルの高さが74pxしかなく、バッジのpadding込みだと3件目が入らないため）

## 7. テスト方針

```
test/domain/    domain層の純粋な単体テスト（Widgetを一切使わない）
test/data/      AreaCatalogのJSONパースのテスト
test/features/  ウィジェットテスト。test/support/test_app.dart で
                ProviderScope + overrideWithValue(todayProvider, ...) した
                MaterialAppを組み立て、日付を固定して検証する
```

日付に依存する画面（ホーム・カレンダー）のテストは`todayProvider`を固定日付で
オーバーライドすることで、実行日に左右されない再現可能なテストにしている。

## 8. CI / ローカルフック

- `.github/workflows/ci.yml`：push（main）・PR時に`flutter pub get` → `dart format
  --set-exit-if-changed` → `flutter analyze` → `flutter test` をUbuntu上で実行
- `.githooks/pre-commit`：同じ3チェックをコミット前にローカルで実行する任意フック。
  `git config core.hooksPath .githooks`で有効化
- 実機/シミュレータ向けの`flutter build ios`はCIに含めていない（macOSランナーは
  Actionsの無料枠消費が大きいため、必要になった段階で別ジョブに切り出す）

## 9. 意図的にやっていないこと

- 状態管理をRiverpodの`Notifier`以上に複雑なもの（Bloc等）にしていない。画面数・状態の
  複雑さに対してRiverpodのAsyncNotifier + Providerで十分なため
- ルーティングパッケージ（go_router等）を導入していない。画面遷移は
  `Navigator.push`と`IndexedStack`の切り替えだけで表現できる規模のため
- ドメイン層の`CollectionRule`/`CollectionArea`はfreezed等のコード生成を使わず手書き。
  `==`/`toJson`/`fromJson`の量が少なく、生成コストに見合わないため
