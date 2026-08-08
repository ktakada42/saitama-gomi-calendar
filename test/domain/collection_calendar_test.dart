import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_calendar.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

/// もえるごみが週2回、もえないごみと有害危険ごみが月1回、
/// 資源物が週1回という、市の案内でよくある組み合わせに近い地区。
const testArea = CollectionArea(
  id: 'test',
  ward: '浦和区',
  name: 'テスト地区',
  rules: {
    GarbageCategory.burnable: [
      CollectionRule.weekly(DateTime.monday),
      CollectionRule.weekly(DateTime.thursday),
    ],
    GarbageCategory.nonBurnable: [
      CollectionRule.monthly(DateTime.tuesday, {2}),
    ],
    GarbageCategory.hazardous: [
      CollectionRule.monthly(DateTime.tuesday, {4}),
    ],
    GarbageCategory.recyclable1: [CollectionRule.weekly(DateTime.wednesday)],
    GarbageCategory.recyclable2: [CollectionRule.weekly(DateTime.tuesday)],
  },
);

void main() {
  const calendar = CollectionCalendar(testArea);

  group('categoriesOn', () {
    test('もえるごみの日', () {
      // 2026年8月3日は月曜日。
      expect(calendar.categoriesOn(DateTime(2026, 8, 3)), [
        GarbageCategory.burnable,
      ]);
    });

    test('同じ日に複数の区分が重なる場合は区分の並び順で返る', () {
      // 8月11日は第2火曜。もえないごみ（第2火）と資源物2類（毎週火）が重なる。
      expect(calendar.categoriesOn(DateTime(2026, 8, 11)), [
        GarbageCategory.nonBurnable,
        GarbageCategory.recyclable2,
      ]);
    });

    test('第4火曜には有害危険ごみが出る', () {
      expect(calendar.categoriesOn(DateTime(2026, 8, 25)), [
        GarbageCategory.hazardous,
        GarbageCategory.recyclable2,
      ]);
    });

    test('収集のない日は空', () {
      // 8月7日は金曜日でどの区分の収集日でもない。
      expect(calendar.categoriesOn(DateTime(2026, 8, 7)), isEmpty);
    });
  });

  group('年末年始', () {
    test('1月1日から3日は曜日が合っていても収集しない', () {
      // 2027年1月4日は月曜（もえるごみ）。1月1日は金曜で元々収集がない。
      // 曜日が合う日で確認するため、月曜が1〜3日に来る年で見る。
      // 2029年1月1日は月曜日。
      expect(DateTime(2029, 1, 1).weekday, DateTime.monday);
      expect(calendar.categoriesOn(DateTime(2029, 1, 1)), isEmpty);
      expect(CollectionCalendar.isSuspended(DateTime(2029, 1, 1)), isTrue);
    });

    test('1月4日以降は通常どおり', () {
      expect(CollectionCalendar.isSuspended(DateTime(2027, 1, 4)), isFalse);
      expect(calendar.categoriesOn(DateTime(2027, 1, 4)), [
        GarbageCategory.burnable,
      ]);
    });

    test('祝日でも収集する', () {
      // 2026年8月11日は山の日の振替ではないが、市は祝日も収集する方針なので
      // 祝日判定そのものを持たない。ここでは休止日が1月1〜3日だけであることを示す。
      expect(CollectionCalendar.isSuspended(DateTime(2026, 5, 4)), isFalse);
    });
  });

  group('年末年始・令和8年度マニュアルの記載どおりの日付になる', () {
    // 市のマニュアル1ページ目に、令和8年度の年末年始の収集について
    // 曜日パターンごとの最終収集日・収集再開日が例示されている。
    //
    //   もえるごみ 月・木曜日  最終日12/31（木） 開始日1/4（月）
    //   もえるごみ 火・金曜日  最終日12/29（火） 開始日1/5（火）
    //   もえるごみ 水・土曜日  最終日12/30（水） 開始日1/6（水）
    //   もえないごみ・有害危険ごみ・資源物1・2類
    //                         最終日12/31（木）まで 開始日1/4（月）以降の各地区の収集曜日
    //
    // これは特別なルールではなく、「1/1〜3だけ休止し、それ以外は通常の
    // 曜日ルールを続ける」という一つのルール（isSuspended）を、
    // 令和8年度の実際の曜日に当てはめた結果と一致する。この一致を
    // 日付で固定しておき、isSuspendedを不用意に変えたときに気づけるようにする。
    const monThu = CollectionCalendar(
      CollectionArea(
        id: 'mon-thu',
        ward: '浦和区',
        name: '月木地区',
        rules: {
          GarbageCategory.burnable: [
            CollectionRule.weekly(DateTime.monday),
            CollectionRule.weekly(DateTime.thursday),
          ],
        },
      ),
    );
    const tueFri = CollectionCalendar(
      CollectionArea(
        id: 'tue-fri',
        ward: '浦和区',
        name: '火金地区',
        rules: {
          GarbageCategory.burnable: [
            CollectionRule.weekly(DateTime.tuesday),
            CollectionRule.weekly(DateTime.friday),
          ],
        },
      ),
    );
    const wedSat = CollectionCalendar(
      CollectionArea(
        id: 'wed-sat',
        ward: '浦和区',
        name: '水土地区',
        rules: {
          GarbageCategory.burnable: [
            CollectionRule.weekly(DateTime.wednesday),
            CollectionRule.weekly(DateTime.saturday),
          ],
        },
      ),
    );

    test('月・木曜日地区：最終12/31（木）、次は1/4（月）', () {
      expect(monThu.categoriesOn(DateTime(2026, 12, 31)), isNotEmpty);
      for (final d in [
        DateTime(2027, 1, 1),
        DateTime(2027, 1, 2),
        DateTime(2027, 1, 3),
      ]) {
        expect(monThu.categoriesOn(d), isEmpty, reason: '$d');
      }
      expect(monThu.categoriesOn(DateTime(2027, 1, 4)), isNotEmpty);
    });

    test('火・金曜日地区：最終12/29（火）、次は1/5（火）', () {
      expect(tueFri.categoriesOn(DateTime(2026, 12, 29)), isNotEmpty);
      // 1/1（金）は通常なら収集日だが、休止期間なので出ない。
      expect(tueFri.categoriesOn(DateTime(2027, 1, 1)), isEmpty);
      expect(tueFri.categoriesOn(DateTime(2027, 1, 5)), isNotEmpty);
    });

    test('水・土曜日地区：最終12/30（水）、次は1/6（水）', () {
      expect(wedSat.categoriesOn(DateTime(2026, 12, 30)), isNotEmpty);
      // 1/2（土）は通常なら収集日だが、休止期間なので出ない。
      expect(wedSat.categoriesOn(DateTime(2027, 1, 2)), isEmpty);
      expect(wedSat.categoriesOn(DateTime(2027, 1, 6)), isNotEmpty);
    });
  });

  group('month', () {
    test('1日から末日まで全部返す', () {
      final august = calendar.month(2026, 8);
      expect(august.length, 31);
      expect(august.first.date, DateTime(2026, 8, 1));
      expect(august.last.date, DateTime(2026, 8, 31));
    });

    test('2月の日数も正しく扱う', () {
      expect(calendar.month(2026, 2).length, 28);
      expect(calendar.month(2028, 2).length, 29);
    });

    test('収集のない日も要素として含む', () {
      final august = calendar.month(2026, 8);
      expect(august.where((day) => day.isEmpty), isNotEmpty);
    });
  });

  group('upcoming', () {
    test('当日を含めて古い順に返す', () {
      // 2026年8月6日は木曜日（もえるごみ）。
      final days = calendar.upcoming(DateTime(2026, 8, 6), limit: 4);
      expect(days.map((day) => day.date.day), [6, 10, 11, 12]);
      expect(days.first.categories, [GarbageCategory.burnable]);
    });

    test('収集のない日は含まない', () {
      final days = calendar.upcoming(DateTime(2026, 8, 7), limit: 3);
      expect(days.every((day) => day.isNotEmpty), isTrue);
      expect(days.first.date, DateTime(2026, 8, 10));
    });

    test('収集日が無い地区でも打ち切って返る', () {
      const empty = CollectionCalendar(
        CollectionArea(id: 'x', ward: '南区', name: '空', rules: {}),
      );
      expect(empty.upcoming(DateTime(2026, 8, 6)), isEmpty);
    });
  });

  group('nextFor', () {
    test('月1回の区分の次回を月をまたいで探す', () {
      // 8月の第2火曜（11日）を過ぎたら、次は9月の第2火曜（8日）。
      final next = calendar.nextFor(
        GarbageCategory.nonBurnable,
        DateTime(2026, 8, 12),
      );
      expect(next!.date, DateTime(2026, 9, 8));
    });

    test('当日が収集日ならその日を返す', () {
      final next = calendar.nextFor(
        GarbageCategory.burnable,
        DateTime(2026, 8, 6),
      );
      expect(next!.date, DateTime(2026, 8, 6));
    });

    test('設定のない区分は null', () {
      const partial = CollectionCalendar(
        CollectionArea(
          id: 'x',
          ward: '南区',
          name: '一部だけ',
          rules: {
            GarbageCategory.burnable: [CollectionRule.weekly(DateTime.monday)],
          },
        ),
      );
      expect(
        partial.nextFor(GarbageCategory.hazardous, DateTime(2026, 8, 6)),
        isNull,
      );
    });
  });

  group('日付ユーティリティ', () {
    test('dateOnly は時刻を落とす', () {
      expect(
        CollectionCalendar.dateOnly(DateTime(2026, 8, 6, 23, 59)),
        DateTime(2026, 8, 6),
      );
    });

    test('isSameDate は時刻を無視する', () {
      expect(
        CollectionCalendar.isSameDate(
          DateTime(2026, 8, 6, 1),
          DateTime(2026, 8, 6, 22),
        ),
        isTrue,
      );
    });
  });
}
