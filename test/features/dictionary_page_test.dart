import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/features/dictionary/dictionary_page.dart';
import 'package:saitama_gomi/ui/widgets/category_pill.dart';

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

    // 市の早見表が付けているかなを行にまとめて区切りに使う。
    // 見出しは「か行」、索引は「か」と書き分ける。
    for (final head in ['か', 'た', 'は']) {
      expect(find.text('$head行'), findsOneWidget);
      expect(find.text(head), findsOneWidget);
    }
  });

  group('五十音の索引', () {
    // 行をまたぐように品目を持たせて、索引の動きを見られるようにする。
    final dictionary = WasteDictionary.fromJson({
      'source': 'テスト用の分別早見表',
      'sourceUrl': '',
      'items': [
        for (final kana in ['あ', 'い', 'か', 'き', 'た', 'ち', 'な', 'に'])
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

    /// 右端の索引に並んでいる文字。一覧の見出しと紛れないよう、
    /// 画面の右端にあるものだけを拾う。
    List<String> indexHeads(WidgetTester tester) {
      final width = tester.view.physicalSize.width;
      return tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data != null && t.data!.length == 1)
          .where((t) => tester.getCenter(find.byWidget(t)).dx > width - 40)
          .map((t) => t.data!)
          .toList();
    }

    /// 索引の中で丸が付いている行。現在地はひとつだけのはず。
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

    testWidgets('索引は行だけを並べる', (tester) async {
      await pump(tester);

      // かな1文字ごとに並べると43個になって1つが小さくなりすぎるので、
      // iOSの連絡先と同じく行でまとめる。
      expect(indexHeads(tester), ['あ', 'か', 'た', 'な']);
    });

    testWidgets('一覧の見出しは行で切る', (tester) async {
      await pump(tester);

      // 索引の「あ」と見分けられるよう、見出しには行を付ける。
      expect(find.text('あ行'), findsOneWidget);
      // 「い」で改めて区切らない。あ行の中に続けて並ぶ。
      expect(find.text('い行'), findsNothing);
      expect(find.text('い'), findsNothing);
      expect(find.text('あ0品目'), findsOneWidget);
      expect(find.text('い0品目'), findsOneWidget);
    });

    testWidgets('現在地に丸が付く', (tester) async {
      await pump(tester);

      expect(circled(tester), 'あ');
    });

    testWidgets('最後の行も選べる', (tester) async {
      // わ行のように件数が少ない最後の行は、一番下まで送っても
      // 見出しが画面の上端まで来ない。スクロール位置から現在地を
      // 拾っていると手前の行のままになり、選べなくなってしまう。
      final tail = WasteDictionary.fromJson({
        'source': 'テスト用の分別早見表',
        'sourceUrl': '',
        'items': [
          for (var i = 0; i < 30; i++)
            {
              'name': 'あ$i品目',
              'kanaHead': 'あ',
              'category': 'burnable',
              'categoryLabel': 'もえるごみ',
              'note': '',
            },
          // 最後の行はたった1件。
          {
            'name': '輪ゴム',
            'kanaHead': 'わ',
            'category': 'burnable',
            'categoryLabel': 'もえるごみ',
            'note': '',
          },
        ],
      });
      await pumpApp(tester, const DictionaryPage(), dictionary: tail);

      await tester.tap(find.text('わ').last);
      await tester.pumpAndSettle();

      expect(circled(tester), 'わ');
      expect(find.text('輪ゴム'), findsOneWidget);
    });

    testWidgets('なぞると触れている行へ送り、行が変わるたびに手応えを返す', (tester) async {
      await pump(tester);

      // 時刻のホイールと同じく、送るたびにクリック感を返す。
      // どこまで来たかを画面から目を離さずに掴めるようにする。
      final clicks = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            clicks.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      // 索引の「あ」から「た」まで指を滑らせる。
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('あ').last),
      );
      await gesture.moveTo(tester.getCenter(find.text('か').last));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('た').last));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(circled(tester), 'た');
      expect(find.text('た0品目'), findsOneWidget);
      expect(find.text('あ0品目'), findsNothing);
      // あ→か、か→た と行をまたいだ回数だけ返る。
      // 同じ行をなぞっている間は鳴らさない。
      expect(clicks, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.selectionClick',
      ]);
    });
  });

  testWidgets('絞り込むと五十音の索引を出さない', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 件数が少なくなると行が飛び飛びになって、かえって探しにくいため。
    await tester.enterText(find.byType(TextField), 'ペット');
    await tester.pumpAndSettle();

    // 見出しは残るが、右端の索引は消える。
    expect(find.text('か行'), findsOneWidget);
    expect(find.text('か'), findsNothing);
  });

  testWidgets('出し先のピルは品目名と同じ高さに並ぶ', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // ピルをtrailingに置くと、下段の行数によって上端に揃ったり
    // 上下の中央に寄ったりして、行ごとに高さが食い違っていた。
    for (final name in ['ペットボトル', 'カーペット', 'たんす']) {
      final tile = find.widgetWithText(ListTile, name);
      final title = tester.getRect(find.text(name));
      final pill = tester.getRect(
        find.descendant(of: tile, matching: find.byType(CategoryPill)),
      );
      expect(pill.center.dy, closeTo(title.center.dy, 0.5), reason: name);
    }
  });

  testWidgets('見出しの帯と行は同じ左右の余白に収まる', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 帯は行と同じ幅いっぱいに敷き、その中で左右とも同じだけ空ける。
    // 右だけ広いと、ピルが帯の右端から離れて浮いて見える。
    final band = tester.getRect(find.widgetWithText(Container, 'か行').first);
    final tile = find.widgetWithText(ListTile, 'カーペット');
    final title = tester.getRect(find.text('カーペット'));
    final pill = tester.getRect(
      find.descendant(of: tile, matching: find.byType(CategoryPill)),
    );

    expect(title.left - band.left, closeTo(band.right - pill.right, 0.5));
  });

  group('冊子の印', () {
    final dictionary = WasteDictionary.fromJson({
      'source': 'テスト用の分別早見表',
      'sourceUrl': 'https://example.com/manual',
      'items': [
        {
          'name': 'いす',
          'kanaHead': 'い',
          'category': 'nonBurnable',
          'categoryLabel': 'もえないごみ',
          'note': '',
          'marks': ['star2'],
        },
        {
          'name': 'ペットボトル',
          'kanaHead': 'へ',
          'category': 'recyclable1',
          'categoryLabel': '資源物1類',
          'note': '中をすすいで',
        },
      ],
    });

    testWidgets('印を持つ品目は押すと詳しい出し方が出る', (tester) async {
      await pumpApp(tester, const DictionaryPage(), dictionary: dictionary);

      // 一覧には「★2」ではなく、何が書いてあるかの手がかりを出す。
      expect(find.text('★2'), findsNothing);
      expect(find.text('大きさで出し方が変わる'), findsOneWidget);

      await tester.tap(find.text('いす'));
      await tester.pumpAndSettle();

      // 冊子の脚注を、冊子を持たない人にも通じる言葉で出す。
      expect(find.textContaining('90cm以上2m未満'), findsOneWidget);
      expect(find.text('市の家庭ごみの出し方マニュアル'), findsOneWidget);
    });

    testWidgets('印を持たない品目は押せない', (tester) async {
      await pumpApp(tester, const DictionaryPage(), dictionary: dictionary);

      // 行に出ている文字がすべてなので、押しても出すものがない。
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'ペットボトル'),
      );
      expect(tile.onTap, isNull);
    });
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
