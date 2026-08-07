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

    expect(find.text('資源物1類'), findsOneWidget);
    expect(find.text('中をすすいで'), findsOneWidget);
  });

  testWidgets('収集日を持たない出し先も出す', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    // 粗大ごみは5区分に入らないが、利用者が知りたいのはむしろここ。
    expect(find.text('たんす'), findsOneWidget);
    expect(find.text('粗大ごみ・適正処理困難物'), findsOneWidget);
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

  testWidgets('出典を表示する', (tester) async {
    await pumpApp(tester, const DictionaryPage());

    expect(find.textContaining('テスト用の分別早見表'), findsOneWidget);
  });
}
