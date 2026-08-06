import 'collection_calendar.dart';
import 'collection_rule.dart';

/// 日付の日本語表記。intl を入れるほどの量ではないので自前で持つ。
/// 純粋な関数なのでテストしやすく、画面側の分岐を減らせる。
class DateLabel {
  const DateLabel._();

  /// 「8月7日(金)」
  static String monthDay(DateTime date) =>
      '${date.month}月${date.day}日(${CollectionRule.weekdayName(date.weekday)})';

  /// 「2026年8月7日(金)」
  static String full(DateTime date) => '${date.year}年${monthDay(date)}';

  /// 「2026年8月」
  static String yearMonth(int year, int month) => '$year年$month月';

  /// [today] を基準にした「今日」「明日」「あさって」。それ以外は null。
  static String? relative(DateTime date, DateTime today) {
    final diff = CollectionCalendar.dateOnly(
      date,
    ).difference(CollectionCalendar.dateOnly(today)).inDays;
    return switch (diff) {
      0 => '今日',
      1 => '明日',
      2 => 'あさって',
      _ => null,
    };
  }

  /// 一覧で使う見出し。「明日 8月7日(金)」のように相対表記があれば前に付ける。
  static String headline(DateTime date, DateTime today) {
    final rel = relative(date, today);
    return rel == null ? monthDay(date) : '$rel ${monthDay(date)}';
  }
}
