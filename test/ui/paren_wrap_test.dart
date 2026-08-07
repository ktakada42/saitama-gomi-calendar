import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/ui/paren_wrap.dart';

const _wordJoiner = '⁠';

void main() {
  group('文字列の加工', () {
    test('括弧の中に切れ目を作らない', () {
      expect(
        keepParenthesesTogether('紙パック（銀色）'),
        ['紙パック（', '銀', '色', '）'].join(_wordJoiner),
      );
    });

    test('括弧の外はそのまま', () {
      // 括弧の手前では切れてよいので、つなぎを入れない。
      expect(keepParenthesesTogether('紙パック'), '紙パック');
      expect(keepParenthesesTogether(''), '');
    });

    test('括弧が閉じていなくても壊れない', () {
      // 市の資料の取り込みなので、閉じ忘れが混じっても表示は続けたい。
      final result = keepParenthesesTogether('紙パック（銀色');
      expect(result.replaceAll(_wordJoiner, ''), '紙パック（銀色');
    });

    test('印を外すと元に戻る', () {
      for (final text in [
        '飲料の紙パック（中が銀色アルミのもの）',
        '西大宮1〜3丁目（旧指扇地区を除く）',
        '中身の見える袋（透明・半透明）に入れて出す。',
        '括弧のない文字列',
      ]) {
        expect(keepParenthesesTogether(text).replaceAll(_wordJoiner, ''), text);
      }
    });
  });

  group('狭い画面での折り返し', () {
    setUpAll(() async {
      final loader = FontLoader('Noto Sans JP')
        ..addFont(
          File(
            'assets/fonts/NotoSansJP-Variable.ttf',
          ).readAsBytes().then((b) => ByteData.view(b.buffer)),
        );
      await loader.load();
    });

    /// [text] を幅[width]で描いたときの各行。
    List<String> linesOf(String text, double width) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontFamily: 'Noto Sans JP', fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      return painter
          .computeLineMetrics()
          .map(
            (line) => text
                .substring(
                  painter.getPositionForOffset(Offset(0, line.baseline)).offset,
                  painter
                      .getPositionForOffset(Offset(width, line.baseline))
                      .offset,
                )
                .replaceAll(_wordJoiner, ''),
          )
          .toList();
    }

    test('括弧の途中ではなく、括弧の手前で折り返す', () {
      // iPhone SE 第2世代の一覧で、品目名に使える幅のあたり。
      const width = 240.0;
      const name = '飲料の紙パック（中が銀色アルミのもの）';

      // 加工しないと括弧の中で切れる。
      expect(linesOf(name, width).first, '飲料の紙パック（中が銀色アルミ');

      // 加工すると括弧ごと次の行へ回る。
      expect(linesOf(keepParenthesesTogether(name), width), [
        '飲料の紙パック',
        '（中が銀色アルミのもの）',
      ]);
    });

    test('括弧の中だけで1行に収まらないときは、これまでどおり中で折り返す', () {
      const width = 240.0;
      const text = 'ためし（これは括弧の中だけでは一行にとても収まらない長い但し書きです）';

      final lines = linesOf(keepParenthesesTogether(text), width);
      // どこかで切らないと表示できないので、溢れさせずに折り返す。
      expect(lines.length, greaterThan(2));
      expect(lines.join(), text);
    });
  });
}
