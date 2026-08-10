import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/dictionary/collection_boxes_page.dart';

import '../support/test_app.dart';

void main() {
  group('回収ボックス', () {
    testWidgets('設定済みの区の場所を、いちばん上に出す', (tester) async {
      // sampleArea は浦和区。55か所の一覧から自分の区を探させるのは、
      // 地区を知っているアプリのやることではない。
      await pumpApp(tester, const CollectionBoxesPage());
      await tester.pumpAndSettle();

      expect(find.text('浦和区の設置場所'), findsOneWidget);
      expect(find.text('浦和区役所'), findsOneWidget);
      expect(find.text('岸町公民館'), findsOneWidget);
    });

    testWidgets('自分の区は、下の一覧には出さない', (tester) async {
      await pumpApp(tester, const CollectionBoxesPage());
      await tester.pumpAndSettle();

      // 上に出したものを下でも繰り返すと、探しているものが2度出る。
      expect(find.text('ほかの区の設置場所'), findsOneWidget);
      expect(find.text('浦和区'), findsNothing);
    });

    testWidgets('地区を設定していなければ、全区を並べる', (tester) async {
      await pumpApp(tester, const CollectionBoxesPage(), area: null);
      await tester.pumpAndSettle();

      // 区が分からないので、どこかを先に出すことはしない。
      expect(find.textContaining('の設置場所'), findsNothing);
      expect(find.text('設置場所'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('浦和区'), 300);
      expect(find.text('浦和区'), findsOneWidget);
    });

    testWidgets('箱は色で見分けられるようにする', (tester) async {
      await pumpApp(tester, const CollectionBoxesPage());
      await tester.pumpAndSettle();

      // 現地では色が先に目に入る。
      expect(find.text('小型家電回収ボックス'), findsOneWidget);
      expect(find.text('黄色'), findsOneWidget);
      expect(find.text('電池回収ボックス'), findsOneWidget);
      expect(find.text('白色'), findsOneWidget);
    });

    testWidgets('電池の品目から来たら、電池の箱を先に出す', (tester) async {
      await pumpApp(tester, const CollectionBoxesPage(focusedBoxId: 'battery'));
      await tester.pumpAndSettle();

      // どちらも見られる状態は保つ。迷う品目があるため。
      final battery = tester.getTopLeft(find.text('電池回収ボックス')).dy;
      final appliance = tester.getTopLeft(find.text('小型家電回収ボックス')).dy;
      expect(battery, lessThan(appliance));
    });

    testWidgets('小型家電の品目から来たら、小型家電の箱を先に出す', (tester) async {
      await pumpApp(
        tester,
        const CollectionBoxesPage(focusedBoxId: 'smallAppliance'),
      );
      await tester.pumpAndSettle();

      final appliance = tester.getTopLeft(find.text('小型家電回収ボックス')).dy;
      final battery = tester.getTopLeft(find.text('電池回収ボックス')).dy;
      expect(appliance, lessThan(battery));
    });

    testWidgets('入らない大きさのときの行き先も出す', (tester) async {
      await pumpApp(tester, const CollectionBoxesPage());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('入らない大きさのとき'), 400);
      expect(find.textContaining('10kg以下は無料'), findsOneWidget);
    });

    testWidgets('出典を示す', (tester) async {
      await pumpApp(tester, const CollectionBoxesPage());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.textContaining('P12'), 400);
      expect(find.textContaining('P12'), findsOneWidget);
    });
  });
}
