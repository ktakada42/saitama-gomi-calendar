import 'paren_wrap.dart';

/// 出し方の注意点を、画面に出す形に整える。
///
/// 早見表は紙の表なので、1つの欄に複数の但し書きが詰め込まれている。
/// 「※」はその区切りとして使われているが、抽出すると前の文と地続きになり
/// 「固めてから※液体のものは、排出禁止」のように読みにくい。
/// 「※」の手前で改行して、文ごとに分ける。
String formatNote(String note) => keepParenthesesTogether(splitNoteLines(note));

/// 「※」の手前で改行を入れる。先頭の「※」はそのまま。
String splitNoteLines(String note) {
  final buffer = StringBuffer();
  for (var i = 0; i < note.length; i++) {
    final char = note[i];
    if (char == '※' && i > 0) buffer.write('\n');
    buffer.write(char);
  }
  return buffer.toString();
}
