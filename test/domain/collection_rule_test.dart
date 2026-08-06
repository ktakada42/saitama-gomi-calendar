import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';

void main() {
  group('毎週のルール', () {
    const rule = CollectionRule.weekly(DateTime.tuesday);

    test('その曜日ならどの週でも一致する', () {
      // 2026年8月の火曜日は 4/11/18/25 日。
      for (final day in [4, 11, 18, 25]) {
        expect(rule.matches(DateTime(2026, 8, day)), isTrue, reason: '8月$day日');
      }
    });

    test('別の曜日には一致しない', () {
      expect(rule.matches(DateTime(2026, 8, 5)), isFalse);
    });

    test('表示は「毎週火曜日」', () {
      expect(rule.label, '毎週火曜日');
    });
  });

  group('第n週のルール', () {
    const rule = CollectionRule.monthly(DateTime.thursday, {2, 4});

    test('指定した週の木曜日だけ一致する', () {
      // 2026年8月の木曜は 6/13/20/27 日。第2は13日、第4は27日。
      expect(rule.matches(DateTime(2026, 8, 6)), isFalse);
      expect(rule.matches(DateTime(2026, 8, 13)), isTrue);
      expect(rule.matches(DateTime(2026, 8, 20)), isFalse);
      expect(rule.matches(DateTime(2026, 8, 27)), isTrue);
    });

    test('週番号は「その月で何回目のその曜日か」であってカレンダーの行ではない', () {
      // 2026年3月1日は日曜日。第1木曜は5日で、カレンダー上は1行目ではなく2行目にある。
      const thursday = CollectionRule.monthly(DateTime.thursday, {1});
      expect(DateTime(2026, 3, 1).weekday, DateTime.sunday);
      expect(thursday.matches(DateTime(2026, 3, 5)), isTrue);
      expect(thursday.matches(DateTime(2026, 3, 12)), isFalse);
    });

    test('第5週があるかどうかは月による', () {
      const fifth = CollectionRule.monthly(DateTime.saturday, {5});
      // 2026年8月の土曜は 1/8/15/22/29 日で第5土曜が存在する。
      expect(fifth.matches(DateTime(2026, 8, 29)), isTrue);
      // 2026年9月の土曜は 5/12/19/26 日までしかない。
      expect(fifth.matches(DateTime(2026, 9, 26)), isFalse);
    });

    test('表示は「第2・第4木曜日」', () {
      expect(rule.label, '第2・第4木曜日');
    });
  });

  test('nthWeekdayOfMonth は1始まりで7日ごとに増える', () {
    expect(CollectionRule.nthWeekdayOfMonth(DateTime(2026, 8, 1)), 1);
    expect(CollectionRule.nthWeekdayOfMonth(DateTime(2026, 8, 7)), 1);
    expect(CollectionRule.nthWeekdayOfMonth(DateTime(2026, 8, 8)), 2);
    expect(CollectionRule.nthWeekdayOfMonth(DateTime(2026, 8, 29)), 5);
  });

  group('JSON', () {
    test('毎週のルールを往復できる', () {
      const rule = CollectionRule.weekly(DateTime.friday);
      expect(CollectionRule.fromJson(rule.toJson()), rule);
    });

    test('第n週のルールを往復できる', () {
      const rule = CollectionRule.monthly(DateTime.wednesday, {1, 3});
      expect(CollectionRule.fromJson(rule.toJson()), rule);
    });

    test('毎週と第n週は等しくない', () {
      expect(
        const CollectionRule.weekly(DateTime.monday) ==
            const CollectionRule.monthly(DateTime.monday, {1, 2, 3, 4, 5}),
        isFalse,
      );
    });
  });
}
