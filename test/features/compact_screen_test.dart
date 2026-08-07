import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/calendar/calendar_page.dart';
import 'package:saitama_gomi/features/dictionary/dictionary_page.dart';
import 'package:saitama_gomi/features/home/home_page.dart';
import 'package:saitama_gomi/features/settings/settings_page.dart';

import '../support/test_app.dart';

/// サポート下限の画面（iPhone SE 第2/第3世代、375×667pt）で崩れないかを確かめる。
///
/// ふだんのテストは[TestViewport.standard]（400×900）で動いていて、SEより
/// 横も縦も広い。狭い画面でだけ起きるレイアウト崩れ（RenderFlex overflow）は
/// そちらでは検知できないので、下限の画面でも一通り開いておく。
///
/// Flutterはオーバーフローすると例外を投げる（デバッグビルド）。
/// `tester.takeException()`がnullでなければ、その画面は下限の端末で崩れている。
void main() {
  group('サポート下限の画面（iPhone SE）', () {
    testWidgets('ホームが崩れない', (tester) async {
      await pumpApp(tester, const HomePage(), viewport: TestViewport.compact);
      expect(tester.takeException(), isNull);
    });

    testWidgets('カレンダーが崩れない', (tester) async {
      await pumpApp(
        tester,
        const CalendarPage(),
        viewport: TestViewport.compact,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('分別が崩れない', (tester) async {
      await pumpApp(
        tester,
        const DictionaryPage(),
        viewport: TestViewport.compact,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('設定が崩れない', (tester) async {
      await pumpApp(
        tester,
        const SettingsPage(),
        viewport: TestViewport.compact,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('初回設定（地区選択）が崩れない', (tester) async {
      await pumpRootApp(tester, area: null, viewport: TestViewport.compact);
      expect(tester.takeException(), isNull);

      // 区を選ぶと地区の一覧が出る。狭い画面だとここが溢れやすい。
      await tester.tap(find.text('大宮区'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('曜日の手入力画面が崩れない', (tester) async {
      await pumpRootApp(tester, area: null, viewport: TestViewport.compact);

      await tester.tap(find.text('自分の地区が見つからない'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 曜日のトグルは7つ横に並ぶ。375px幅で溢れないことを確かめる。
      expect(find.text('月'), findsWidgets);
      expect(find.text('日'), findsWidgets);
    });

    testWidgets('日別詳細シートが崩れない', (tester) async {
      await pumpApp(tester, const HomePage(), viewport: TestViewport.compact);

      await tester.tap(find.text('明日'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('カレンダーの日をタップしても崩れない', (tester) async {
      await pumpApp(
        tester,
        const CalendarPage(),
        viewport: TestViewport.compact,
      );

      // 8月11日は複数区分が重なる日。セルに区分帯が2本入る。
      await tester.tap(find.text('11'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('5区分が重なる日でもカレンダーが溢れず、シートを閉じられる', (tester) async {
    await pumpApp(
      tester,
      const CalendarPage(),
      area: manyCategoryArea,
      viewport: TestViewport.compact,
    );
    // マスは3段まで。帯を3本出したうえで「+2」を足すと4段になって溢れる。
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('11').first);
    await tester.pumpAndSettle();

    // シートが画面いっぱいに広がると、外を押しても、つまみを掴んでも
    // 閉じられなくなる。上に余白を残す。
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.top, greaterThan(0));
    expect(tester.takeException(), isNull);

    // 余白を押して閉じられる。
    await tester.tapAt(Offset(sheet.center.dx, sheet.top / 2));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
}
