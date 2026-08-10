import 'garbage_category.dart';
import 'waste_note.dart';

/// 分別早見表の1品目。
///
/// [GarbageCategory]（収集日を持つ5区分）に収まらない出し先もある。
/// 粗大ごみ・小型家電・電池回収ボックス・収集できないもの、がそれで、
/// 利用者が「これはどこに出すのか」を知りたいのはむしろそちらなので、
/// 5区分に丸めずそのまま持つ。
class WasteItem {
  const WasteItem({
    required this.name,
    required this.kanaHead,
    required this.categoryId,
    required this.categoryLabel,
    required this.note,
    this.markIds = const [],
    this.keywords = const [],
  });

  /// 品目名。「ペットボトル」「電気スタンド」など。
  final String name;

  /// 五十音の「行」を示すかな1文字。
  ///
  /// 市の早見表が付けているものをそのまま持つ。「石」「鏡」のように漢字だけの
  /// 品目でも、市がどの行に置いたかが分かるので、読みを推測せずに
  /// 五十音順の並びと索引を作れる。
  final String kanaHead;

  /// 出し先の識別子。5区分なら[GarbageCategory.id]と一致する。
  final String categoryId;

  /// 出し先の表示名。
  final String categoryLabel;

  /// 出し方の注意点。無い品目も多い。
  ///
  /// 早見表の「★2」「▶P9参照」といった印は含まない。冊子を前提にした
  /// 書き方で、そのまま出しても意味が通らないため、[markIds]に分けてある。
  final String note;

  /// 注意点に付いていた印のid。「star2」「page9」など。
  final List<String> markIds;

  /// 印の意味。知らない印は落とす。
  List<NoteMark> get marks => NoteMark.resolve(markIds);

  /// 一覧の行だけでは伝わらない事情を持っているか。
  bool get hasDetail => marks.isNotEmpty;

  /// 5区分のいずれかならその区分。粗大ごみなど収集日を持たない出し先なら null。
  GarbageCategory? get category => GarbageCategory.fromId(categoryId);

  /// ピルに収めるための短い出し先名。
  ///
  /// 「粗大ごみ・適正処理困難物」は12文字あり、一覧の右端に置くには長すぎる。
  /// 5区分は[GarbageCategory.shortLabel]をそのまま使い、それ以外だけ縮める。
  String get shortCategoryLabel {
    final category = this.category;
    if (category != null) return category.shortLabel;
    return switch (categoryId) {
      'oversized' => '粗大',
      'smallAppliance' => '小型家電',
      'battery' => '電池',
      'notAccepted' => '収集不可',
      _ => categoryLabel,
    };
  }

  /// 市の表記と、利用者が打つ言葉のずれを埋める言い換え。
  ///
  /// 市は「かん」「びん」「フタ」とかなで書くが、利用者は「缶」「瓶」「ふた」
  /// と打つ。品目を足しても、この対応が無いと引けない。
  /// 決まっている言い換えは、推測させる前にここで確実に当てる。
  final List<String> keywords;

  /// 検索用に正規化した名前。
  ///
  /// 早見表の品目名には「（プラスチック製）」のような補足や、中黒・波ダッシュが
  /// 混ざる。利用者が「ペットボトル」と打ったときに「ペットボトル」が出ないと
  /// 困るので、記号を落として比較できるようにしておく。
  String get searchKey => _normalize(name);

  /// 括弧の補足を落とした主要部。
  ///
  /// 「新聞紙（折込チラシ含）」の主要部は「新聞紙」。利用者が「古い新聞紙」と
  /// 打ったとき、括弧の中まで含めた名前では入力に収まらず、0件になる。
  String get _baseKey =>
      _normalize(name.replaceAll(RegExp(r'[（(][^）)]*[）)]'), ''));

  bool matches(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return true;
    if (searchKey.contains(q) || _normalize(categoryLabel).contains(q)) {
      return true;
    }
    if (keywords.any((word) => _normalize(word).contains(q))) return true;

    // 入力のほうが品目名を含む場合も拾う。
    //
    // 利用者は品目名だけを打つとは限らない。「こわれた電球」「金属の
    // フライパン」のように、状態や材質を添えて打つ。前方の一致だけを
    // 見ていると、いちばん困っている人が0件になる。
    //
    // 1文字の名前（「石」「土」）は、長い入力にたまたま含まれることが
    // 多いので除く。
    if (searchKey.length >= 2 && q.contains(searchKey)) return true;
    if (_baseKey.length >= 2 && q.contains(_baseKey)) return true;
    return keywords.any((word) {
      final normalized = _normalize(word);
      return normalized.length >= 2 && q.contains(normalized);
    });
  }

  static String _normalize(String value) => _foldKatakana(
    value
        .replaceAll(RegExp(r'[（）()【】\[\]・、。／/･]'), '')
        .replaceAll(RegExp(r'[〜~ー－―\-\s]'), '')
        .toLowerCase(),
  );

  /// カタカナをひらがなに寄せる。
  ///
  /// 市は「生ごみ」、利用者は「生ゴミ」と打つ。どちらで打っても同じ品目に
  /// 当たるようにする。
  static String _foldKatakana(String value) {
    final buffer = StringBuffer();
    for (final code in value.runes) {
      // 「ァ」〜「ヶ」を、同じ並びのひらがなへ移す。
      final isKatakana = code >= 0x30A1 && code <= 0x30F6;
      buffer.writeCharCode(isKatakana ? code - 0x60 : code);
    }
    return buffer.toString();
  }

  factory WasteItem.fromJson(Map<String, dynamic> json) => WasteItem(
    name: json['name'] as String,
    kanaHead: json['kanaHead'] as String? ?? '',
    categoryId: json['category'] as String,
    categoryLabel: json['categoryLabel'] as String,
    note: json['note'] as String? ?? '',
    keywords: [
      for (final word in (json['keywords'] as List<dynamic>? ?? const []))
        word as String,
    ],
    markIds: [
      for (final mark in (json['marks'] as List<dynamic>? ?? const []))
        mark as String,
    ],
  );
}
