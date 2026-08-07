# 次フェーズ仕様・設計

A（地区表の取り込み）は[requirements.md](requirements.md) 4.1節で初回設定の**主経路**と
定めており、データ取り込み（A.4）・UI（A.2/A.3）とも実装済み。以下は実装の記録と、
再取得・保守のための指針。B（ローカル通知）も実装済み。

## A. 地区表の取り込み（実装済み）

### A.1 目的

収集曜日は利用者が決めるものではなく、住んでいる地区で市がすでに決めているものである。
「利用者が自分で収集曜日を登録する」方式は、地区表データ（`areas.json`の`areas`）を
持たない間の暫定の代替手段だった。今は町丁目から地区を選ぶだけで収集曜日が確定する
`AreaPickerPage`が主経路になっている。

### A.2 仕様（実装済み）

- 初回設定・地区変更の入口を`AreaPickerPage`（[design.md](design.md) 5章）にした
  - 郵便番号（7桁）を入力すると、`AreaCatalog.areasForPostalCode()`で候補を絞り込む。
    郵便番号は地区特定にのみ使い、端末にも保存しない旨を画面に明示している
    （[requirements.md](requirements.md) 4.1節）
  - 郵便番号を使わない場合は、区（`saitamaWards`のChoiceChip）→ 地区一覧（`areasInWard`）
    から選べる。1区に複数パターンあるのが通常（例：西区には収集曜日パターンが3つある）
  - 選ぶと区分ごとの収集曜日・早朝収集地区かどうかが確定した状態で`AreaEditorPage`に
    反映される。反映後もこれまでどおり曜日を個別に調整できる
- 「自分の地区が見つからない」を選んだ場合のみ、区分ごとに曜日を手入力する
  `AreaEditorPage`の入力UIに進む代替経路として残した
- 設定画面に「地区を選び直す」を追加し、いつでも`AreaPickerPage`に戻れるようにした

**郵便番号での絞り込み精度の実測**：270件の郵便番号のうち、1件に絞れたのは239件
（約88.5%）、複数候補が残ったのは31件（約11.5%）だった。複数候補が残るのは、
たとえば「三橋」という郵便番号が西区の複数の収集パターンにまたがっているような、
郵便番号の粒度が収集区分の粒度より粗いケース。町丁目アイテム4件（団地名など）は
郵便番号データ側に個別の項目が無く、郵便番号検索の対象外になっている
（実害はなく一覧・手入力にフォールバックする）。

### A.3 設計（実装済み）

```
AreaCatalog
  areasInWard(ward)              実装済み・テスト済み
  areasForPostalCode(postalCode) 実装済み・テスト済み。postalAreas と areas を突き合わせる
  postalAreas: Map<String, List<String>>  郵便番号 → areasのid一覧

AreaPickerPage (lib/features/area/area_picker_page.dart)
  郵便番号 or 一覧で CollectionArea を選ぶ、または「自分の地区が見つからない」
   → push: AreaEditorPage(initial: 選んだarea または null, isOnboarding: 同じ値)
```

`AreaEditorPage`自体への変更は最小限（`initState`が元々`initial`からプリフィルする
仕組みを持っていたので、ピッカー側から`_applyPreset`等を呼ぶ必要は無かった）。
変更したのは`_save()`の保存後の遷移（常に`pop`するように統一。詳細はdesign.md 5章）。

### A.4 データ整備（完了。以降は再取得・保守の指針）

**経緯（方針転換）**：当初は市公式サイトが内部で使っている第三者ベンダーのウィジェット
「gomisuke」（株式会社G-Placeが自治体向けに有料提供しているSaaS製品）の非公開JSONP APIから
`areas`を生成していた。しかしgomisukeは自治体が費用を払って導入する商用製品であり、
その編集済みデータベースを非公式APIから抽出してアプリに同梱することには、
著作権（データベースの著作物）・さいたま市自身のサイト利用規約（無断転載の禁止）・
gomisukeの利用規約の観点で懸念があった（#18で指摘）。

