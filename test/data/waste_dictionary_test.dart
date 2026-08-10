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
  return WasteDictionary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
