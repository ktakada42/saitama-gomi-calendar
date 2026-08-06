import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/area_catalog.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
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

  test('地区データは区で絞り込める（合成データでの単体テスト）', () {
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

  // ここから先は scripts/update_areas_json.mjs が生成した実データ
  // （さいたま市「収集日カレンダー」由来）の健全性チェック。
  // データ更新のたびに壊れていないことをここで保証する。

  test('確定した地区データが同梱されている', () {
    expect(catalog.areas, isNotEmpty);
  });

  test('10区すべてに1件以上の地区がある', () {
    for (final ward in saitamaWards) {
      expect(catalog.areasInWard(ward), isNotEmpty, reason: ward);
    }
  });

  test('西区には複数の収集パターンがある', () {
    // 西区は同じ区の中でも収集曜日が3パターンに分かれている。
    expect(catalog.areasInWard('西区').length, greaterThanOrEqualTo(3));
  });

  test('早朝収集地区（★）を持つ地区が存在する', () {
    expect(catalog.areas.any((area) => area.earlyMorning), isTrue);
  });

  test('すべての確定地区で5区分すべての曜日が決まっている', () {
    // 手入力を経ないデータなので、区分の設定漏れがあれば必ずここで気づけるようにする。
    for (final area in catalog.areas) {
      for (final category in GarbageCategory.values) {
        expect(
          area.rulesFor(category),
          isNotEmpty,
          reason: '${area.ward} ${area.name} / ${category.label}',
        );
      }
    }
  });

  test('地区IDに重複がない', () {
    final ids = catalog.areas.map((area) => area.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
