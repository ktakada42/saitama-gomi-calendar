/// 括弧の中で行が折り返されないようにする。
///
/// 「飲料の紙パック（中が銀色アルミのもの）」のような名前は、狭い画面だと
/// 「飲料の紙パック（中が銀色アルミ／のもの）」と括弧の途中で切れる。
/// 括弧の中は前の語の言い換えや但し書きなので、ひとかたまりで読めた方が早い。
///
/// 括弧の中の文字どうしを`WORD JOINER`（U+2060）でつなぎ、そこで切れないように
/// する。すると行送りは括弧の手前まで戻り、括弧全体が次の行へ回る。
/// 括弧の中だけで1行に収まらないときは、従来どおり中で折り返す
/// （どこかで切らないと表示できないため）。
library;

/// 行を切らせない印。表示されず、幅も持たない。
const _wordJoiner = '⁠';

const _openBrackets = '（(「『［〔【〈《';
const _closeBrackets = '）)」』］〕】〉》';

/// [text] の括弧の中を、折り返しの起きないひとかたまりにする。
///
/// 入れ子は数えていない。分別早見表にも地区名にも入れ子の括弧は無く、
/// 数えたところで見え方は変わらないため。
String keepParenthesesTogether(String text) {
  if (text.isEmpty) return text;

  final buffer = StringBuffer();
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    final isOpen = _openBrackets.contains(char);
    final isClose = _closeBrackets.contains(char);

    // 開き括弧の手前では切れてよい。つなぎを入れるのは括弧の中だけ。
    if (depth > 0 && !isOpen) buffer.write(_wordJoiner);
    buffer.write(char);

    if (isOpen) {
      // 次の文字の手前でつなぎが入るので、開き括弧だけが行末に残ることはない。
      depth++;
    } else if (isClose && depth > 0) {
      depth--;
    }
  }
  return buffer.toString();
}
