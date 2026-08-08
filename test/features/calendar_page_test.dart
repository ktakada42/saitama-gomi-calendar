import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/calendar/calendar_page.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('起動時は今月を表示する', (tester) async {
    await pumpApp(tester, const CalendarPage());

    expect(find.text('2026年8月'), findsOneWidget);
    // 8月は31日まで。末日のセルがあること。
    expect(find.text('31'), findsOneWidget);
  });

  testWidgets('収集のある日には区分の帯が出る', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // もえるごみは月・木の週2回。8月は月曜5回・木曜4回で9日ある。
    expect(find.text('もえる'), findsNWidgets(9));
    // もえないごみは第2火曜だけなので1日。
    expect(find.text('もえない'), findsOneWidget);
  });

  testWidgets('月を送れる', (tester) async {
    await pumpApp(tester, const CalendarPage());

    await tester.tap(find.byTooltip('次の月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年9月'), findsOneWidget);

    // 今月に戻るボタンは今月を見ているときは出ない。
    await tester.tap(find.text('今月に戻る'));
    await tester.pumpAndSettle();
    expect(find.text('2026年8月'), findsOneWidget);
    expect(find.text('今月に戻る'), findsNothing);
  });

  testWidgets('年月は今月に戻るボタンの有無によらず中央に来る', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // 「今月に戻る」を月送りと同じ行に混ぜていたときは、ボタンが出た分だけ
    // 年月が中央から左へずれていた。別のボタンにしたので動かない。
    final width = tester.view.physicalSize.width;
    expect(tester.getCenter(find.text('2026年8月')).dx, closeTo(width / 2, 0.5));

    await tester.tap(find.byTooltip('次の月'));
    await tester.pumpAndSettle();

    expect(find.text('今月に戻る'), findsOneWidget);
    expect(tester.getCenter(find.text('2026年9月')).dx, closeTo(width / 2, 0.5));
  });

  testWidgets('前の月にも戻れる', (tester) async {
    await pumpApp(tester, const CalendarPage());

    await tester.tap(find.byTooltip('前の月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年7月'), findsOneWidget);
  });

  testWidgets('日をタップすると出し方が読める', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // 8月11日（第2火）はもえないごみと資源物2類。
    await tester.tap(find.text('11'));
    await tester.pumpAndSettle();

    expect(find.text('8月11日(火)'), findsOneWidget);
    expect(find.textContaining('陶磁器'), findsOneWidget);
    expect(find.textContaining('ダンボール'), findsOneWidget);
  });

  testWidgets('収集の無い日をタップしたらそう伝える', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // 8月7日は金曜で収集がない。
    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();

    expect(find.text('収集はありません。'), findsOneWidget);
  });

  testWidgets('凡例に5区分すべて並ぶ', (tester) async {
    await pumpApp(tester, const CalendarPage());

    for (final label in ['もえるごみ', 'もえないごみ', '有害危険ごみ', '資源物1類', '資源物2類']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('カレンダーを左右になぞって月を送れる', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // 左へ払うと次の月。紙をめくる向きに合わせる。
    await tester.fling(find.text('15'), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('2026年9月'), findsOneWidget);

    // 右へ払うと前の月。
    await tester.fling(find.text('15'), const Offset(200, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('2026年8月'), findsOneWidget);
  });

  testWidgets('なぞっている間は今の月と隣の月が並んで見える', (tester) async {
    await pumpApp(tester, const CalendarPage());

    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    expect(controller.page, 1200.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('15')),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-17, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 指の動きに追従して、月と月の途中で止まっている。
    // ここで今の月が抜けて隣の月が入ってくるのが見える。
    expect(controller.page, greaterThan(1200.0));
    expect(controller.page, lessThan(1201.0));

    // 途中で離せば元の月に戻る。
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.page, 1200.0);
    expect(find.text('2026年8月'), findsOneWidget);
  });

  testWidgets('ボタンで送るときも同じように動かす', (tester) async {
    await pumpApp(tester, const CalendarPage());

    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;

    await tester.tap(find.byTooltip('次の月'));
    await tester.pump();
    // 押した直後はまだ動いている途中。
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.page, greaterThan(1200.0));
    expect(controller.page, lessThan(1201.0));

    await tester.pumpAndSettle();
    expect(controller.page, 1201.0);
    expect(find.text('2026年9月'), findsOneWidget);
  });

  testWidgets('わずかに指がずれただけでは月を送らない', (tester) async {
    await pumpApp(tester, const CalendarPage());

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('15')),
    );
    await gesture.moveBy(const Offset(-12, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('2026年8月'), findsOneWidget);
  });
}