代わりに、**さいたま市自身が配布しているPDFマニュアル**「家庭ごみの出し方マニュアル」
（[requirements.md](requirements.md) 5.4節の`source`）に含まれる「地区別ごみ収集曜日
一覧表」（P18-19）を直接読み取る方式に切り替えた。これは市が住民向けに配布している
一次資料そのもので、第三者ベンダーを一切経由しない。

```
scripts/extract_manual_schedule.py  PDFをダウンロードし、地区別ごみ収集曜日一覧表を
                                     pdfplumberで読み取って町丁目ごとのJSONを出力する
scripts/update_areas_json.mjs       上記を実行し、日本郵便の郵便番号データと突き合わせて
                                     assets/data/areas.json を書き出す
```

一覧表はA4見開き2ページの罫線なしの表（区ごとに列を分けたレイアウト）で、
PDF内部の座標がページ境界をまたいで共有されている作りだったため、抽出には
座標クラスタリング（列の実データの左端の位置から境界を決め、縦書きの
「西部/東部清掃事務所」バナーやページ隅の縦書きタイトルが表の一部の列に
重なって誤って混入する問題を個別に除外）が必要だった。抽出結果は以下で検証している。

- 2種類の独立した抽出手法（pdfplumberの座標ベース抽出と、`pdftotext -layout`の
  テキストレイアウト抽出）で同じ行を突き合わせ、完全一致することを確認した
- 抽出前に使っていたgomisukeの実データ（このQAのためだけに一度だけ再取得し、
  検証後は破棄・コミットしていない）と町丁目単位で突き合わせ、一致しない場合は
  上記2手法での再確認を行った。不一致の大半はgomisuke側のグルーピングが
  この一覧表より粗い（複数の町丁目を1パターンにまとめている）ことによるもので、
  一覧表の方が新しく（令和8年3月1日時点）・粒度が細かい

一覧表では、もえないごみ・資源物2類・有害危険ごみの3区分がひとつの「共通」列に
まとまっている（この3区分が同じ曜日にまとめて収集される地区が多いことは
`lib/domain/collection_area.dart`のコメントにも既に書かれている）。抽出時はこの1つの
共通曜日値を`nonBurnable`・`hazardous`・`recyclable2`の3つのCollectionRuleに複製している。

町丁目ごとの行が320件（もえるごみ早朝地区の★1マークも町丁目単位でそのまま反映）。
一覧表内の全パターンが「毎週」で、月内の週番号を限定する運用（第2・第4など）は
無かった（5.2節参照）。★3（市が「近隣の方や地元自治会にお尋ねください」としている、
一覧表だけでは曜日を確定できない地区。浦和区神明1・2丁目の一部が該当）は、
不確かな情報を提示するより地区が見つからない代替経路にフォールバックさせる方が
誠実と考え、生成対象から除外している。

**郵便番号データ（`postalAreas`）**：`update_areas_json.mjs`が、日本郵便の公開データ
（「住所の郵便番号」全国一括CSV、`utf_ken_all.zip`）を取得し、`areas`の各町丁目名
（丁目番号・かっこ書きを除いたベース名）と突き合わせて`postalAreas`（郵便番号→`areas`の
`id`一覧）を作る。ZIPの展開にはシステムの`unzip`コマンドを使う（Node標準機能だけでは
ZIPコンテナを読めないため）。町丁目名がどちらのデータにも同じ表記で出てくる前提の
突き合わせなので、表記ゆれ（団地名など、郵便番号データ側に個別の項目が無いもの）が
ある町丁目はマッチしないことがある（実例8件。実害はなく一覧・手入力にフォールバックする）。

**再取得・保守**：`node scripts/update_areas_json.mjs`を実行すると常に最新の`areas`・
`postalAreas`に更新できる。内部で呼ぶ`extract_manual_schedule.py`は`pdfplumber`が必要
（事前に`python3 -m venv .venv && .venv/bin/pip install pdfplumber`）。マニュアルが
改版されて一覧表のレイアウトが変わった場合、`extract_manual_schedule.py`内の列座標
（`COL_BOUNDS`等）の再計測が必要になる可能性がある。抽出件数が想定範囲（250〜400件）
から外れた場合はスクリプトが警告を出す。生成結果は必ず`flutter test`
（`test/data/area_catalog_test.dart`）と差分レビューをしてからコミットすること。

