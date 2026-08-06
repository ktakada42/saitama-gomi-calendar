import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_calendar.dart';
import 'package:saitama_gomi/domain/collection_reminder.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

/// もえるごみ 月・木／資源物1類 水／もえないごみ 第2火 の地区。
const _area = CollectionArea(
  id: CollectionArea.customAreaId,
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
    GarbageCategory.recyclable1: [CollectionRule.weekly(DateTime.wednesday)],
  },
);

const _planner = CollectionReminderPlanner(CollectionCalendar(_area));

/// 20:00 に通知する設定。
const _notifyAt = Duration(hours: 20);

void main() {
  test('収集日の前日に通知が並ぶ', () {
    // 2026年8月7日(金) 12:00 から。翌8日(土)は収集なし、10日(月)がもえるごみ。
    final reminders = _planner.plan(
      from: DateTime(2026, 8, 7, 12),
      notifyAt: _notifyAt,
      horizonDays: 7,
    );

    // 最初の通知は 9日(日)20:00 に出て、10日(月)のもえるごみを知らせる。
    expect(reminders.first.scheduledAt, DateTime(2026, 8, 9, 20));
    expect(reminders.first.collectionDate, DateTime(2026, 8, 10));
    expect(reminders.first.categories, [GarbageCategory.burnable]);
  });

  test('収集のない日には通知を作らない', () {
    final reminders = _planner.plan(
      from: DateTime(2026, 8, 7, 12),
      notifyAt: _notifyAt,
      horizonDays: 7,
    );

    // 8日(土)・9日(日)は収集がないので、その前夜（7日・8日）の通知は無い。
    final dates = reminders.map((r) => r.collectionDate).toList();
    expect(dates.contains(DateTime(2026, 8, 8)), isFalse);
    expect(dates.contains(DateTime(2026, 8, 9)), isFalse);
  });

  test('複数の区分が重なる日は1件にまとめる', () {
    // 2026年8月11日は第2火曜。もえないごみの日。
    final reminders = _planner.plan(
      from: DateTime(2026, 8, 9),
      notifyAt: _notifyAt,
      horizonDays: 3,
    );

    final forEleventh = reminders.firstWhere(
      (r) => r.collectionDate == DateTime(2026, 8, 11),
    );
    expect(forEleventh.categories, [GarbageCategory.nonBurnable]);
    // 同じ収集日に対して通知が2件できたりしない。
    expect(
      reminders.where((r) => r.collectionDate == DateTime(2026, 8, 11)).length,
      1,
    );
  });

  test('通知時刻を過ぎている当日分は作らない', () {
    // 8月9日(日)の21:00 時点。20:00 はもう過ぎている。
    final reminders = _planner.plan(
      from: DateTime(2026, 8, 9, 21),
      notifyAt: _notifyAt,
      horizonDays: 3,
    );

    // 9日20:00 の通知（＝10日の収集分）は作らない。
    expect(
      reminders.any((r) => r.scheduledAt == DateTime(2026, 8, 9, 20)),
      isFalse,
    );
    // 次に出るのは 10日20:00（＝11日の収集分）。
    expect(reminders.first.scheduledAt, DateTime(2026, 8, 10, 20));
  });

  test('年末年始の休止日は通知しない', () {
    // 2026年12月31日から。1月1日〜3日は収集を休む。
    final reminders = _planner.plan(
      from: DateTime(2026, 12, 31),
      notifyAt: _notifyAt,
      horizonDays: 5,
    );

    for (final reminder in reminders) {
      expect(
        CollectionCalendar.isSuspended(reminder.collectionDate),
        isFalse,
        reason: '休止日 ${reminder.collectionDate} の通知が作られている',
      );
    }
  });

  test('同じ収集日には同じ通知IDが振られる', () {
    final first = _planner.plan(
      from: DateTime(2026, 8, 7),
      notifyAt: _notifyAt,
      horizonDays: 7,
    );
    final second = _planner.plan(
      from: DateTime(2026, 8, 8),
      notifyAt: _notifyAt,
      horizonDays: 7,
    );

    // 張り直しても、同じ収集日に対しては同じIDになる（二重登録されない）。
    final firstIds = {for (final r in first) r.collectionDate: r.id};
    for (final reminder in second) {
      final knownId = firstIds[reminder.collectionDate];
      if (knownId != null) expect(reminder.id, knownId);
    }
  });

  test('本文に区分名が並ぶ', () {
    final reminders = _planner.plan(
      from: DateTime(2026, 8, 7, 12),
      notifyAt: _notifyAt,
      horizonDays: 7,
    );

    expect(reminders.first.body, '明日はもえるごみの日です');
  });

  test('予約する件数に上限をかけられる', () {
    final reminders = _planner.plan(
      from: DateTime(2026, 8, 7),
      notifyAt: _notifyAt,
      horizonDays: 365,
      limit: 5,
    );

    expect(reminders.length, 5);
  });

  test('収集曜日が未設定の地区では通知を作らない', () {
    const empty = CollectionReminderPlanner(
      CollectionCalendar(
        CollectionArea(
          id: CollectionArea.customAreaId,
          ward: '西区',
          name: '未設定',
          rules: {},
        ),
      ),
    );

    expect(
      empty.plan(from: DateTime(2026, 8, 7), notifyAt: _notifyAt),
      isEmpty,
    );
  });
}
