import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/collection_boxes.dart';

/// 回収ボックスの検査。
///
/// 利用者はこれを見て実際に出かける。区名が地区データと食い違うと、
/// 設定しているのに「あなたの区」が出ない。数が合わないと、
/// 近所の1か所を見落とす。
void main() {
  late CollectionBoxes boxes;
  late Set<String> wardsInAreas;

  setUpAll(() {
    boxes = CollectionBoxes.fromJson(
      jsonDecode(File('assets/data/collection_boxes.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final raw = File('assets/data/areas.json').readAsStringSync();
    wardsInAreas = {
      for (final area
          in (jsonDecode(raw) as Map<String, dynamic>)['areas'] as List)
        (area as Map<String, dynamic>)['ward'] as String,
    };
  });

  group('同梱したデータ', () {
    test('10区すべてに設置場所がある', () {
      expect(boxes.places, hasLength(10));
    });

    test('区名は地区データと同じ表記', () {
      // ここがずれると、地区を設定しているのに「あなたの区」が出ない。
      // 気づきにくいので縛る。
      expect(boxes.places.map((p) => p.ward).toSet(), equals(wardsInAreas));
    });

    test('市内55か所', () {
      expect(boxes.totalPlaces, 55);
    });

    test('区ごとの数は冊子P12のとおり', () {
      final counts = {
        for (final place in boxes.places) place.ward: place.names.length,
      };
      expect(counts, {
        '西区': 3,
        '北区': 6,
        '大宮区': 6,
        '見沼区': 6,
        '中央区': 6,
        '桜区': 4,
        '浦和区': 6,
        '南区': 8,
        '緑区': 5,
        '岩槻区': 5,
      });
    });

    test('同じ場所を二重に書いていない', () {
      final all = [for (final place in boxes.places) ...place.names];
      expect(all.toSet(), hasLength(all.length));
    });

    test('箱は2種類で、色が分かる', () {
      // 現地では色で見分ける。名前より先に目に入る手がかり。
      final byId = {for (final b in boxes.boxes) b.id: b};
      expect(byId['smallAppliance']!.color, '黄色');
      expect(byId['battery']!.color, '白色');
    });

    test('宅配回収の連絡先がある', () {
      expect(boxes.homePickup.phone, '0570-085-800');
      expect(boxes.homePickup.url, startsWith('https://'));
    });

    test('出典が示されている', () {
      expect(boxes.source, contains('P12'));
      expect(boxes.sourceUrl, startsWith('https://www.city.saitama.lg.jp/'));
    });
  });

  group('区から設置場所を引く', () {
    test('設定済みの区の場所が出る', () {
      expect(boxes.placesIn('浦和区')?.names, contains('浦和区役所'));
      expect(boxes.placesIn('岩槻区')?.names, contains('岩槻本丸公民館'));
    });

    test('地区を設定していなければ null', () {
      // 初回起動では区が分からない。全区の一覧を出す側に倒す。
      expect(boxes.placesIn(null), isNull);
    });

    test('知らない区名なら null', () {
      expect(boxes.placesIn('さいたま区'), isNull);
      expect(boxes.placesIn(''), isNull);
    });
  });
}
