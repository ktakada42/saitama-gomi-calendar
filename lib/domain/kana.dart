/// 五十音の「行」。
///
/// 分別の一覧はこの行ごとにまとめる。市の早見表はかな1文字ごとに
/// 索引を付けているが、43文字を索引に並べると1文字あたりが小さくなりすぎて
/// 狙って押せない。iOSの連絡先と同じく行でまとめると索引は10個で済み、
/// なぞって送れるようになる。
class KanaRow {
  const KanaRow(this.head, this.kana);

  /// 行の名前になるかな。「あ」「か」など。
  final String head;

  /// その行に属するかな。
  final String kana;

  /// 一覧の見出しに出す文字列。索引の「あ」と見分けられるよう行を付ける。
  String get label => '$head行';

  static const values = [
    KanaRow('あ', 'あいうえお'),
    KanaRow('か', 'かきくけこがぎぐげご'),
    KanaRow('さ', 'さしすせそざじずぜぞ'),
    KanaRow('た', 'たちつてとだぢづでど'),
    KanaRow('な', 'なにぬねの'),
    KanaRow('は', 'はひふへほばびぶべぼぱぴぷぺぽ'),
    KanaRow('ま', 'まみむめも'),
    KanaRow('や', 'やゆよ'),
    KanaRow('ら', 'らりるれろ'),
    KanaRow('わ', 'わをん'),
  ];

  /// [kana] が属する行の頭文字。見つからなければ null。
  ///
  /// 濁音・半濁音も清音と同じ行として扱う。五十音順の並びでも
  /// 「か」と「が」は同じところに来るため。
  static String? headOf(String kana) {
    // 空文字はどの行の文字列にも「含まれる」と判定されてしまうので先に弾く。
    if (kana.isEmpty) return null;
    for (final row in values) {
      if (row.kana.contains(kana)) return row.head;
    }
    return null;
  }
}
