import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

/// 同梱している分別早見表そのものを読み、内容が壊れていないかを確かめる。
///
/// 生成スクリプト（scripts/extract_waste_dictionary.py）はPDFのレイアウトに
/// 依存しているので、マニュアルが改版されて抽出が崩れたときに気づけるように
/// しておく。テスト用の作り物ではなく本物のアセットを読む。
WasteDictionary _loadBundled() {
  final raw = File('assets/data/dictionary.json').readAsStringSync();
  final kana = File('assets/data/dictionary_kana.json').readAsStringSync();
  return WasteDictionary.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
    kana: jsonDecode(kana) as Map<String, dynamic>,
  );
}

void main() {
  final dictionary = _loadBundled();

  test('十分な件数の品目が入っている', () {
    // 早見表はおよそ440品目。極端に減っていたら抽出が壊れている。
    expect(dictionary.items.length, greaterThan(300));
  });

  test('出典が入っている', () {
    expect(dictionary.source, isNotEmpty);
    expect(dictionary.sourceUrl, startsWith('https://'));
  });

  test('読みの五十音順に並んでいる', () {
    // 品目名で並べ直すとUnicodeのコードポイント順になり、「アイロン」の次に
    // 「アルバム」、その後ろに「油」と、読みと無関係な並びになる。
    expect(
      dictionary.items
          .where((item) => item.kanaHead == 'あ')
          .map((item) => item.name),
      ['アイロン', '足拭きマット', '油（食用油）', '雨衣（カッパ）', '網戸', 'アルバム（写真用）', 'アルミ箔'],
    );
  });

  test('全件に読みがある', () {
    // 名前がかなだけの品目は名前から起こす。漢字や英字を含む品目は
    // dictionary_kana.json に読みが要る。市が資料を更新して品目が増えたとき、
    // 読みを足し忘れるとその品目だけ行の中で違う場所に出る。
    final unreadable = RegExp(r'[^ぁ-んー]');
    for (final item in dictionary.items) {
      expect(
        unreadable.hasMatch(item.sortKana),
        isFalse,
        reason: '${item.name} の読みが無い（${item.sortKana}）',
      );
    }
  });

  test('資料の並びと食い違うのは、資料の側が五十音から外れている2件だけ', () {
    // 早見表そのものが市の付けた読みの五十音順なので、読みを1つでも
    // 書き間違えると並びが資料とずれる。資料の側が外れているのは
    // 「炭酸ボンベ」（た行の最後に置かれている）と、
    // 「パソコン本体／パソコンディスプレイ」（本体を先に置いている）の2箇所。
    final booklet = [
      for (final item in jsonDecode(
            File('assets/data/dictionary.json').readAsStringSync(),
          )['items']
          as List)
        (item as Map<String, dynamic>)['name'] as String,
    ];
    final sorted = dictionary.items.map((item) => item.name).toList();
    final moved = [
      for (var i = 0; i < booklet.length; i++)
        if (booklet[i] != sorted[i]) booklet[i],
    ];
    expect(moved, ['たんす', 'ダンベル', '段ボール', '炭酸ボンベ', 'パソコン本体（ノート型も）', 'パソコンディスプレイ']);
  });

  test('欄に収まらない品目名も落ちていない', () {
    // 市は欄に収まらない品目名を本文より小さい字で組み、2行に折り返す。
    // 「プラマーク付き」バッジを字の大きさだけで落とすと、これも消える。
    final names = dictionary.items.map((item) => item.name).toSet();
    expect(names, contains('カセットボンベ（カートリッジ式ボンベ）'));
    expect(names, contains('マーガリン・バターの容器（プラスチック製）'));
  });

  test('かな行の見出しが飛んでいない', () {
    // 「ほ」の見出しは品目名とくっついてPDFに入っている（「ほ（車の）ホイール」）。
    // 分けそこねると見出しごと消え、「ほ」以降が「へ」に流れ込んで、
    // 麻雀牌やマウスまでは行に並ぶ。
    final headOf = {
      for (final item in dictionary.items) item.name: item.kanaHead,
    };
    expect(headOf['（車の）ホイール'], 'ほ');
    expect(headOf['ボンベ'], 'ほ');
    expect(headOf['麻雀牌'], 'ま');
  });

  test('品目名と出し先が空でない', () {
    for (final item in dictionary.items) {
      expect(item.name, isNotEmpty);
      expect(item.categoryId, isNotEmpty);
      expect(item.categoryLabel, isNotEmpty);
    }
  });

  test('品目名に抽出漏れの記号が混ざっていない', () {
    for (final item in dictionary.items) {
      // PDFのフォント埋め込み漏れで出る (cid:1234) が残っていないこと。
      expect(item.name, isNot(contains('(cid:')));
      // バッジの小さな文字（「マーク付き」）が混ざると読めない名前になる。
      expect(item.name, isNot(contains('マ付')));
      expect(item.name, isNot(contains('ーきク')));
    }
  });

  test('5区分の品目はGarbageCategoryに解決できる', () {
    final fiveCategories = dictionary.items.where(
      (item) => GarbageCategory.fromId(item.categoryId) != null,
    );
    // 早見表の大半は5区分に入る。
    expect(fiveCategories.length, greaterThan(200));
    for (final item in fiveCategories) {
      expect(item.category, isNotNull);
    }
  });

  test('収集日を持たない出し先も保持している', () {
    // 粗大ごみ・小型家電・電池・収集できないものは5区分に入らないが、
    // 利用者が知りたいのはむしろそこなので落とさずに持つ。
    final others = dictionary.items
        .where((item) => item.category == null)
        .map((item) => item.categoryId)
        .toSet();
    expect(others, contains('oversized'));
    expect(others, contains('smallAppliance'));
    expect(others, contains('notAccepted'));
  });

  group('検索', () {
    test('品目名で引ける', () {
      final results = dictionary.search('ペットボトル');
      expect(results, isNotEmpty);
      expect(results.first.name, contains('ペットボトル'));
    });

    test('前方一致を先に出す', () {
      // 「ペット」は「ペットボトル」のように前方一致する品目と、
      // 「カーペット」のように途中に含むだけの品目の両方がある。
      final results = dictionary.search('ペット');
      expect(results.length, greaterThan(1));
      // searchKey はカタカナをひらがなに寄せてある（「生ゴミ」と「生ごみ」を
      // 同じものとして扱うため）ので、比較は表示名で行う。
      expect(
        results.first.name.startsWith('ペット'),
        isTrue,
        reason: '前方一致（${results.first.name}）が先に来るべき',
      );
      // 途中に含むだけのものも結果には入る。
      expect(results.any((item) => !item.name.startsWith('ペット')), isTrue);
    });

    test('記号や中黒を無視して引ける', () {
      // 「牛乳パック」は早見表では「牛乳等の紙パック」のような表記。
      // 記号を落として比較しているので、括弧付きの品目も引ける。
      final results = dictionary.search('プラスチック');
      expect(results, isNotEmpty);
    });

    test('空文字なら全件返す', () {
      expect(dictionary.search('').length, dictionary.items.length);
      expect(dictionary.search('   ').length, dictionary.items.length);
    });

    test('該当が無ければ空を返す', () {
      expect(dictionary.search('この品目は存在しないはず'), isEmpty);
    });

    test('出し先の名前でも引ける', () {
      final results = dictionary.search('粗大');
      expect(results, isNotEmpty);
      expect(
        results.every((item) => item.categoryLabel.contains('粗大')),
        isTrue,
      );
    });
  });
}
