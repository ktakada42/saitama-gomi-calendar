import 'collection_calendar.dart';
import 'garbage_category.dart';

/// 前夜に出す通知1件分。
class CollectionReminder {
  const CollectionReminder({
    required this.scheduledAt,
    required this.collectionDate,
    required this.categories,
  });

  /// 通知を出す日時（収集日の前日の、利用者が設定した時刻）。
  final DateTime scheduledAt;

  /// 通知が指している収集日（`scheduledAt`の翌日）。
  final DateTime collectionDate;

  /// その日に出せる区分。空になることはない（収集がある日だけ通知するため）。
  final List<GarbageCategory> categories;

  /// 通知の本文。「もえるごみ・資源物1類」のように区分を並べる。
  String get body => '明日は${categories.map((c) => c.label).join('・')}の日です';

  /// OSに渡す通知ID。
  ///
  /// 同じ日付には必ず同じIDが振られるので、張り直しても二重に登録されない。
  /// 32bit intに収める必要があるため、年月日を素直に連結した数値にする
  /// （例: 2026年8月7日 → 20260807）。
  int get id =>
      collectionDate.year * 10000 +
      collectionDate.month * 100 +
      collectionDate.day;

  @override
  String toString() =>
      'CollectionReminder($scheduledAt -> $collectionDate: ${categories.map((c) => c.id).join(',')})';
}

/// 「地区の収集ルールから、いつ何を通知すべきか」を計算する。
///
/// OSの通知APIには触らない純粋な計算だけを持つ。こうしておくと、
/// 通知の中身とタイミングの判断を単体テストで担保できる
/// （[docs/next-phase.md](../../docs/next-phase.md) B.4節）。
class CollectionReminderPlanner {
  const CollectionReminderPlanner(this.calendar);

  final CollectionCalendar calendar;

  /// [from]以降に出すべき通知の一覧を、古い順に返す。
  ///
  /// [notifyAt]は通知を出す時刻（収集日の前日の何時か）。
  /// [horizonDays]は何日先まで予約するか。OSが一度に保持できる通知数には
  /// 上限がある（iOSでは64件）ため、無制限には作らない。
  ///
  /// [from]より前になる通知は含めない。つまり「今日の分の通知時刻を過ぎていたら、
  /// その通知は作らない」。過ぎた時刻に予約しても発火しないうえ、
  /// 端末によっては即時に発火してしまうため。
  List<CollectionReminder> plan({
    required DateTime from,
    required Duration notifyAt,
    int horizonDays = 30,
    int limit = 60,
  }) {
    final startDate = CollectionCalendar.dateOnly(from);
    final reminders = <CollectionReminder>[];

    for (var offset = 0; offset <= horizonDays; offset++) {
      // 「offset日後の前夜」に通知するので、収集日はその翌日。
      final notifyDate = startDate.add(Duration(days: offset));
      final collectionDate = notifyDate.add(const Duration(days: 1));

      final categories = calendar.categoriesOn(collectionDate);
      // 収集のない日・年末年始の休止日（categoriesOnが空を返す）は通知しない。
      if (categories.isEmpty) continue;

      final scheduledAt = notifyDate.add(notifyAt);
      // 通知時刻をすでに過ぎている分は作らない。
      if (!scheduledAt.isAfter(from)) continue;

      reminders.add(
        CollectionReminder(
          scheduledAt: scheduledAt,
          collectionDate: collectionDate,
          categories: categories,
        ),
      );
      if (reminders.length >= limit) break;
    }

    return reminders;
  }
}
