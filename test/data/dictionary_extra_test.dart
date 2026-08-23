import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';

/// 図解ページからの補いの検査。
///
/// 早見表は市の資料の一部でしかない。マニュアル自身が「早見表に記載のない
/// 品目は、市ホームページやごみ分別アプリで検索できます」と書いており、
/// 飲料の缶のような基本的な品目も早見表には無い。同じマニュアルの図解ページ
/// （P6・P8・P10〜P12）から補っている。
void main() {
  late Map<String, dynamic> base;
  late Map<String, dynamic> extra;
  late WasteDictionary merged;

  setUpAll(() {
    base =
        jsonDecode(File('assets/data/dictionary.json').readAsStringSync())
            as Map<String, dynamic>;
    extra =
        jsonDecode(File('assets/data/dictionary_extra.json').readAsStringSync())
            as Map<String, dynamic>;
    merged = WasteDictionary.fromJson(
      base,
      extra: extra,
      kana:
          jsonDecode(File('assets/data/dictionary_kana.json').readAsStringSync())
              as Map<String, dynamic>,
    );
  });

  group('補いのデータ', () {
    test('早見表と同じ名前を足していない', () {
      // 同じ品目が2度並ぶと、どちらが正しいのか分からなくなる。
      final baseNames = {
        for (final item in base['items'] as List)
          (item as Map<String, dynamic>)['name'] as String,
      };
      for (final item in extra['items'] as List) {
        final name = (item as Map<String, dynamic>)['name'] as String;
        expect(baseNames, isNot(contains(name)), reason: name);
      }
    });

    test('補いの中でも名前が重複しない', () {
      final names = [
        for (final item in extra['items'] as List)
          (item as Map<String, dynamic>)['name'] as String,
      ];
      expect(names.toSet(), hasLength(names.length));
    });

    test('どの品目にも出典のページが書いてある', () {
      // どこから取ったか分からなくなると、市の資料が変わったときに
      // 突き合わせられない。
      for (final item in extra['items'] as List) {
        final map = item as Map<String, dynamic>;
        expect(map['page'], isNotNull, reason: map['name'] as String);
        expect(map['page'], startsWith('P'), reason: map['name'] as String);
      }
    });

    test('区分は早見表が使っているものだけ', () {
      final known = {
        for (final item in base['items'] as List)
          (item as Map<String, dynamic>)['category'] as String,
      };
      for (final item in extra['items'] as List) {
        final map = item as Map<String, dynamic>;
        expect(known, contains(map['category']), reason: map['name'] as String);
      }
    });
  });

  group('合わせて読む', () {
    test('早見表と補いの両方が入る', () {
      final baseCount = (base['items'] as List).length;
      final extraCount = (extra['items'] as List).length;
      expect(merged.items, hasLength(baseCount + extraCount));
    });

    test('飲料の缶を引けるようになった', () {
      // 早見表には一斗かん・スプレーかん・やかんはあるのに、
      // いちばん身近な飲料の缶が無かった。
      expect(merged.search('飲料のかん'), isNotEmpty);
      final hit = merged.search('かん').map((i) => i.name);
      expect(hit, contains('飲料のかん'));
      expect(hit, contains('缶詰のかん'));
    });

    test('フタの行き先を引けるようになった', () {
      // 早見表には「風呂のフタ」しか無かった。いちばん訊かれるのは
      // びん・かん・ペットボトルのフタのほう。
      final names = merged.search('フタ').map((i) => i.name).toList();
      expect(names, contains('びんのフタ（金属製）'));
      expect(names, contains('かんのフタ（金属製）'));
      expect(names, contains('ペットボトルのフタ'));
    });

    test('太陽ソーラーを引けるようになった', () {
      // AIに推定させると「もえないごみ」と答えた品目。
      // 実際は許可業者行きで、市の資料には載っていた。
      final hit = merged.search('太陽ソーラー').single;
      expect(hit.categoryLabel, '収集できないもの');
      expect(hit.note, contains('太盛'));
    });

    test('紛らわしい別物を、名前で見分けられる', () {
      // P11のミニカーは一人乗りの車。早見表のミニカーはおもちゃ。
      final names = merged.search('ミニカー').map((i) => i.name).toList();
      expect(names, contains('ミニカー（おもちゃ）'));
      expect(names, contains('ミニカー（一人乗りの車）'));
    });

    test('五十音の並びが崩れない', () {
      // 補いを後ろに繋いだままだと「わ」の次に「い」が来て、
      // 索引から飛んだ先がずれる。
      const order =
          'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほ'
          'まみむめもやゆよらりるれろわをん';
      var previous = -1;
      for (final item in merged.items) {
        final index = order.indexOf(item.kanaHead);
        if (index < 0) continue;
        expect(index, greaterThanOrEqualTo(previous), reason: item.name);
        previous = index;
      }
    });

    test('補いも読みの順に混ざる', () {
      // 補いを行の末尾に足すだけだと、「あ」の早見表の品目を全部見終わった
      // 後ろに「油のかん」が来る。読みを持たせて混ぜ込む。
      expect(
        merged.items
            .where((item) => item.kanaHead == 'あ')
            .map((item) => item.name),
        [
          'アイロン',
          '足拭きマット',
          '油（食用油）',
          '油食品等の容器',
          '油のかん',
          '油のびん',
          '雨衣（カッパ）',
          '網戸',
          'アルバム（写真用）',
          'アルミ箔',
        ],
      );
    });

    test('補い全件に読みがある', () {
      // 読みが無いと名前から起こそうとして、漢字のまま比べることになる。
      for (final item in extra['items'] as List) {
        final map = item as Map<String, dynamic>;
        expect(map['kana'], isNotEmpty, reason: map['name'] as String);
      }
    });
  });
}
