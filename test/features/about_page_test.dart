import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/about/about_page.dart';

import '../support/test_app.dart';

void main() {
  group('このアプリについて', () {
    testWidgets('バージョンを出す', (tester) async {
      await pumpApp(tester, const AboutPage());

      // pubspec.yamlの値を焼き込むのではなく、入っているパッケージから読む。
      expect(find.text('1.2.3 (45)'), findsOneWidget);
    });

    testWidgets('収集日と分別早見表の出典をそれぞれ出す', (tester) async {
      await pumpApp(tester, const AboutPage());

      // 別々の資料から取っているので、片方だけを出典として見せない。
      expect(find.text('テスト用の出典'), findsOneWidget);
      expect(find.text('テスト用の分別早見表'), findsOneWidget);
      // どう機械処理したか（disclaimer）は利用者の判断の役に立たないので出さない。
      expect(find.text('テスト用の但し書き'), findsNothing);
    });

    testWidgets('プライバシーポリシーと市の公式ページへ出られる', (tester) async {
      await pumpApp(tester, const AboutPage());

      for (final title in ['プライバシーポリシー', 'さいたま市の公式ページ']) {
        // アプリの外へ出ることを右端のアイコンで示す。
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, title),
            matching: find.byIcon(Icons.open_in_new),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('ライセンス一覧を開ける', (tester) async {
      await pumpApp(tester, const AboutPage());

      await tester.tap(find.text('ライセンス'));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('さいたまごみカレンダー'), findsOneWidget);
      expect(find.text('1.2.3 (45)'), findsOneWidget);
    });
  });
}