## B. 収集日前夜のローカル通知（実装済み）

### B.1 目的

ごみ出しは前夜に思い出す行動（[requirements.md](requirements.md) 1章）という設計方針の
延長線上として、アプリを開かなくても前夜に気づける手段を用意する。

### B.2 仕様（実装済み。[requirements.md](requirements.md) 4.6節）

- 設定画面に通知のON/OFFスイッチと通知時刻を置いた（既定はOFF、時刻は20:00）
- 通知対象は「翌日に収集がある区分」。複数区分ある日は1通にまとめる
  （例：「明日はもえるごみ・資源物1類の日です」）
- 収集のない日・年末年始の休止期間（1/1〜1/3）の前夜は通知しない
- ONにするタイミングでOSの通知許可を求める。拒否された場合はONにせず、
  端末の設定アプリから許可する必要がある旨をスナックバーで伝える
  （iOSは一度拒否されるとアプリからダイアログを出せないため）

**未実装**：通知をタップしてホーム（明日のカード）を開く導線。
通知を開くと結局アプリのトップに来るので実用上の不足は小さく、
`onDidReceiveNotificationResponse`での画面遷移は別途対応でよいと判断した。

### B.3 設計（実装済み）

```
CollectionReminderPlanner (lib/domain/collection_reminder.dart)
  plan(from, notifyAt, horizonDays, limit) -> List<CollectionReminder>
  「いつ何を通知すべきか」だけを計算する純粋なDart。OSには触らない

NotificationRepository (lib/data/notification_repository.dart)
  abstract。requestPermission / reschedule / cancelAll
  実装は _PluginNotificationRepository（flutter_local_notifications + timezone）
  テストからは NoopNotificationRepository に差し替える

NotificationController (lib/providers.dart)
  設定の保存と、上2つをつなぐ。設定変更時と地区変更時に予約を張り直す
```

- `flutter_local_notifications`を導入した（ローカル通知のみなので、サーバー通信を
  持たない方針（[requirements.md](requirements.md) 6章）と矛盾しない）
- スケジューリングは、OS標準の「毎週◯曜」繰り返しではなく、直近30日分を
  日付ごとに個別予約する方式にした
  - 理由：`CollectionRule`の第◯曜日パターンはOS標準の繰り返し通知だけでは表現できない。
    日付ごとに個別スケジュールするほうが`CollectionCalendar`の判定ロジックを
    そのまま使い回せて二重実装にならない
  - 予約は差分更新せず毎回全部張り直す。地区や時刻を変えたときに古い予約が残らないので、
    状態のずれを考えなくて済む
  - 通知IDは収集日から決まる（`20260807`のような年月日の連結）。同じ日には必ず
    同じIDが振られるので、張り直しても二重登録されない
- タイムゾーンは`Asia/Tokyo`固定。端末のタイムゾーンを見に行くと追加依存が必要になるうえ、
  日本以外で使う想定がない
- 通知ON/OFFと時刻は`SettingsRepository`が保存する（`CollectionArea`とは別キーなので、
  地区を選び直しても通知設定は保たれる）

### B.4 テスト方針（実装済み）

`flutter_local_notifications`のOS連携部分はウィジェットテストで検証できないため、
「地区のルールから通知すべき日付・区分の集合を計算する」ロジックを
`CollectionReminderPlanner`として`lib/domain/`に切り出し、そこを単体テストで担保した
（`test/domain/collection_reminder_test.dart`、9件）。OS API呼び出し自体はテストしない。

設定画面のウィジェットテストでは、`notificationRepositoryProvider`を
`NoopNotificationRepository`に差し替えている（`test/support/test_app.dart`）。

## C. スコープ外のまま据え置くもの

粗大ごみの受付可否判定・「これは出せるか」をAIに聞く機能は、A・Bより前提となる情報
（品目ごとの判定基準、市への申込導線）の整理が別途必要なため、本ドキュメントでは
仕様化しない。着手する場合は先に別ドキュメントとして要件を切り出す。
