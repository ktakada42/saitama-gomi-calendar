import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/date_label.dart';

void main() {
  final today = DateTime(2026, 8, 6);

  test('monthDay は曜日つき', () {
    expect(DateLabel.monthDay(DateTime(2026, 8, 7)), '8月7日(金)');
  });

  test('full は年つき', () {
    expect(DateLabel.full(DateTime(2026, 8, 7)), '2026年8月7日(金)');
  });

  test('relative は3日先まで', () {
    expect(DateLabel.relative(today, today), '今日');
    expect(DateLabel.relative(DateTime(2026, 8, 7), today), '明日');
    expect(DateLabel.relative(DateTime(2026, 8, 8), today), 'あさって');
    expect(DateLabel.relative(DateTime(2026, 8, 9), today), isNull);
  });

  test('relative は時刻の影響を受けない', () {
    expect(
      DateLabel.relative(DateTime(2026, 8, 7, 1), DateTime(2026, 8, 6, 23)),
      '明日',
    );
  });

  test('過去の日付には相対表記をつけない', () {
    expect(DateLabel.relative(DateTime(2026, 8, 5), today), isNull);
  });

  test('headline は相対表記があれば前につける', () {
    expect(DateLabel.headline(DateTime(2026, 8, 7), today), '明日 8月7日(金)');
    expect(DateLabel.headline(DateTime(2026, 8, 20), today), '8月20日(木)');
  });

  test('狭いところでは相対表記と日付を別の行にする', () {
    // 「あさって 8月9日(日)」は1行に収まらず、成り行きに任せると
    // 日付の途中で切れる。切るなら相対表記との境目で切る。
    expect(
      DateLabel.headlineWrapped(DateTime(2026, 8, 8), today),
      'あさって\n8月8日(土)',
    );
    // 相対表記が無いときは1行のまま。
    expect(DateLabel.headlineWrapped(DateTime(2026, 8, 20), today), '8月20日(木)');
  });
}
