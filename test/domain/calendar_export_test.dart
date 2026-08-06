import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/calendar_export.dart';
import 'package:saitama_gomi/domain/collection_area.dart';
import 'package:saitama_gomi/domain/collection_rule.dart';
import 'package:saitama_gomi/domain/garbage_category.dart';

/// もえるごみ 月・木／もえないごみ・資源物2類 第2火／資源物1類 水 の地区。
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
    GarbageCategory.recyclable2: [
      CollectionRule.monthly(DateTime.tuesday, {2}),
    ],
    GarbageCategory.recyclable1: [CollectionRule.weekly(DateTime.wednesday)],
  },
);

/// 2026年8月7日は金曜日。
final _from = DateTime(2026, 8, 7);
final _now = DateTime.utc(2026, 8, 7, 12);

String _build([CollectionArea area = _area]) =>
    CalendarExport(area).build(from: _from, now: _now);

void main() {
  test('iCalendarの体裁になっている', () {
    final ics = _build();

    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics, contains('VERSION:2.0'));
    // 行の区切りはCRLF（RFC 5545）。
    expect(ics.contains('\n') && !ics.contains('\r\n\r\n'), isTrue);
  });

  test('毎週の区分は週の繰り返しになる', () {
    final ics = _build();

    // もえるごみは月・木なので、それぞれ週次のルールになる。
    expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=MO'));
    expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=TH'));
  });

  test('第◯週だけの区分は月の繰り返しになる', () {
    final ics = _build();

    // 第2火曜は「毎月の第2火曜」として表す。
    expect(ics, contains('RRULE:FREQ=MONTHLY;BYDAY=2TU'));
  });

  test('同じ曜日・同じ頻度の区分は1つのイベントにまとめる', () {
    final ics = _build();

    // もえないごみと資源物2類はどちらも第2火曜なので、
    // 別々のイベントにせず1件にまとめる。
    expect(ics, contains('SUMMARY:もえないごみ・資源物2類'));
    // 第2火曜のイベントは1件だけ。
    expect('FREQ=MONTHLY;BYDAY=2TU'.allMatches(ics).length, 1);
  });

  test('終日イベントになっている', () {
    final ics = _build();

    // 時刻付きにすると予定表の時間帯を占有してしまうので、日付だけを持たせる。
    expect(ics, contains('DTSTART;VALUE=DATE:'));
    expect(ics, isNot(contains('DTSTART:')));
    // 予定ありとして扱われないようにする。
    expect(ics, contains('TRANSP:TRANSPARENT'));
  });

  test('開始日は指定日以降で最初に当てはまる日になる', () {
    final ics = _build();

    // 2026年8月7日(金)以降で最初の月曜は10日。
    expect(ics, contains('DTSTART;VALUE=DATE:20260810'));
    // 最初の木曜は13日。
    expect(ics, contains('DTSTART;VALUE=DATE:20260813'));
    // 最初の第2火曜は8月11日。
    expect(ics, contains('DTSTART;VALUE=DATE:20260811'));
  });

  test('出す期限を説明に入れる', () {
    final ics = _build();

    expect(ics, contains('朝8:30までに出してください'));
  });

  test('早朝収集地区では期限が5:30になる', () {
    final ics = _build(_area.copyWith(earlyMorning: true));

    expect(ics, contains('朝5:30までに出してください'));
  });

  test('カレンダー名に区と地区名が入る', () {
    final ics = _build();

    expect(ics, contains('X-WR-CALNAME:ごみ収集日（浦和区 テスト地区）'));
  });

  test('区切り文字はエスケープする', () {
    final ics = _build(_area.copyWith(name: 'テスト,地区;その1'));

    // カンマ・セミコロンはそのまま書くと値の区切りとして解釈されてしまう。
    expect(ics, contains(r'テスト\,地区\;その1'));
  });

  test('収集曜日が未設定ならイベントを作らない', () {
    final ics = _build(_area.copyWith(rules: const {}));

    expect(ics, isNot(contains('BEGIN:VEVENT')));
    // 空のカレンダーとしては成立している。
    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
  });

  test('同じ設定なら毎回同じUIDになる', () {
    final first = _build();
    final second = _build();

    expect(first, second);
  });
}
