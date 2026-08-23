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

  _collation();
}

void _collation() {
  group('五十音順に比べる', () {
    /// [readings] がその順に並んでいることを確かめる。
    void inOrder(List<String> readings) {
      for (var i = 0; i + 1 < readings.length; i++) {
        expect(
          KanaCollation.compare(readings[i], readings[i + 1]),
          lessThan(0),
          reason: '${readings[i]} < ${readings[i + 1]}',
        );
      }
    }

    test('清音の並びで決まる', () {
      inOrder(['あしふきまっと', 'あぶら', 'あまい', 'あみど', 'あるばむ']);
    });

    test('濁点は清音に均してから比べる', () {
      // 「はんガー」が「はんカチ」より前に来るのは、3文字目の濁点ではなく
      // 4文字目（あ／ち）で決まるため。コードポイント順だと逆になる。
      inOrder(['はんがー', 'はんかち']);
      inOrder(['かんそうざい', 'かんでんち', 'かんねつし']);
    });

    test('清音・大文字が先。同じ音のときだけ効く', () {
      // 「くつした」と「くっしょん」は、つ／っの大小ではなく3文字目で決まる。
      inOrder(['くつした', 'くっしょん']);
      // 読みが同じところまで並ぶときだけ、大小と濁点を見る。
      expect(KanaCollation.compare('つ', 'っ'), lessThan(0));
      expect(KanaCollation.compare('か', 'が'), lessThan(0));
      expect(KanaCollation.compare('は', 'ば'), lessThan(0));
      expect(KanaCollation.compare('ば', 'ぱ'), lessThan(0));
    });

    test('長音符は直前の母音に開く', () {
      // 「こーひー」を開かないと「こんぽうざい」の後ろに落ちる。
      inOrder(['こーひーのびん', 'こんぽうざい']);
      inOrder(['えあこん', 'えーしーあだぷた', 'えきしょうてれび']);
      expect(KanaCollation.compare('こーひー', 'こおひい'), 0);
    });

    test('短いほうが先', () {
      inOrder(['ほん', 'ほんだな']);
      expect(KanaCollation.compare('いしょうけーす', 'いしょうけーす'), 0);
    });
  });
}
