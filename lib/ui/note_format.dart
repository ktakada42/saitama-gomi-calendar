import 'paren_wrap.dart';

/// 出し方の注意点を、画面に出す形に整える。
///
/// 早見表は紙の表なので、1つの欄に複数の但し書きが詰め込まれている。
/// 但し書きの切れ目には、抽出のときに改行を入れてある
/// （`scripts/extract_waste_dictionary.py`の`join_note`）。
///
/// 「※」も区切りとして使われている。手で起こした注意点（図解ページからの
/// 補いなど）には改行が入っていないことがあるので、「※」の手前でも改行する。
String formatNote(String note) => keepParenthesesTogether(splitNoteLines(note));

/// 「※」の手前で改行を入れる。先頭の「※」と、すでに改行してある「※」はそのまま。
String splitNoteLines(String note) {
  final buffer = StringBuffer();
  for (var i = 0; i < note.length; i++) {
    final char = note[i];
    if (char == '※' && i > 0 && note[i - 1] != '\n') buffer.write('\n');
    buffer.write(char);
  }
  return buffer.toString();
}
