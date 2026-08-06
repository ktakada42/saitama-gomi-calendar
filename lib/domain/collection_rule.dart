/// 収集日の繰り返しパターン。
///
/// さいたま市の収集日はすべて「◯曜日」を軸に決まっていて、
/// 毎週のものと「第2・第4◯曜日」のように月内の週を限るものがある。
/// 日付そのもの（毎月15日など）で決まる区分は存在しないため、
/// 曜日＋月内の週番号の2要素だけで全パターンを表現できる。
class CollectionRule {
  /// 毎週その曜日に収集される。
  const CollectionRule.weekly(this.weekday) : weeksOfMonth = null;

  /// 月内の特定の週だけ収集される（例：第1・第3水曜日なら `{1, 3}`）。
  const CollectionRule.monthly(this.weekday, this.weeksOfMonth);

  /// [DateTime.monday] から [DateTime.sunday]（1〜7）。
  final int weekday;

  /// 収集する週番号の集合。`null` なら毎週。
  ///
  /// 週番号は「その月で何回目のその曜日か」を表す。カレンダーの行数ではないので、
  /// 月初が日曜でも第1◯曜日は必ずその月の最初の◯曜日になる。
  final Set<int>? weeksOfMonth;

  bool get isWeekly => weeksOfMonth == null;

  /// [date] がこのルールの収集日にあたるか。
  bool matches(DateTime date) {
    if (date.weekday != weekday) return false;
    final weeks = weeksOfMonth;
    if (weeks == null) return true;
    return weeks.contains(nthWeekdayOfMonth(date));
  }

  /// [date] がその月で何回目の同じ曜日か（1始まり）。
  static int nthWeekdayOfMonth(DateTime date) => ((date.day - 1) ~/ 7) + 1;

  static const _weekdayNames = ['月', '火', '水', '木', '金', '土', '日'];

  /// 「毎週火曜日」「第2・第4木曜日」のような表示用の文字列。
  String get label {
    final name = '${_weekdayNames[weekday - 1]}曜日';
    final weeks = weeksOfMonth;
    if (weeks == null) return '毎週$name';
    final sorted = weeks.toList()..sort();
    return '第${sorted.join('・第')}$name';
  }

  static String weekdayName(int weekday) => _weekdayNames[weekday - 1];

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    if (weeksOfMonth != null) 'weeksOfMonth': (weeksOfMonth!.toList()..sort()),
  };

  factory CollectionRule.fromJson(Map<String, dynamic> json) {
    final weekday = json['weekday'] as int;
    final weeks = json['weeksOfMonth'] as List<dynamic>?;
    if (weeks == null) return CollectionRule.weekly(weekday);
    return CollectionRule.monthly(weekday, weeks.cast<int>().toSet());
  }

  @override
  bool operator ==(Object other) {
    if (other is! CollectionRule) return false;
    if (other.weekday != weekday) return false;
    final a = weeksOfMonth;
    final b = other.weeksOfMonth;
    if (a == null || b == null) return a == b;
    return a.length == b.length && a.containsAll(b);
  }

  @override
  int get hashCode => Object.hash(
    weekday,
    weeksOfMonth == null ? null : Object.hashAllUnordered(weeksOfMonth!),
  );

  @override
  String toString() => 'CollectionRule($label)';
}
