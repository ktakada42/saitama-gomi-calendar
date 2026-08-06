import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/area_catalog.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

void main() {
  // 同梱アセットをそのまま読む。JSONの書き間違いはアプリを起動しないと
  // 気づけないので、テストで壊れていないことを保証しておく。
  final raw = File('assets/data/areas.json').readAsStringSync();
  final catalog = AreaCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  test('同梱データが読める', () {
    expect(catalog.presets, isNotEmpty);
    expect(catalog.source, isNotEmpty);
    expect(catalog.disclaimer, isNotEmpty);
  });

  test('雛形はもえるごみの曜日を持っている', () {
    for (final preset in catalog.presets) {
      expect(
        preset.rulesFor(GarbageCategory.burnable),
        isNotEmpty,
        reason: preset.name,
      );
    }
  });

  test('もえるごみは週2回', () {
    for (final preset in catalog.presets) {
      expect(
        preset.rulesFor(GarbageCategory.burnable),
        hasLength(2),
        reason: preset.name,
      );
    }
  });

  test('確定した地区データは区で絞り込める', () {
    // 市の地区表を取り込んだら、この絞り込みがそのまま
    // 「区を選ぶ→地区を選ぶ」の導線になる。同梱データの areas はまだ空なので、
    // 埋まったときの挙動をここで確かめておく。
    final filled = AreaCatalog.fromJson({
      'areas': [
        {
          'id': 'a',
          'ward': '浦和区',
          'name': 'A地区',
          'rules': {
            'burnable': [
              {'weekday': 1},
            ],
          },
        },
        {'id': 'b', 'ward': '南区', 'name': 'B地区', 'rules': <String, dynamic>{}},
      ],
    });
    expect(filled.areasInWard('浦和区').map((area) => area.id), ['a']);
    expect(filled.areasInWard('見沼区'), isEmpty);
  });
}
