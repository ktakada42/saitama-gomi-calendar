import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/features/dictionary/dictionary_page.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('最初は全品目が並ぶ', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    expect(find.text('ペットボトル'), findsOneWidget);
    expect(find.text('カーペット'), findsOneWidget);
    expect(find.text('たんす'), findsOneWidget);
  });

  testWidgets('品目名で絞り込める', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    await tester.enterText(find.byType(TextField), 'ペット');
    await tester.pumpAndSettle();

    expect(find.text('ペットボトル'), findsOneWidget);
    // 「カーペット」も「ペット」を含むので残る。
    expect(find.text('カーペット'), findsOneWidget);
    // 含まないものは消える。
    expect(find.text('たんす'), findsNothing);
  });

  testWidgets('出し先と注意点を表示する', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 出し先はピルに収まる短い名前で出す（'資源物1類'→'資源1'）。
    expect(find.text('資源1'), findsOneWidget);
    expect(find.text('中をすすいで'), findsOneWidget);
  });

  testWidgets('収集日を持たない出し先も出す', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 粗大ごみは5区分に入らないが、利用者が知りたいのはむしろここ。
    // 12文字ある正式名はピルに収まらないので、短縮名で出す。
    expect(find.text('たんす'), findsOneWidget);
    expect(find.text('粗大'), findsOneWidget);
  });

  testWidgets('該当が無ければその旨を伝える', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    await tester.enterText(find.byType(TextField), 'あるはずのない品目');
    await tester.pumpAndSettle();

    expect(find.textContaining('一覧にありません'), findsOneWidget);
  });

  testWidgets('入力を消せる', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    await tester.enterText(find.byType(TextField), 'ペット');
    await tester.pumpAndSettle();
    expect(find.text('たんす'), findsNothing);

    await tester.tap(find.byTooltip('入力を消す'));
    await tester.pumpAndSettle();

    expect(find.text('たんす'), findsOneWidget);
  });

  testWidgets('五十音の見出しと索引が出る', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 市の早見表が付けているかな行を、そのまま区切りに使う。
    // 一覧の見出しと右端の索引の両方に出るので、2つずつ見つかる。
    expect(find.text('か'), findsNWidgets(2));
    expect(find.text('た'), findsNWidgets(2));
    expect(find.text('へ'), findsNWidgets(2));
  });

  group('五十音の索引', () {
    // 行ごとに複数のかなを持たせて、開閉の様子を見られるようにする。
    final dictionary = WasteDictionary.fromJson({
      'source': 'テスト用の分別早見表',
      'sourceUrl': '',
      'items': [
        for (final kana in ['あ', 'い', 'う', 'か', 'き', 'た', 'ち'])
          for (var i = 0; i < 6; i++)
            {
              'name': '$kana$i品目',
              'kanaHead': kana,
              'category': 'burnable',
              'categoryLabel': 'もえるごみ',
              'note': '',
            },
      ],
    });

    Future<void> pump(WidgetTester tester) =>
        pumpApp(tester, const DictionaryPage(), dictionary: dictionary);

    /// 右端の索引に並んでいるかな。一覧の見出しと紛れないよう、
    /// 画面の右端にあるものだけを拾う。
    List<String> indexKana(WidgetTester tester) {
      final width = tester.view.physicalSize.width;
      return tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data != null && t.data!.length == 1)
          .where((t) => tester.getCenter(find.byWidget(t)).dx > width - 40)
          .map((t) => t.data!)
          .toList();
    }

    /// 索引の中で丸が付いているかな。現在地はひとつだけのはず。
    String? circled(WidgetTester tester) {
      final circles = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
      if (circles.evaluate().length != 1) return null;
      return tester
          .widget<Text>(
            find.descendant(of: circles, matching: find.byType(Text)),
          )
          .data;
    }

    testWidgets('ふだんは行頭だけを出し、今いる行だけ開く', (tester) async {
      await pump(tester);

      // 43文字を一度に並べると1文字が小さくなりすぎて押し間違えるため、
      // ふだんは行頭だけを出す。先頭にいるのであ行だけが開く。
      expect(indexKana(tester), ['あ', 'い', 'う', 'か', 'た']);
    });

    testWidgets('現在地に丸が付く', (tester) async {
      await pump(tester);

      expect(circled(tester), 'あ');
    });

    testWidgets('行を押すと開くだけで、飛びはしない', (tester) async {
      await pump(tester);

      // 索引側の「か」を押す。一覧の見出しではなく索引を押したいので、
      // 画面の右端にある方を選ぶ。
      await tester.tap(find.text('か').last);
      await tester.pumpAndSettle();

      // か行が開き、あ行は閉じる。
      expect(indexKana(tester), ['あ', 'か', 'き', 'た']);
      // まだ飛んでいないので、先頭のあ行が見えたまま。
      expect(find.text('あ0品目'), findsOneWidget);
      expect(circled(tester), 'あ');
    });

    testWidgets('開いた行のかなを押すとそこへ飛ぶ', (tester) async {
      await pump(tester);

      await tester.tap(find.text('か').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('き').last);
      await tester.pumpAndSettle();

      // 「き」まで飛ぶので、先頭のあ行は画面から外れる。
      expect(find.text('き0品目'), findsOneWidget);
      expect(find.text('あ0品目'), findsNothing);
      // 飛んだ先が現在地になり、その行が開いたままになる。
      expect(circled(tester), 'き');
      expect(indexKana(tester), ['あ', 'か', 'き', 'た']);
    });
  });

  testWidgets('絞り込むと五十音の索引を出さない', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 件数が少なくなると行が飛び飛びになって、かえって探しにくいため。
    await tester.enterText(find.byType(TextField), 'ペット');
    await tester.pumpAndSettle();

    // 見出しは残るが、右端の索引は消えるので1つだけになる。
    expect(find.text('か'), findsOneWidget);
  });

  testWidgets('出典はヘッダから開いたときだけ出す', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 品目を探している間はずっと見えている必要がないので、出しっぱなしにしない。
    expect(find.textContaining('テスト用の分別早見表'), findsNothing);

    await tester.tap(find.byTooltip('出典'));
    await tester.pumpAndSettle();
    expect(find.textContaining('テスト用の分別早見表'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.textContaining('テスト用の分別早見表'), findsNothing);
  });
}
