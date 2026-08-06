import 'collection_area.dart';
import 'garbage_category.dart';

/// ある1日と、その日に出せる区分。
class CollectionDay {
  const CollectionDay(this.date, this.categories);

  final DateTime date;

  /// [GarbageCategory] の宣言順に並ぶ。空なら収集のない日。
  final List<GarbageCategory> categories;

  bool get isEmpty => categories.isEmpty;
  bool get isNotEmpty => categories.isNotEmpty;
}

/// 地区の収集ルールから、日付ごとの収集区分を引くカレンダー。
///
/// Flutter に依存しない純粋な Dart。日付計算はここに閉じ込めて、
/// 画面側は「この日は何ごみか」を聞くだけにする。
class CollectionCalendar {
  const CollectionCalendar(this.area);

  final CollectionArea area;

  /// 収集を休む日。さいたま市は祝日も収集するが、1月1日〜3日だけは休み。
  static bool isSuspended(DateTime date) => date.month == 1 && date.day <= 3;

  /// 時刻を落とした日付。DateTime をキーに使うため必ずこれを通す。
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// [date] に出せる区分。収集休止日は必ず空になる。
  List<GarbageCategory> categoriesOn(DateTime date) {
    if (isSuspended(date)) return const [];
    return [
      for (final category in GarbageCategory.values)
        if (area.rulesFor(category).any((rule) => rule.matches(date))) category,
    ];
  }

  CollectionDay dayOf(DateTime date) {
    final day = dateOnly(date);
    return CollectionDay(day, categoriesOn(day));
  }

  /// [year] 年 [month] 月の全日。収集のない日も含めて1日から末日まで返す。
  List<CollectionDay> month(int year, int month) {
    // 翌月0日 = 当月末日。月末が28〜31日と揺れるのをここで吸収する。
    final lastDay = DateTime(year, month + 1, 0).day;
    return [
      for (var day = 1; day <= lastDay; day++)
        CollectionDay(
          DateTime(year, month, day),
          categoriesOn(DateTime(year, month, day)),
        ),
    ];
  }

  /// [from] 以降で収集のある日を古い順に。[from] 当日も含む。
  ///
  /// [horizonDays] は探索の打ち切り。区分によっては月1回しかないので、
  /// 何も設定されていない地区で無限に探し続けないための上限でもある。
  List<CollectionDay> upcoming(
    DateTime from, {
    int limit = 10,
    int horizonDays = 120,
  }) {
    final start = dateOnly(from);
    final result = <CollectionDay>[];
    for (var offset = 0; offset < horizonDays; offset++) {
      final date = start.add(Duration(days: offset));
      final categories = categoriesOn(date);
      if (categories.isEmpty) continue;
      result.add(CollectionDay(date, categories));
      if (result.length >= limit) break;
    }
    return result;
  }

  /// [category] の次の収集日。[from] 当日も含む。見つからなければ null。
  CollectionDay? nextFor(
    GarbageCategory category,
    DateTime from, {
    int horizonDays = 120,
  }) {
    final start = dateOnly(from);
    for (var offset = 0; offset < horizonDays; offset++) {
      final date = start.add(Duration(days: offset));
      final categories = categoriesOn(date);
      if (categories.contains(category)) {
        return CollectionDay(date, categories);
      }
    }
    return null;
  }
}
