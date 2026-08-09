import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_calendar.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

/// もえるごみが月・木の地区。2026年8月6日は木曜。
const _area = CollectionArea(
  id: 'test',
  ward: '浦和区',
  name: 'テスト地区',
  rules: {
    GarbageCategory.burnable: [
      CollectionRule.weekly(DateTime.monday),
      CollectionRule.weekly(DateTime.thursday),
    ],
  },
);

/// 同じ曜日で、もえるごみの早朝収集地区。
const _earlyArea = CollectionArea(
  id: 'early',
  ward: '大宮区',
  name: '早朝地区',
  earlyMorning: true,
  rules: {
    GarbageCategory.burnable: [
      CollectionRule.weekly(DateTime.monday),
      CollectionRule.weekly(DateTime.thursday),
    ],
  },
);

void main() {
  group('DepositDeadline', () {
    test('ふつうの地区は8:30、早朝収集地区のもえるごみは5:30', () {
      expect(_area.depositDeadlineAt(GarbageCategory.burnable).label, '8:30');
      expect(
        _earlyArea.depositDeadlineAt(GarbageCategory.burnable).label,
        '5:30',
      );
      // 早朝収集が効くのはもえるごみだけ。
      expect(
        _earlyArea.depositDeadlineAt(GarbageCategory.recyclable1).label,
        '8:30',
      );
    });

    test('ちょうど期限の時刻はまだ出せる', () {
      const deadline = DepositDeadline(8, 30);
      expect(deadline.isPassedAt(DateTime(2026, 8, 6, 8, 29)), isFalse);
      expect(deadline.isPassedAt(DateTime(2026, 8, 6, 8, 30)), isFalse);
      expect(deadline.isPassedAt(DateTime(2026, 8, 6, 8, 31)), isTrue);
    });
  });

  group('canStillPutOut', () {
    const calendar = CollectionCalendar(_area);
    // 2026年8月6日は木曜＝もえるごみの日。
    final collectionDay = calendar.dayOf(DateTime(2026, 8, 6));

    test('収集日の朝、期限前ならまだ出せる', () {
      expect(
        calendar.canStillPutOut(collectionDay, DateTime(2026, 8, 6, 7, 0)),
        isTrue,
      );
    });

    test('期限を過ぎたらもう出せない', () {
      expect(
        calendar.canStillPutOut(collectionDay, DateTime(2026, 8, 6, 9, 0)),
        isFalse,
      );
    });

    test('収集のない日は、朝でも出せない', () {
      // 8月7日は金曜で収集がない。
      final noCollection = calendar.dayOf(DateTime(2026, 8, 7));
      expect(
        calendar.canStillPutOut(noCollection, DateTime(2026, 8, 7, 7, 0)),
        isFalse,
      );
    });

    test('別の日の収集日を今の時刻で聞かれても出せない', () {
      // 明日の分を「今」出せるわけではない。
      expect(
        calendar.canStillPutOut(collectionDay, DateTime(2026, 8, 5, 7, 0)),
        isFalse,
      );
    });

    test('早朝収集地区は5:30で切り替わる', () {
      const early = CollectionCalendar(_earlyArea);
      final day = early.dayOf(DateTime(2026, 8, 6));
      expect(early.canStillPutOut(day, DateTime(2026, 8, 6, 5, 0)), isTrue);
      // ふつうの地区ならまだ出せる時刻でも、早朝地区は過ぎている。
      expect(early.canStillPutOut(day, DateTime(2026, 8, 6, 7, 0)), isFalse);
      expect(
        calendar.canStillPutOut(collectionDay, DateTime(2026, 8, 6, 7, 0)),
        isTrue,
      );
    });
  });

  group('featuredDay', () {
    const calendar = CollectionCalendar(_area);

    test('収集日の朝は今日を出す', () {
      final featured = calendar.featuredDay(DateTime(2026, 8, 6, 7, 0));
      expect(featured.date, DateTime(2026, 8, 6));
      expect(featured.categories, [GarbageCategory.burnable]);
    });

    test('期限を過ぎたら明日に切り替わる', () {
      final featured = calendar.featuredDay(DateTime(2026, 8, 6, 9, 0));
      expect(featured.date, DateTime(2026, 8, 7));
    });

    test('収集のない日は、朝でも明日を出す', () {
      // 8月7日（金）は収集がない。今日を大きく出しても伝えることがない。
      final featured = calendar.featuredDay(DateTime(2026, 8, 7, 7, 0));
      expect(featured.date, DateTime(2026, 8, 8));
    });

    test('日付が変わった直後も、その日の収集日なら今日を出す', () {
      final featured = calendar.featuredDay(DateTime(2026, 8, 6, 0, 1));
      expect(featured.date, DateTime(2026, 8, 6));
    });
  });
}
