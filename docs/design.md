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
            全面的に依存するデータ（現状空。next-phase.md A章参照）
  presets:  曜日入力の雛形。地区が見つからない代替経路でのみ使う

SettingsRepository           shared_preferences 経由でCollectionAreaを1件だけ保存
  readArea() / writeArea() / clear()
  保存形式は CollectionArea.toJson() のJSON文字列まるごと。
  IDだけでは復元できない（ユーザーがプリセットから曜日を調整できるため）
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
```

画面が直接触るのはこの5つのproviderのみ。`AreaEditorPage`だけが
`selectedAreaProvider.notifier`経由で書き込みを行う。

## 5. 画面構成・遷移

```
SaitamaGomiApp (MaterialApp, ja固定)
 └ _Root  selectedAreaProviderを見て分岐
    ├ area == null            → AreaEditorPage(isOnboarding: true)
    ├ area != null            → HomeShell
    │   └ IndexedStack（タブ切り替えでカレンダーの表示月を失わないため）
    │       ├ HomePage      明日を最大化、今日、この先6件、区分ごとの次回
    │       ├ CalendarPage  月表示、前後月に送れる
    │       └ SettingsPage  地区変更・設定中の曜日・区分ごとの出し方
    └ AsyncError             → エラー表示（設定読み込み失敗）

AreaEditorPage(initial: null, isOnboarding: true)   … 初回設定
AreaEditorPage(initial: area, isOnboarding: false)  … SettingsPageから遷移する変更画面
```

初回設定と設定変更は同一Widget（`AreaEditorPage`）。`isOnboarding`でAppBarの戻るボタンと
文言だけを切り替え、入力UI自体は共通にしている。

**現状の`AreaEditorPage`は曜日の手入力を主UIとして描いているが、これは
[requirements.md](requirements.md) 4.1節で定めた「地区を選べば曜日は自動で決まる」という
目標形ではなく、地区データが空である現状に合わせた暫定の姿。** `areas.json`にデータが入り
次第、区→地区選択を主UIに置き換え、曜日の手入力（現行の`_CategoryEditor`一式）は
「地区が見つからない」を選んだ場合の代替経路に格下げする（詳細はnext-phase.md A章）。
`_applyPreset`が`CollectionArea`を受けて`_drafts`に反映する処理は、対象が`presets`か`areas`かに
関わらず同じ形で再利用できる見込み。

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
