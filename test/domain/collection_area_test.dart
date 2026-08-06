import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

void main() {
  const area = CollectionArea(
    id: CollectionArea.customAreaId,
    ward: '大宮区',
    name: 'わたしの地区',
    earlyMorning: true,
    rules: {
      GarbageCategory.burnable: [
        CollectionRule.weekly(DateTime.tuesday),
        CollectionRule.weekly(DateTime.friday),
      ],
      GarbageCategory.nonBurnable: [
        CollectionRule.monthly(DateTime.thursday, {1, 3}),
      ],
    },
  );

  test('JSONを往復しても収集ルールが保たれる', () {
    final restored = CollectionArea.fromJson(area.toJson());
    expect(restored.id, area.id);
    expect(restored.ward, '大宮区');
    expect(restored.name, 'わたしの地区');
    expect(restored.earlyMorning, isTrue);
    expect(restored.rulesFor(GarbageCategory.burnable), [
      const CollectionRule.weekly(DateTime.tuesday),
      const CollectionRule.weekly(DateTime.friday),
    ]);
    expect(restored.rulesFor(GarbageCategory.nonBurnable), [
      const CollectionRule.monthly(DateTime.thursday, {1, 3}),
    ]);
  });

  test('知らない区分IDが混ざっていても読み込めて、既知の区分は失われない', () {
    final json = area.toJson();
    (json['rules'] as Map<String, dynamic>)['unknownCategory'] = [
      {'weekday': 1},
    ];
    final restored = CollectionArea.fromJson(json);
    expect(restored.rulesFor(GarbageCategory.burnable), hasLength(2));
  });

  test('早朝収集地区のもえるごみだけ5:30、他は8:30', () {
    expect(area.depositDeadline(GarbageCategory.burnable), '5:30');
    expect(area.depositDeadline(GarbageCategory.recyclable1), '8:30');
  });

  test('早朝収集地区でなければすべて8:30', () {
    final normal = area.copyWith(earlyMorning: false);
    expect(normal.depositDeadline(GarbageCategory.burnable), '8:30');
  });

  test('収集日がひとつも無い地区は isEmpty', () {
    expect(CollectionArea.emptyCustom('南区').isEmpty, isTrue);
    expect(area.isEmpty, isFalse);
  });

  test('区の一覧は10区', () {
    expect(saitamaWards, hasLength(10));
    expect(saitamaWards, contains('岩槻区'));
  });
}
