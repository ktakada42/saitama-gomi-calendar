import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/settings/settings_page.dart';

import '../support/test_app.dart';

void main() {
  group('初回起動', () {
    testWidgets('地区が未設定なら設定画面から始まる', (tester) async {
      await pumpRootApp(tester, area: null);

      expect(find.text('お住まいの地区を設定'), findsOneWidget);
      // 設定前は本体のタブが出ていないこと。
      expect(find.text('カレンダー'), findsNothing);
    });

    testWidgets('区と曜日を設定するとトップページに進む', (tester) async {
      await pumpRootApp(tester, area: null);

      await tester.tap(find.text('見沼区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('もえるごみが月・木の地区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この設定ではじめる'));
      await tester.pumpAndSettle();

      expect(find.text('見沼区　わたしの地区'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    });

    testWidgets('曜日をひとつも選ばないと先に進めない', (tester) async {
      await pumpRootApp(tester, area: null);

      final button = find.widgetWithText(FilledButton, 'この設定ではじめる');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
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

    testWidgets('地区はあとから変更できる', (tester) async {
      await pumpRootApp(tester);

      // IndexedStack で全タブが組み立て済みなので、AppBar のタイトルと
      // ナビゲーションのラベルが同じ文字列になる。アイコンで指す。
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('お住まいの地区'));
      await tester.pumpAndSettle();

      expect(find.text('地区の設定'), findsOneWidget);

      await tester.tap(find.text('岩槻区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存する'));
      await tester.pumpAndSettle();

      expect(find.text('岩槻区　テスト地区'), findsOneWidget);
    });
  });
}
