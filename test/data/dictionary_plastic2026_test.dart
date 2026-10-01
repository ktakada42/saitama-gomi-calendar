import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/domain/waste_item.dart';

/// 令和8年10月のプラスチックの分別変更の検査。
///
/// 早見表（dictionary.json）は4月に配られた時点の区分のままで、市が後から
/// リーフレットと告知ページで名指しした品目だけを、別のファイルから
/// 上書き・追加している。
void main() {
  late Map<String, dynamic> base;
  late Map<String, dynamic> extra;
  late Map<String, dynamic> changes;
  late WasteDictionary merged;

  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  List<Map<String, dynamic>> listOf(Map<String, dynamic> json, String key) => [
    for (final entry in json[key] as List) entry as Map<String, dynamic>,
  ];

  setUpAll(() {
    base = read('assets/data/dictionary.json');
    extra = read('assets/data/dictionary_extra.json');
    changes = read('assets/data/dictionary_plastic2026.json');
    merged = WasteDictionary.fromJson(
      base,
      extra: extra,
      changes: changes,
      kana: read('assets/data/dictionary_kana.json'),
    );
  });

  WasteItem item(String name) => merged.items.firstWhere((i) => i.name == name);

  group('早見表の赤い枠', () {
    test('市が枠で囲んだ品目を拾えている', () {
      // 早見表の上に「□で囲まれているもので、全てプラスチック製で最長の辺が
      // 30㎝未満のものは、令和8年10月からプラスチック資源として回収します」
      // とある。枠は文字ではなく線なので、抽出が崩れると黙って0件になる。
      final boxed = [
        for (final entry in listOf(base, 'items'))
          if ((entry['marks'] as List).contains('box')) entry['name'],
      ];
      expect(boxed, hasLength(23));
      expect(
        boxed,
        containsAll(['歯ブラシ', 'ストロー', 'タッパー', '洗面器', 'おもちゃ', 'バケツ']),
      );
    });

    test('枠の品目は、行にその条件が出る', () {
      // 一覧の行には先頭の印だけが出る。★4（30cm以上はもえないごみ）より
      // 前に置かないと、資源物1類に出せることが行から読めない。
      for (final name in ['プランター', '植木鉢（植木ポット・プラスチック製）']) {
        expect(item(name).markIds.first, 'box', reason: name);
      }
      expect(item('バケツ').marks.first.title, contains('資源物1類'));
    });

    test('枠の品目でも、早見表の区分は書き換えない', () {
      // 材質や大きさを品物ごとに見ないと決まらない。プラスチックでない
      // おもちゃはもえるごみのままで、30cm以上のバケツはもえないごみ。
      expect(item('おもちゃ').categoryId, 'burnable');
      expect(item('バケツ').categoryId, 'nonBurnable');
    });
  });

  group('名指しされた品目の上書き', () {
    test('上書きする品目は、すべて早見表か補いに実在する', () {
      // マニュアルが改訂されて品目名が変わると、上書きは黙って効かなくなる。
      final names = {
        for (final source in [base, extra])
          for (final entry in listOf(source, 'items')) entry['name'],
      };
      for (final override in listOf(changes, 'overrides')) {
        expect(
          names,
          contains(override['name']),
          reason: '${override['name']}',
        );
      }
    });

    test('どの上書きにも、市の資料のどこにあるかが書いてある', () {
      // 条件から推測した品目を混ぜない。どこから取ったか分からなくなると、
      // 市の資料が変わったときに突き合わせられない。
      for (final entry in [
        ...listOf(changes, 'overrides'),
        ...listOf(changes, 'items'),
      ]) {
        expect(entry['from'], isNotEmpty, reason: '${entry['name']}');
      }
    });

    test('歯ブラシ・ストローは資源物1類になった', () {
      for (final name in [
        '歯ブラシ',
        'ストロー',
        'スプーン（プラスチック製）',
        'フォーク（プラスチック製）',
        '定規',
      ]) {
        expect(item(name).categoryId, 'recyclable1', reason: name);
        expect(item(name).categoryLabel, '資源物1類', reason: name);
      }
    });

    test('区分だけを上書きした品目は、早見表の注意点と印が残る', () {
      final toothbrush = item('歯ブラシ');
      expect(toothbrush.note, '電動歯ブラシは電池を抜いて、回収ボックスへ');
      expect(toothbrush.markIds, ['box']);
      expect(item('ストロー').note, '金属製は、もえないごみ');
    });

    test('注意点だけを上書きした品目は、早見表の区分が残る', () {
      // 木のまな板はもえるごみのまま。プラスチック製の出し先だけが変わった。
      final board = item('まな板');
      expect(board.categoryId, 'burnable');
      expect(board.note, contains('もえないごみ'));
      // 「30cm以上はもえるごみ」のままでは、変更後の決まりと食い違う。
      expect(item('発泡スチロール（30cm未満のもの）').note, contains('30cm以上はもえないごみ'));
    });
  });

  group('足した品目', () {
    test('早見表・補いと同じ名前を足していない', () {
      final names = {
        for (final source in [base, extra])
          for (final entry in listOf(source, 'items')) entry['name'],
      };
      final added = [for (final e in listOf(changes, 'items')) e['name']];
      for (final name in added) {
        expect(names, isNot(contains(name)), reason: '$name');
      }
      expect(added.toSet(), hasLength(added.length));
    });

    test('区分は早見表が使っているものだけ', () {
      final known = {
        for (final entry in listOf(base, 'items')) entry['category'],
      };
      for (final entry in [
        ...listOf(changes, 'items'),
        ...listOf(changes, 'overrides').where((o) => o['category'] != null),
      ]) {
        expect(known, contains(entry['category']), reason: '${entry['name']}');
      }
    });

    test('早見表・補い・足した品目がすべて入る', () {
      expect(
        merged.items,
        hasLength(
          listOf(base, 'items').length +
              listOf(extra, 'items').length +
              listOf(changes, 'items').length,
        ),
      );
    });

    test('リーフレットにしか無い品目を引ける', () {
      expect(item('クリアファイル').categoryId, 'recyclable1');
      expect(item('CDケース').categoryId, 'recyclable1');
      // 中のCDは金属を含むので、ケースと出し先が違う。
      expect(item('CD').categoryId, 'burnable');
    });

    test('読みの五十音順に入る', () {
      final names = merged.items.map((i) => i.name).toList();
      expect(names.indexOf('CDケース'), names.indexOf('CD') + 1);
    });
  });

  test('変更の出典を持つ', () {
    expect(merged.changeSource, isNotEmpty);
    expect(merged.changeSourceUrl, contains('p127278'));
  });

  test('変更を渡さなければ、早見表のまま', () {
    final plain = WasteDictionary.fromJson(base, extra: extra);
    expect(
      plain.items.firstWhere((i) => i.name == '歯ブラシ').categoryId,
      'burnable',
    );
    expect(plain.changeSource, isEmpty);
  });
}
