/// 読みを五十音順に比べる。
///
/// 単純な文字列比較だとUnicodeのコードポイント順になり、濁音・半濁音が
/// 清音のずっと後ろに落ちる（「かんそうざい」と「かんでんち」が離れる）。
/// 冊子の並びに合わせて、まず清音の大文字に均した並びで比べ、そこが
/// 同じときだけ小書き・濁点の違いを見る。「はんガー」が「はんカチ」より
/// 前に来るのは、3文字目の濁点ではなく4文字目（あ／ち）で決まるため。
class KanaCollation {
  const KanaCollation._();

  static const _base =
      'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほ'
      'まみむめもやゆよらりるれろわをん';

  /// 小書きのかなと、その大文字。
  static const _small = {
    'ぁ': 'あ',
    'ぃ': 'い',
    'ぅ': 'う',
    'ぇ': 'え',
    'ぉ': 'お',
    'っ': 'つ',
    'ゃ': 'や',
    'ゅ': 'ゆ',
    'ょ': 'よ',
    'ゎ': 'わ',
  };

  /// 濁音・半濁音と、その清音。値は (清音, 濁点の段)。
  static const _voiced = {
    'が': ('か', 1),
    'ぎ': ('き', 1),
    'ぐ': ('く', 1),
    'げ': ('け', 1),
    'ご': ('こ', 1),
    'ざ': ('さ', 1),
    'じ': ('し', 1),
    'ず': ('す', 1),
    'ぜ': ('せ', 1),
    'ぞ': ('そ', 1),
    'だ': ('た', 1),
    'ぢ': ('ち', 1),
    'づ': ('つ', 1),
    'で': ('て', 1),
    'ど': ('と', 1),
    'ば': ('は', 1),
    'び': ('ひ', 1),
    'ぶ': ('ふ', 1),
    'べ': ('へ', 1),
    'ぼ': ('ほ', 1),
    'ぱ': ('は', 2),
    'ぴ': ('ひ', 2),
    'ぷ': ('ふ', 2),
    'ぺ': ('へ', 2),
    'ぽ': ('ほ', 2),
  };

  /// 行そのものが母音を持たないかなの、長音符を開いたときの音。
  static const _vowelOf = {
    'や': 'あ',
    'ゆ': 'う',
    'よ': 'お',
    'わ': 'あ',
    'を': 'お',
    'ん': 'ん',
  };

  /// [reading] を、比べるための (清音の並び, 小書き・濁点の並び) に分ける。
  ///
  /// 長音符「ー」は直前の音の母音に開く。「こーひーのびん」を「こおひい…」
  /// として扱わないと、「こんぽうざい」の後ろに落ちる。
  static (List<int>, List<int>) _key(String reading) {
    final primary = <int>[];
    final secondary = <int>[];
    String? previous;
    for (var char in reading.split('')) {
      if (char == 'ー') {
        if (previous == null) continue;
        char = _vowel(previous);
      }
      var small = 0;
      final unsmall = _small[char];
      if (unsmall != null) {
        char = unsmall;
        small = 1;
      }
      var voice = 0;
      final unvoiced = _voiced[char];
      if (unvoiced != null) {
        (char, voice) = unvoiced;
      }
      final index = _base.indexOf(char);
      if (index < 0) {
        // かな以外（数字など）は末尾へ。落とすと別の品目と読みが並んでしまう。
        primary.add(_base.length);
        secondary.add(0);
        continue;
      }
      primary.add(index);
      // 大文字が先、清音が先。
      secondary.add(small * 3 + voice);
      previous = char;
    }
    return (primary, secondary);
  }

  static String _vowel(String base) {
    final fixed = _vowelOf[base];
    if (fixed != null) return fixed;
    final index = _base.indexOf(base);
    if (index < 0) return base;
    return 'あいうえお'[index % 5];
  }

  /// [a] と [b] を五十音順で比べる。
  static int compare(String a, String b) {
    final (aPrimary, aSecondary) = _key(a);
    final (bPrimary, bSecondary) = _key(b);
    for (final (x, y) in [(aPrimary, bPrimary), (aSecondary, bSecondary)]) {
      for (var i = 0; i < x.length && i < y.length; i++) {
        if (x[i] != y[i]) return x[i] - y[i];
      }
      if (x.length != y.length) return x.length - y.length;
    }
    return 0;
  }
}

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
