import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/kana.dart';

void main() {
  test('かなから行を引ける', () {
    expect(KanaRow.headOf('あ'), 'あ');
    expect(KanaRow.headOf('お'), 'あ');
    expect(KanaRow.headOf('こ'), 'か');
    expect(KanaRow.headOf('ん'), 'わ');
  });

  test('濁音・半濁音も清音と同じ行になる', () {
    // 五十音順の並びでも「か」と「が」は同じところに来る。
    expect(KanaRow.headOf('が'), 'か');
    expect(KanaRow.headOf('じ'), 'さ');
    expect(KanaRow.headOf('ぱ'), 'は');
  });

  test('かなでないものは行を持たない', () {
    expect(KanaRow.headOf('A'), isNull);
    expect(KanaRow.headOf(''), isNull);
  });

  test('十行そろっていて、かなの重複がない', () {
    expect(KanaRow.values, hasLength(10));
    final all = KanaRow.values.expand((r) => r.kana.split('')).toList();
    expect(all.toSet(), hasLength(all.length));
    // 行の頭文字は、その行のかなの先頭。
    for (final row in KanaRow.values) {
      expect(row.kana[0], row.head);
    }
  });
}
