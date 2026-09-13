import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/sorting_change.dart';

void main() {
  final change = SortingChange.plastic2026;

  test('切り替え日を境に伝えるかどうかが変わる', () {
    // 前日までは出さない。まだ表示している分別が正しい。
    expect(change.hasStarted(DateTime(2026, 9, 30)), isFalse);
    // 当日から出す。
    expect(change.hasStarted(DateTime(2026, 10, 1)), isTrue);
    expect(change.hasStarted(DateTime(2027, 3, 1)), isTrue);
  });

  test('伝えるべき変更を日付から引ける', () {
    expect(SortingChange.current(DateTime(2026, 9, 30)), isNull);
    expect(SortingChange.current(DateTime(2026, 10, 1)), change);
  });

  test('表示に使う文言がそろっている', () {
    expect(change.title, isNotEmpty);
    expect(change.description, isNotEmpty);
    // 古いと言われるだけでは行き先がない。品目ごとの分別はまだ市から
    // 出ていないので、手元の品物を自分で判断できる条件を渡す。
    expect(change.conditions, hasLength(3));
    expect(change.conditions.any((c) => c.isEmpty), isFalse);
  });

  test('リンク先は変更を告知しているページ', () {
    // 分別一覧のページ（p005300）ではない。そちらを開いても
    // 何がどう変わったのかは書かれていない。
    expect(change.noticeUrl, contains('p127278'));
  });
}
