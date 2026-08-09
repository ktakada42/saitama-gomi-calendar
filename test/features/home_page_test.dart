import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/home/home_page.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('明日が収集日なら区分と日付を大きく出す', (tester) async {
    // 2026年8月9日は日曜。翌10日は月曜でもえるごみの日。
    await pumpApp(tester, const HomePage(), today: DateTime(2026, 8, 9));

    expect(find.text('明日'), findsOneWidget);
    expect(find.text('8月10日(月)'), findsOneWidget);
    expect(find.text('もえるごみ'), findsWidgets);
    expect(find.text('朝8:30までに出す'), findsOneWidget);
  });

  testWidgets('明日に収集が無ければそう書く', (tester) async {
    // 2026年8月6日（木）の翌日は金曜で、この地区は収集がない。
    await pumpApp(tester, const HomePage(), today: DateTime(2026, 8, 6));

    expect(find.text('収集はありません'), findsOneWidget);
  });

  testWidgets('明日に複数の区分が重なればすべて出す', (tester) async {
    // 8月11日は第2火曜。もえないごみと資源物2類が重なる。
    await pumpApp(tester, const HomePage(), today: DateTime(2026, 8, 10));

    expect(find.text('もえないごみ'), findsWidgets);
    expect(find.text('資源物2類'), findsWidgets);
  });

  testWidgets('早朝収集地区なら明日の期限が5:30になる', (tester) async {
    await pumpApp(
      tester,
      const HomePage(),
      area: sampleArea.copyWith(earlyMorning: true),
      today: DateTime(2026, 8, 9),
    );

    expect(find.text('朝5:30までに出す'), findsOneWidget);
  });

  testWidgets('区と地区名をタイトルに出す', (tester) async {
    await pumpApp(tester, const HomePage());

    expect(find.text('浦和区 テスト地区'), findsOneWidget);
  });

  testWidgets('月1回の区分の次回もトップから分かる', (tester) async {
    // 8月12日時点で、もえないごみ（第2火）の次回は9月8日。
    await pumpApp(tester, const HomePage(), today: DateTime(2026, 8, 12));

    expect(find.text('分別ごとの次の収集'), findsOneWidget);
    expect(find.text('9月8日(火)'), findsOneWidget);
  });

  testWidgets('日をタップすると出し方が読める', (tester) async {
    await pumpApp(tester, const HomePage(), today: DateTime(2026, 8, 9));

    await tester.tap(find.text('明日'));
    await tester.pumpAndSettle();

    // カード側は「朝8:30までに出す」なので、この完全一致はシート側だけに当たる。
    expect(find.text('朝8:30まで'), findsOneWidget);
    expect(find.textContaining('中身の見える袋'), findsWidgets);
  });

  testWidgets('収集曜日が未設定なら設定を促す', (tester) async {
    await pumpApp(
      tester,
      const HomePage(),
      area: sampleArea.copyWith(rules: const {}),
    );

    expect(find.textContaining('収集曜日がまだ設定されていません'), findsOneWidget);
  });

  testWidgets('この先の収集では、あさっての次の行に日付を置く', (tester) async {
    // 「あさって 8月11日(火)」は日付の欄に1行では収まらず、成り行きに
    // 任せると「あさって 8月11／日(火)」と日付の途中で切れていた。
    await pumpApp(
      tester,
      const HomePage(),
      today: DateTime(2026, 8, 9),
      viewport: TestViewport.compact,
    );

    expect(find.text('あさって\n8月11日(火)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('出す期限をまたぐと大きく出す日が入れ替わる', () {
    // sampleAreaのもえるごみは月・木。2026年8月6日は木曜。

    testWidgets('収集日の朝、期限前は今日を大きく出す', (tester) async {
      await pumpApp(
        tester,
        const HomePage(),
        today: DateTime(2026, 8, 6),
        now: DateTime(2026, 8, 6, 7, 0),
      );

      // まだ出しに行けるので、今日を大きく出す。
      expect(find.text('今日'), findsOneWidget);
      expect(find.text('8月6日(木)'), findsOneWidget);
      // 大きい方に区分名（見出し）が出る。
      expect(find.text('もえるごみ'), findsWidgets);
      expect(find.text('朝8:30までに出す'), findsOneWidget);
      // 明日は小さい行に回る。
      expect(find.text('明日'), findsOneWidget);
    });

    testWidgets('期限を過ぎたら明日を大きく出す', (tester) async {
      await pumpApp(
        tester,
        const HomePage(),
        today: DateTime(2026, 8, 6),
        now: DateTime(2026, 8, 6, 9, 0),
      );

      // 今日はもう出せないので、明日に切り替える。
      expect(find.text('明日'), findsOneWidget);
      expect(find.text('8月7日(金)'), findsOneWidget);
      expect(find.text('今日'), findsOneWidget);
    });

    testWidgets('早朝収集地区は5:30で切り替わる', (tester) async {
      final early = sampleArea.copyWith(earlyMorning: true);

      // 7時。ふつうの地区ならまだ今日だが、早朝地区は過ぎている。
      await pumpApp(
        tester,
        const HomePage(),
        area: early,
        today: DateTime(2026, 8, 6),
        now: DateTime(2026, 8, 6, 7, 0),
      );
      expect(find.text('8月7日(金)'), findsOneWidget);

      // 5時ならまだ間に合う。
      await pumpApp(
        tester,
        const HomePage(),
        area: early,
        today: DateTime(2026, 8, 6),
        now: DateTime(2026, 8, 6, 5, 0),
      );
      expect(find.text('8月6日(木)'), findsOneWidget);
      expect(find.text('朝5:30までに出す'), findsOneWidget);
    });

    testWidgets('収集のない日の朝は、これまでどおり明日を出す', (tester) async {
      // 8月7日（金）は収集がない。
      await pumpApp(
        tester,
        const HomePage(),
        today: DateTime(2026, 8, 7),
        now: DateTime(2026, 8, 7, 7, 0),
      );

      expect(find.text('明日'), findsOneWidget);
      expect(find.text('8月8日(土)'), findsOneWidget);
    });
  });
}
