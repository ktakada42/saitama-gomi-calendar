import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_calendar.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';
import 'package:saitama_gomi/domain/widget_payload.dart';

/// もえるごみ月・木／もえないごみ第2火の地区。2026年8月6日は木曜。
const _area = CollectionArea(
  id: 'test',
  ward: '浦和区',
  name: '大原1〜5丁目',
  rules: {
    GarbageCategory.burnable: [
      CollectionRule.weekly(DateTime.monday),
      CollectionRule.weekly(DateTime.thursday),
    ],
    GarbageCategory.nonBurnable: [
      CollectionRule.monthly(DateTime.tuesday, {2}),
    ],
  },
);

void main() {
  const calendar = CollectionCalendar(_area);
  final from = DateTime(2026, 8, 6, 9, 0);

  test('収集のある日だけを古い順に並べる', () {
    final payload = WidgetPayload.build(calendar, from, horizonDays: 8);

    // 8/6(木) 8/10(月) 8/11(火) 8/13(木) が収集日。
    expect(payload.days.map((d) => d.date), [
      DateTime(2026, 8, 6),
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 11),
      DateTime(2026, 8, 13),
    ]);
  });

  test('地区名は画面と同じ表記', () {
    final payload = WidgetPayload.build(calendar, from);
    expect(payload.areaLabel, '浦和区 大原1〜5丁目');
  });

  test('期限は分別ごとの中でいちばん遅いものを採る', () {
    // 早朝収集地区では、もえるごみだけ5:30、他は8:30。
    // ひとつでもまだ出せるものがあれば、その日はまだ行ける日なので
    // 遅い方（8:30）を日の期限とする。
    const early = CollectionCalendar(
      CollectionArea(
        id: 'early',
        ward: '大宮区',
        name: '早朝地区',
        earlyMorning: true,
        rules: {
          GarbageCategory.burnable: [CollectionRule.weekly(DateTime.thursday)],
          GarbageCategory.recyclable1: [
            CollectionRule.weekly(DateTime.thursday),
          ],
        },
      ),
    );
    final payload = WidgetPayload.build(early, from, horizonDays: 1);
    expect(payload.days.single.deadlineHour, 8);
    expect(payload.days.single.deadlineMinute, 30);
  });

  test('早朝収集地区でもえるごみだけの日は5:30', () {
    const early = CollectionCalendar(
      CollectionArea(
        id: 'early',
        ward: '大宮区',
        name: '早朝地区',
        earlyMorning: true,
        rules: {
          GarbageCategory.burnable: [CollectionRule.weekly(DateTime.thursday)],
        },
      ),
    );
    final payload = WidgetPayload.build(early, from, horizonDays: 1);
    expect(payload.days.single.deadlineHour, 5);
    expect(payload.days.single.deadlineMinute, 30);
  });

  group('JSON', () {
    test('日付はタイムゾーンを持たない形で書く', () {
      // タイムゾーン付きにすると、ウィジェット側で日付がずれうる。
      final payload = WidgetPayload.build(calendar, from, horizonDays: 1);
      final json = payload.toJson();
      final day = (json['days'] as List).single as Map<String, dynamic>;
      expect(day['date'], '2026-08-06');
    });

    test('分別はidで渡す。名前・色はウィジェット側が持つ', () {
      final payload = WidgetPayload.build(calendar, from, horizonDays: 6);
      final json = payload.toJson();
      final days = json['days'] as List;
      expect((days.first as Map)['categories'], ['burnable']);
      // 8/11は第2火曜。もえないごみ。
      final tuesday = days.firstWhere(
        (d) => (d as Map)['date'] == '2026-08-11',
      );
      expect((tuesday as Map)['categories'], ['nonBurnable']);
    });

    test('地区名と書き出し時刻も入る', () {
      final json = WidgetPayload.build(calendar, from, horizonDays: 1).toJson();
      expect(json['areaLabel'], '浦和区 大原1〜5丁目');
      expect(json['generatedAt'], from.toIso8601String());
    });
  });

  test('先の分まで書き出す。しばらくアプリを開かなくても尽きないように', () {
    final payload = WidgetPayload.build(calendar, from);
    // 60日ぶん見るので、月1回のもえないごみも2回入る。
    final nonBurnable = payload.days.where(
      (d) => d.categoryIds.contains('nonBurnable'),
    );
    expect(nonBurnable.length, greaterThanOrEqualTo(2));
  });
}
