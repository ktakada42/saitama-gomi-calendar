import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/dictionary/oversized_guide_page.dart';

import '../support/test_app.dart';

void main() {
  group('粗大ごみの出し方', () {
    testWidgets('まず大きさの目安を出す', (tester) async {
      await pumpApp(tester, const OversizedGuidePage());
      await tester.pumpAndSettle();

      // 知りたい順は、自分のものが粗大ごみに当たるか→いくらか→どう申し込むか。
      expect(find.text('最大の一辺又は直径が90cm以上2m未満のごみ'), findsOneWidget);
    });

    testWidgets('2m以上は市では扱えないことも書く', (tester) async {
      await pumpApp(tester, const OversizedGuidePage());
      await tester.pumpAndSettle();

      // 大きいほど粗大ごみだと思われがちなので、上限を必ず見せる。
      expect(find.textContaining('2m以上'), findsWidgets);
    });

    testWidgets('2つの方法を、料金つきで並べる', (tester) async {
      await pumpApp(tester, const OversizedGuidePage());
      await tester.pumpAndSettle();

      expect(find.text('10kgごとに180円'), findsOneWidget);
      expect(find.text('1品 550円'), findsOneWidget);
    });

    testWidgets('申込み先の電話番号を出す', (tester) async {
      await pumpApp(tester, const OversizedGuidePage());
      await tester.pumpAndSettle();

      // 番号を覚えて電話アプリに打ち直させないため、押せる形で置く。
      expect(find.text('050-3033-8229'), findsOneWidget);
      expect(find.text('048-878-0053'), findsOneWidget);
    });

    testWidgets('品目から来たときは、その品目の料金を先に出す', (tester) async {
      await pumpApp(
        tester,
        const OversizedGuidePage(highlightedItem: 'マットレス（スプリングあり）'),
      );
      await tester.pumpAndSettle();

      // 一般の料金を読ませてから訂正するより、先に出す。
      expect(find.text('この品目の料金'), findsOneWidget);
      expect(find.text('2,200円'), findsWidgets);
    });

    testWidgets('個別料金が無い品目では、その欄を出さない', (tester) async {
      await pumpApp(tester, const OversizedGuidePage(highlightedItem: 'たんす'));
      await tester.pumpAndSettle();

      // 大きさで決まるものに個別料金の欄を出すと、額を取り違える。
      expect(find.text('この品目の料金'), findsNothing);
    });

    testWidgets('似た名前の別物には、料金を出さない', (tester) async {
      // 「自転車のタイヤ・チューブ」はもえるごみ。名前で照合していると、
      // ここに粗大ごみのタイヤ550円が出てしまう。
      await pumpApp(
        tester,
        const OversizedGuidePage(highlightedItem: '自転車のタイヤ・チューブ（ゴム製）'),
      );
      await tester.pumpAndSettle();

      expect(find.text('この品目の料金'), findsNothing);
    });

    testWidgets('注意書きは畳んでおき、開くと読める', (tester) async {
      await pumpApp(tester, const OversizedGuidePage());
      await tester.pumpAndSettle();

      expect(find.textContaining('当日の予約はできません'), findsNothing);

      await tester.tap(find.textContaining('注意すること').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('当日の予約はできません'), findsOneWidget);
    });

    testWidgets('出典を示す', (tester) async {
      await pumpApp(tester, const OversizedGuidePage());
      await tester.pumpAndSettle();

      // 金額は市の資料の記載であって、こちらの計算ではない。
      await tester.scrollUntilVisible(find.textContaining('P9'), 400);
      expect(find.textContaining('P9'), findsOneWidget);
    });
  });
}
