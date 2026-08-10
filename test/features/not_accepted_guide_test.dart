import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/dictionary/not_accepted_guide_page.dart';

import '../support/test_app.dart';

void main() {
  group('市では収集できないもの', () {
    testWidgets('品目から来たときは、その行き先だけを出す', (tester) async {
      await pumpApp(tester, const NotAcceptedGuidePage(focusedItem: 'エアコン'));
      await tester.pumpAndSettle();

      // 全部を読ませて自分で探させると、行き先を取り違える。
      expect(find.textContaining('「エアコン」は市では収集・処理できません'), findsOneWidget);
      expect(find.text('家電リサイクル法の対象品目'), findsOneWidget);
      expect(find.text('0120-319640'), findsOneWidget);
    });

    testWidgets('品目から来ても、ほかの行き先を確かめられる', (tester) async {
      await pumpApp(tester, const NotAcceptedGuidePage(focusedItem: 'エアコン'));
      await tester.pumpAndSettle();

      // 「これで合っているのか」を確かめたくなることがある。
      expect(find.text('ほかの持って行き先'), findsOneWidget);
      expect(find.text('パソコン'), findsOneWidget);
    });

    testWidgets('品目を指定しなければ、全部の行き先を並べる', (tester) async {
      await pumpApp(tester, const NotAcceptedGuidePage());
      await tester.pumpAndSettle();

      expect(find.text('家電リサイクル法の対象品目'), findsOneWidget);
      expect(find.text('ほかの持って行き先'), findsNothing);

      // 一覧なので、下の行き先までたどれる。
      await tester.scrollUntilVisible(find.text('オートバイ・原付'), 400);
      expect(find.text('オートバイ・原付'), findsOneWidget);
    });

    testWidgets('危ないものは、なぜ駄目かまで書く', (tester) async {
      await pumpApp(
        tester,
        const NotAcceptedGuidePage(focusedItem: 'プロパンガスボンベ'),
      );
      await tester.pumpAndSettle();

      // 「出せません」だけだと、こっそり出す人が出る。
      expect(find.textContaining('人命に関わる重大事故'), findsWidgets);
    });

    testWidgets('注射針は医療機関へ返すと伝える', (tester) async {
      await pumpApp(tester, const NotAcceptedGuidePage(focusedItem: '注射針'));
      await tester.pumpAndSettle();

      expect(find.textContaining('処方を行った医療機関等'), findsOneWidget);
    });

    testWidgets('行き先が決まっていない品目でも、画面は開ける', (tester) async {
      // 早見表に無い名前を渡されても落ちない。
      await pumpApp(
        tester,
        const NotAcceptedGuidePage(focusedItem: 'そんな品目はない'),
      );
      await tester.pumpAndSettle();

      expect(find.text('家電リサイクル法の対象品目'), findsOneWidget);
    });

    testWidgets('出典を示す', (tester) async {
      await pumpApp(tester, const NotAcceptedGuidePage());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.textContaining('P10'), 400);
      expect(find.textContaining('P10'), findsOneWidget);
    });
  });
}
