import 'collection_calendar.dart';

/// ホーム画面ウィジェットに渡す内容。
///
/// 収集日の計算はDartで書いてあり、ウィジェット（Swift）からは呼べない。
/// ロジックを二重に持つと、片方だけ直したときに表示が食い違う。
/// そこでアプリ側で先の分まで計算し、その結果だけを共有領域に書き出す。
/// ウィジェットはそれを読んで並べるだけにする（通知機能と同じ考え方）。
class WidgetPayload {
  const WidgetPayload({
    required this.areaLabel,
    required this.days,
    required this.generatedAt,
  });

  /// 「浦和区 大原1〜5丁目」。ウィジェットの隅に出して、どの地区の予定かを示す。
  final String areaLabel;

  /// 収集のある日だけを古い順に並べたもの。収集のない日は含まない。
  final List<WidgetDay> days;

  /// 書き出した時刻。ウィジェット側で「いつのデータか」を判断するのに使う。
  final DateTime generatedAt;

  /// 何日先まで書き出すか。
  ///
  /// ウィジェットはアプリが起動していなくても動き続けるので、しばらく
  /// アプリを開かなくても表示が尽きない長さが要る。月1回の分別でも
  /// 2回は入る長さとして60日を取る。
  static const horizonDays = 60;

  Map<String, dynamic> toJson() => {
    'areaLabel': areaLabel,
    'generatedAt': generatedAt.toIso8601String(),
    'days': [for (final day in days) day.toJson()],
  };

  /// [calendar] から [from] 以降の収集日を集める。
  static WidgetPayload build(
    CollectionCalendar calendar,
    DateTime from, {
    int horizonDays = horizonDays,
  }) {
    final start = CollectionCalendar.dateOnly(from);
    final days = <WidgetDay>[];
    for (var offset = 0; offset < horizonDays; offset++) {
      final date = start.add(Duration(days: offset));
      final categories = calendar.categoriesOn(date);
      if (categories.isEmpty) continue;
      // 期限は分別ごとに違いうるが、いちばん遅いものを日の期限とする。
      // ひとつでもまだ出せるものがあれば、その日はまだ行ける日だから
      // （CollectionCalendar.canStillPutOut と同じ考え方）。
      final deadline = categories
          .map(calendar.area.depositDeadlineAt)
          .reduce(
            (a, b) => a.hour * 60 + a.minute >= b.hour * 60 + b.minute ? a : b,
          );
      days.add(
        WidgetDay(
          date: date,
          categoryIds: [for (final category in categories) category.id],
          deadlineHour: deadline.hour,
          deadlineMinute: deadline.minute,
        ),
      );
    }
    return WidgetPayload(
      areaLabel: calendar.area.label,
      days: days,
      generatedAt: from,
    );
  }
}

/// 収集のある1日。
class WidgetDay {
  const WidgetDay({
    required this.date,
    required this.categoryIds,
    required this.deadlineHour,
    required this.deadlineMinute,
  });

  final DateTime date;

  /// [GarbageCategory.id]。名前・色・アイコンはウィジェット側が持つ。
  /// 5区分は変わらないので、そこだけは二重に持っても食い違わない。
  final List<String> categoryIds;

  final int deadlineHour;
  final int deadlineMinute;

  Map<String, dynamic> toJson() => {
    // 時刻を持たない日付として扱いたいので、YYYY-MM-DD で書く。
    // タイムゾーン付きにすると、ウィジェット側で日付がずれうる。
    'date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'categories': categoryIds,
    'deadlineHour': deadlineHour,
    'deadlineMinute': deadlineMinute,
  };
}
