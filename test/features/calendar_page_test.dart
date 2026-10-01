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

  group('プラスチックの分別変更の前後', () {
    testWidgets('変更のあとの資源物1類には、プラスチック資源と出す', (tester) async {
      await pumpApp(
        tester,
        const CalendarPage(),
        today: DateTime(2026, 10, 15),
      );

      // 10月14日（水）は資源物1類。
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();

      expect(find.textContaining('プラスチック資源'), findsWidgets);
      expect(find.textContaining('容器包装プラスチック'), findsNothing);
    });

    testWidgets('変更の前の月まで戻ると、当時の決まりで出す', (tester) async {
      await pumpApp(
        tester,
        const CalendarPage(),
        today: DateTime(2026, 10, 15),
      );
      await tester.tap(find.byTooltip('前の月'));
      await tester.pumpAndSettle();

      // 9月16日（水）は資源物1類。このころはまだ容器包装プラスチックだけを
      // 集めていた。いまの決まりで出すと、当時は出せなかったものを載せる。
      await tester.tap(find.text('16'));
      await tester.pumpAndSettle();

      expect(find.textContaining('容器包装プラスチック'), findsOneWidget);
      expect(find.textContaining('プラスチック資源'), findsNothing);
    });
  });

  testWidgets('収集の無い日は押せない', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // 8月7日は金曜で収集がない。開いても「収集はありません」としか出せず、
    // マスに帯が無いことで既に伝わっている。
    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();

    expect(find.text('収集はありません。'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('年末年始は、収集が無くても押せて理由が読める', (tester) async {
    await pumpApp(tester, const CalendarPage(), today: DateTime(2027, 1, 10));

    // 1月1日は金曜。年末年始でなければ押せないが、いつもの曜日なのに帯が
    // 無い日（1月2日・3日など）もあるので、3日間は理由を読めるようにしておく。
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(find.text('年末年始のため収集はお休みです。'), findsOneWidget);
  });

  testWidgets('短い文だけの日でも、シートは画面の幅いっぱいに出る', (tester) async {
    await pumpApp(tester, const CalendarPage(), today: DateTime(2027, 1, 10));
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    // シートの面（Material）の幅は中身に合わせて縮む。文の幅しかない
    // 細いシートになっていた。外側のBottomSheetは常に画面の幅なので、
    // 面のほうを測る。
    final surface = tester.getSize(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(surface.width, screen.width);
  });

  testWidgets('凡例は出さない。区分名はマスの帯に直接書いてある', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // 色だけで区分を示しているなら、色と名前の対応を示す凡例が要る。
    // このアプリはマスの帯そのものに短縮名を書いているので、
    // 別立ての凡例は同じ対応を重複して示すだけになる。
    for (final label in ['もえるごみ', 'もえないごみ', '有害危険ごみ', '資源物1類', '資源物2類']) {
      expect(find.text(label), findsNothing, reason: label);
    }
    // sampleAreaは8月に5区分すべての収集日を持つので、短縮名がマスに出る。
    for (final label in ['もえる', 'もえない', '有害危険', '資源1', '資源2']) {
      expect(find.text(label), findsWidgets, reason: label);
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
    expect(controller.page, 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('15')),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-17, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 指の動きに追従して、月と月の途中で止まっている。
    // ここで今の月が抜けて隣の月が入ってくるのが見える。
    expect(controller.page, greaterThan(1.0));
    expect(controller.page, lessThan(2.0));

    // 途中で離せば元の月に戻る。
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.page, 1.0);
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
    expect(controller.page, greaterThan(1.0));
    expect(controller.page, lessThan(2.0));

    await tester.pumpAndSettle();
    expect(controller.page, 2.0);
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

  testWidgets('送れるのは前1か月・後3か月まで', (tester) async {
    await pumpApp(tester, const CalendarPage());

    // 表示している収集日は「今の決まり」を先へ延ばしたものでしかない。
    // 市の決まりは変わるので、何年も先まで出せてしまうと当たっている
    // かのように見せてしまう。
    for (final expected in ['2026年9月', '2026年10月', '2026年11月']) {
      await tester.tap(find.byTooltip('次の月'));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    }
    // 3か月先で止まる。押せないボタンにして、効かないのか壊れたのかを
    // 迷わせない。
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('次の月'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    // 前は1か月だけ。払いすぎたときに戻れれば足りる。
    await tester.tap(find.text('今月に戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('前の月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年7月'), findsOneWidget);

    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('前の月'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}
