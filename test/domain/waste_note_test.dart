import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/waste_note.dart';

void main() {
  test('印から説明を引ける', () {
    final marks = NoteMark.resolve(['star2', 'page9']);

    expect(marks.map((m) => m.id), ['star2', 'page9']);
    // 冊子の脚注を、冊子を持たない人にも通じる言葉にしてある。
    expect(marks.first.description, contains('90cm以上2m未満'));
  });

  test('知らない印は落とす', () {
    // 市が印を増やしても、古いアプリが空欄を出したり落ちたりしないように。
    expect(NoteMark.resolve(['star2', 'star99']).map((m) => m.id), ['star2']);
    expect(NoteMark.resolve([]), isEmpty);
  });

  test('説明はどれも空でない', () {
    for (final id in [
      'star1',
      'star2',
      'star3',
      'star4',
      'star5',
      'star6',
      'page7',
      'page9',
      'page10',
      'page11',
      'page12',
    ]) {
      final mark = NoteMark.resolve([id]).single;
      expect(mark.title, isNotEmpty, reason: id);
      expect(mark.description, isNotEmpty, reason: id);
      // 印そのものを説明に使ったら意味がない。
      expect(mark.description, isNot(contains('★')), reason: id);
    }
  });
}
