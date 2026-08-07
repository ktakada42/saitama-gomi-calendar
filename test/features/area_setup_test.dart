import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/settings/settings_page.dart';

import '../support/test_app.dart';

void main() {
  group('初回起動', () {
    testWidgets('地区が未設定なら地区確認画面から始まる', (tester) async {
      await pumpRootApp(tester, area: null);

      expect(find.text('お住まいの地区を確認'), findsOneWidget);
      expect(find.text('郵便番号で探す'), findsOneWidget);
      // 郵便番号は保存されない旨の案内が出ていること。
      expect(find.textContaining('保存はされません'), findsOneWidget);
      // 設定前は本体のタブが出ていないこと。
      expect(find.text('カレンダー'), findsNothing);
    });

    testWidgets('地区が見つからない場合は曜日を手入力できる', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.tap(find.text('自分の地区が見つからない'));
      await tester.pumpAndSettle();
      expect(find.text('収集曜日を自分で設定'), findsOneWidget);
      // 地区が特定できない経路なので、入力を助ける雛形が出る。
      expect(find.text('入力の出発点'), findsOneWidget);

      await tester.tap(find.text('見沼区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('もえるごみが月・木の地区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この設定ではじめる'));
      await tester.pumpAndSettle();

      expect(find.text('見沼区　わたしの地区'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    });

    testWidgets('手入力のときは早朝収集を自分で選べる', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.tap(find.text('自分の地区が見つからない'));
      await tester.pumpAndSettle();

      // 地区データが無い経路なので、早朝収集地区かどうかは利用者が指定する。
      // 画面下部にあるのでスクロールしてから確かめる。
      await tester.scrollUntilVisible(
        find.byType(SwitchListTile),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('地区データを読み込めなくても手入力に進める', (tester) async {
      await pumpRootApp(tester, area: null, failCatalog: true);

      // 読み込みに失敗したまま回り続けず、何が起きたかを伝える。
      expect(find.text('地区データを読み込めませんでした。'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 地区データが無くても、曜日を手入力すれば使える。
      await tester.tap(find.text('収集曜日を自分で設定する'));
      await tester.pumpAndSettle();
      expect(find.text('収集曜日を自分で設定'), findsOneWidget);
    });

    testWidgets('手入力で曜日をひとつも選ばないと先に進めない', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.tap(find.text('自分の地区が見つからない'));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'この設定ではじめる');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    });

    testWidgets('郵便番号が7桁そろうまで探せない', (tester) async {
      await pumpRootApp(tester, area: null);

      final button = find.widgetWithText(FilledButton, '探す');
      // 途中の桁で探しても「該当なし」としか返せず、入力を間違えたのか
      // 対応する地区が無いのかが分からない。
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '330000');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '3300001');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('候補から選んで保存すると、候補の画面には戻らない', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('お住まいの地区'));
      await tester.pumpAndSettle();

      // 複数の候補が出る郵便番号。
      await tester.enterText(find.byType(TextField).first, '3300002');
      await tester.pump();
      await tester.tap(find.text('探す'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('大宮区　テスト町二丁目東側'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存する'));
      await tester.pumpAndSettle();

      // 候補が並んだ画面に着地すると、何の画面か・保存できたのかが分からない。
      expect(find.text('大宮区　テスト町二丁目西側'), findsNothing);
      expect(find.text('お住まいの地区を確認'), findsNothing);
      // 設定画面まで戻り、選んだ地区が入っている。
      expect(find.text('大宮区　テスト町二丁目東側'), findsOneWidget);
    });

    testWidgets('郵便番号で1件に絞れたら選ぶだけで進める', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.enterText(find.byType(TextField), '3300001');
      // 桁がそろって「探す」が押せるようになるまで描き直す。
      await tester.pump();
      await tester.tap(find.text('探す'));
      await tester.pumpAndSettle();

      expect(find.text('見沼区　テスト町一丁目'), findsOneWidget);
      await tester.tap(find.text('見沼区　テスト町一丁目'));
      await tester.pumpAndSettle();

      // 選んだ地区の曜日があらかじめ反映されている。
      expect(find.text('収集曜日の確認'), findsOneWidget);
      // 地区が確定しているので、入力を助ける雛形は出さない。
      expect(find.text('入力の出発点'), findsNothing);
      await tester.tap(find.text('この設定ではじめる'));
      await tester.pumpAndSettle();

      expect(find.text('見沼区　テスト町一丁目'), findsOneWidget);
    });

    testWidgets('郵便番号で候補が複数あれば一覧から選ぶ', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.enterText(find.byType(TextField), '3300002');
      // 桁がそろって「探す」が押せるようになるまで描き直す。
      await tester.pump();
      await tester.tap(find.text('探す'));
      await tester.pumpAndSettle();

      expect(find.text('大宮区　テスト町二丁目東側'), findsOneWidget);
      expect(find.text('大宮区　テスト町二丁目西側'), findsOneWidget);

      await tester.tap(find.text('大宮区　テスト町二丁目西側'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この設定ではじめる'));
      await tester.pumpAndSettle();

      expect(find.text('大宮区　テスト町二丁目西側'), findsOneWidget);
    });

    testWidgets('該当しない郵便番号ならその旨を伝える', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.enterText(find.byType(TextField), '3300099');
      // 桁がそろって「探す」が押せるようになるまで描き直す。
      await tester.pump();
      await tester.tap(find.text('探す'));
      await tester.pumpAndSettle();

      expect(find.textContaining('特定できませんでした'), findsOneWidget);
    });

    testWidgets('郵便番号を使わず一覧からも選べる', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.tap(find.text('大宮区'));
      await tester.pumpAndSettle();

      expect(find.text('大宮区　テスト町二丁目東側'), findsOneWidget);
      expect(find.text('大宮区　テスト町二丁目西側'), findsOneWidget);
    });
  });

  group('設定画面', () {
    testWidgets('設定中の曜日を区分ごとに読める', (tester) async {
      await pumpApp(tester, const SettingsPage());

      expect(find.text('浦和区　テスト地区'), findsOneWidget);
      expect(find.text('毎週月・木曜日'), findsOneWidget);
      expect(find.text('第2火曜日'), findsOneWidget);
      expect(find.text('第4火曜日'), findsOneWidget);
      expect(find.text('毎週水曜日'), findsOneWidget);
    });

    testWidgets('お住まいの地区からは地区を選び直せる', (tester) async {
      await pumpRootApp(tester);

      // IndexedStack で全タブが組み立て済みなので、AppBar のタイトルと
      // ナビゲーションのラベルが同じ文字列になる。アイコンで指す。
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('お住まいの地区'));
      await tester.pumpAndSettle();

      // 曜日の編集画面ではなく、地区を選び直す画面に入る。
      expect(find.text('お住まいの地区を確認'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '3300001');
      // 桁がそろって「探す」が押せるようになるまで描き直す。
      await tester.pump();
      await tester.tap(find.text('探す'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('見沼区　テスト町一丁目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存する'));
      await tester.pumpAndSettle();

      expect(find.text('見沼区　テスト町一丁目'), findsOneWidget);
    });

    testWidgets('収集曜日を修正するからは区や地区名を変えられない', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('収集曜日を修正する'));
      await tester.pumpAndSettle();

      // 市の一覧から選んだ地区で区だけ差し替えられると、
      // 「岩槻区高砂三丁目」のような実在しない地区ができてしまう。
      expect(find.widgetWithText(ChoiceChip, '岩槻区'), findsNothing);
      expect(find.widgetWithText(TextField, '地区の名前（任意）'), findsNothing);
      // 今の地区は読めるようにしておく。
      expect(find.textContaining('浦和区'), findsWidgets);
    });

    testWidgets('収集曜日を修正するからは曜日を直せる', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('収集曜日を修正する'));
      await tester.pumpAndSettle();

      expect(find.text('収集曜日の確認'), findsOneWidget);

      // もえるごみは月・木。金曜も足して保存する。
      await tester.tap(find.text('金').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存する'));
      await tester.pumpAndSettle();

      // 保存すると設定画面まで戻る。地区を選ぶ画面には着地しない。
      expect(find.text('収集曜日の確認'), findsNothing);
      // 曜日だけが変わり、地区はそのまま。
      expect(find.text('毎週月・木・金曜日'), findsOneWidget);
      expect(find.textContaining('テスト地区'), findsWidgets);
    });

    testWidgets('地区を選んで来たときは早朝収集の切り替えを出さない', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('収集曜日を修正する'));
      await tester.pumpAndSettle();

      // 早朝収集地区かどうかは地区データ側で確定しているので、
      // 利用者に切り替えさせない。
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('画面の明るさは既定でライト、設定から切り替えられる', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      // 端末がダークモードでも、既定はライト固定。
      expect(find.text('ライト'), findsOneWidget);

      await tester.tap(find.text('画面の明るさ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('端末の設定に合わせる').last);
      await tester.pumpAndSettle();

      expect(find.text('端末の設定に合わせる'), findsOneWidget);
    });

    testWidgets('前日のお知らせは既定でOFF、ONにすると時刻を選べる', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      // 既定はOFF。時刻の項目もまだ出さない。
      final toggle = find.widgetWithText(SwitchListTile, '前日にお知らせ');
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(find.text('お知らせの時刻'), findsNothing);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      // ONにすると時刻を選べるようになる。既定は20:00。
      expect(find.text('お知らせの時刻'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
    });

    testWidgets('時刻はホイールで5分刻みに選ぶ', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, '前日にお知らせ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('お知らせの時刻'));
      await tester.pumpAndSettle();

      // Materialの文字盤ではなく、iOSのホイールを出す。
      final picker = find.byType(CupertinoDatePicker);
      expect(picker, findsOneWidget);
      expect(tester.widget<CupertinoDatePicker>(picker).minuteInterval, 5);
      // 決めるまでは変えない。
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('決定'), findsOneWidget);
    });

    testWidgets('時刻を選ぶ見出しは左右のボタンと同じ高さの中央に来る', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, '前日にお知らせ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('お知らせの時刻'));
      await tester.pumpAndSettle();

      // 見出しをボタンと同じ行に並べると、「キャンセル」と「決定」の
      // 文字数の差だけ中央からずれる。3つとも同じ高さに揃っていること。
      final cancel = tester.getRect(find.text('キャンセル'));
      final title = tester.getRect(find.text('お知らせの時刻').last);
      final ok = tester.getRect(find.text('決定'));
      expect(title.center.dy, closeTo(cancel.center.dy, 0.5));
      expect(title.center.dy, closeTo(ok.center.dy, 0.5));

      // 見出しはシートの横幅の中央にある。
      final sheetWidth = tester.getSize(find.byType(CupertinoDatePicker)).width;
      expect(title.center.dx, closeTo(sheetWidth / 2, 0.5));
    });

    testWidgets('折りたたみはスクロールしても開いたままになる', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('もえるごみ').last,
        200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('もえるごみ').last);
      await tester.pumpAndSettle();
      // 開くと代表品目が見える。
      expect(find.textContaining('生ごみ'), findsWidgets);

      // いったん画面外まで動かしてから戻す。ListViewはこの間にウィジェットを
      // 捨てるので、キーが無いと閉じた状態に戻ってしまう。
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.drag(scrollable, const Offset(0, 600));
      await tester.pumpAndSettle();

      expect(find.textContaining('生ごみ'), findsWidgets);
    });

    testWidgets('このアプリについては専用の画面へ進む', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      // 設定の一覧に出典そのものは出さない。量が多いので画面を分ける。
      expect(find.text('テスト用の出典'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('バージョンと出典'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('バージョンと出典'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'このアプリについて'), findsOneWidget);
    });

    testWidgets('設定からカレンダーに追加できる', (tester) async {
      await pumpRootApp(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('カレンダーに追加'), findsOneWidget);
      // 行全体が押せるので、右端に共有アイコンは置かない。
      // アイコンがあると「そこだけが押せる」ように見えてしまう。
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'カレンダーに追加'),
          matching: find.byIcon(Icons.ios_share),
        ),
        findsNothing,
      );
      // タップしても例外にならない（共有シート自体はテストでは開かない）。
      await tester.tap(find.text('カレンダーに追加'));
      await tester.pumpAndSettle();
    });
  });
}
