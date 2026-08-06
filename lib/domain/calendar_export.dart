import 'collection_area.dart';
import 'collection_rule.dart';
import 'garbage_category.dart';

/// 収集日を、標準カレンダーに取り込める iCalendar（.ics）形式に書き出す。
///
/// 端末のカレンダーに直接書き込むのではなく、ファイルを作って共有シートに
/// 渡す方式にしている。カレンダーへのアクセス権限を求めずに済み、
/// 追加先のカレンダーも利用者が選べるため。
///
/// 日付ごとに個別のイベントを並べるのではなく、繰り返しルール（RRULE）で
/// 「毎週月・木」のように表す。イベント数が少なく、カレンダー側で
/// ずっと先まで表示できる。
class CalendarExport {
  const CalendarExport(this.area);

  final CollectionArea area;

  /// このアプリが作ったイベントだと分かるようにする識別子。
  static const _productId = '-//saitama-gomi-calendar//JP';

  /// 1日に複数の区分が重なる場合、区分ごとにイベントを分けず1件にまとめる。
  /// カレンダーが埋まって使いにくくなるのを避けるため。
  ///
  /// ただし区分ごとに収集の頻度（毎週／第2・第4など）が違うので、
  /// 「同じ曜日・同じ頻度」の組をまとめる単位にする。
  List<_EventGroup> _groups() {
    final byKey = <String, _EventGroup>{};
    for (final category in GarbageCategory.values) {
      for (final rule in area.rulesFor(category)) {
        final key = _ruleKey(rule);
        final group = byKey.putIfAbsent(
          key,
          () => _EventGroup(rule: rule, categories: []),
        );
        if (!group.categories.contains(category)) {
          group.categories.add(category);
        }
      }
    }
    final groups = byKey.values.toList();
    // 出力順を安定させる（曜日順→週指定の有無）。
    groups.sort((a, b) {
      final byWeekday = a.rule.weekday.compareTo(b.rule.weekday);
      if (byWeekday != 0) return byWeekday;
      return _ruleKey(a.rule).compareTo(_ruleKey(b.rule));
    });
    return groups;
  }

  static String _ruleKey(CollectionRule rule) {
    final weeks = rule.weeksOfMonth;
    if (weeks == null) return '${rule.weekday}:weekly';
    final sorted = weeks.toList()..sort();
    return '${rule.weekday}:${sorted.join(',')}';
  }

  /// [from]以降で、[rule]に最初に当てはまる日。
  static DateTime _firstDate(CollectionRule rule, DateTime from) {
    var date = DateTime(from.year, from.month, from.day);
    // 曜日と週指定の両方に当てはまる日は、たかだか5週間以内に必ず来る。
    for (var i = 0; i < 40; i++) {
      if (rule.matches(date)) return date;
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  static const _icalWeekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// iCalendar形式の文字列を作る。
  ///
  /// [from]は繰り返しの開始日。[now]はファイルの作成日時（DTSTAMP）で、
  /// テストから固定するために引数にしている。
  String build({required DateTime from, DateTime? now}) {
    final stamp = _formatUtc(now ?? DateTime.now());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$_productId',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escape('ごみ収集日（${area.ward} ${area.name}）')}',
    ];

    for (final group in _groups()) {
      final start = _firstDate(group.rule, from);
      final summary = group.categories.map((c) => c.label).join('・');
      final deadline = area.depositDeadline(group.categories.first);

      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${_uid(group, start)}',
        'DTSTAMP:$stamp',
        // 終日イベント。時刻付きにすると予定表の時間帯を占有してしまう。
        'DTSTART;VALUE=DATE:${_formatDate(start)}',
        'DTEND;VALUE=DATE:${_formatDate(start.add(const Duration(days: 1)))}',
        'RRULE:${_rrule(group.rule)}',
        'SUMMARY:${_escape(summary)}',
        'DESCRIPTION:${_escape('朝$deadlineまでに出してください')}',
        'TRANSP:TRANSPARENT',
        'END:VEVENT',
      ]);
    }

    lines.add('END:VCALENDAR');
    // iCalendarの改行はCRLF。
    return '${lines.join('\r\n')}\r\n';
  }

  String _uid(_EventGroup group, DateTime start) {
    final key = _ruleKey(group.rule).replaceAll(RegExp(r'[^0-9a-zA-Z]'), '-');
    return '$key-${_formatDate(start)}@saitama-gomi-calendar';
  }

  static String _rrule(CollectionRule rule) {
    final day = _icalWeekdays[rule.weekday - 1];
    final weeks = rule.weeksOfMonth;
    if (weeks == null) return 'FREQ=WEEKLY;BYDAY=$day';
    // 「第2・第4木曜」は、月ごとの繰り返しで週番号を指定して表す。
    final sorted = weeks.toList()..sort();
    final byDay = sorted.map((w) => '$w$day').join(',');
    return 'FREQ=MONTHLY;BYDAY=$byDay';
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatUtc(DateTime dateTime) {
    final utc = dateTime.toUtc();
    return '${_formatDate(utc)}T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  /// iCalendarのテキスト値では、カンマ・セミコロン・バックスラッシュ・改行を
  /// エスケープする必要がある（RFC 5545 3.3.11）。
  static String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');
}

class _EventGroup {
  _EventGroup({required this.rule, required this.categories});

  final CollectionRule rule;
  final List<GarbageCategory> categories;
}
