import 'garbage_category.dart';

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
  final String note;

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

  /// 検索用に正規化した名前。
  ///
  /// 早見表の品目名には「（プラスチック製）」のような補足や、中黒・波ダッシュが
  /// 混ざる。利用者が「ペットボトル」と打ったときに「ペットボトル」が出ないと
  /// 困るので、記号を落として比較できるようにしておく。
  String get searchKey => _normalize(name);

  bool matches(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return true;
    return searchKey.contains(q) || _normalize(categoryLabel).contains(q);
  }

  static String _normalize(String value) => value
      .replaceAll(RegExp(r'[（）()【】\[\]・、。／/･]'), '')
      .replaceAll(RegExp(r'[〜~ー－―\-\s]'), '')
      .toLowerCase();

  factory WasteItem.fromJson(Map<String, dynamic> json) => WasteItem(
    name: json['name'] as String,
    kanaHead: json['kanaHead'] as String? ?? '',
    categoryId: json['category'] as String,
    categoryLabel: json['categoryLabel'] as String,
    note: json['note'] as String? ?? '',
  );
}
