import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('絞り込むと五十音の索引を出さない', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 件数が少なくなると行が飛び飛びになって、かえって探しにくいため。
    await tester.enterText(find.byType(TextField), 'ペット');
    await tester.pumpAndSettle();

    // 見出しは残るが、右端の索引は消えるので1つだけになる。
    expect(find.text('か'), findsOneWidget);
  });

  testWidgets('出典を表示する', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    expect(find.textContaining('テスト用の分別早見表'), findsOneWidget);
  });
}
