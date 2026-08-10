import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/waste_item.dart';

/// アセットに同梱した分別早見表。
///
/// さいたま市が配布するPDFマニュアルの「ごみの分別早見表」から機械的に生成した
/// もの（`scripts/extract_waste_dictionary.py`）。市の公式サイトの分別辞典ページは
/// 第三者ベンダーの非公開APIで動いているため、そちらは経由していない。
class WasteDictionary {
  const WasteDictionary({
    required this.items,
    required this.source,
    required this.sourceUrl,
  });

  final List<WasteItem> items;

  /// 出典の名前。
  final String source;

  /// 出典のURL。
  final String sourceUrl;

  /// 早見表と、図解ページからの補いを合わせて読む。
  ///
  /// 早見表（`dictionary.json`）は抽出スクリプトの出力そのままにしておく。
  /// 補い（`dictionary_extra.json`）を混ぜて書き戻すと、市が資料を更新して
  /// 抽出をやり直したときに、手で足したぶんが消える。
  static Future<WasteDictionary> load() async {
    final raw = await rootBundle.loadString('assets/data/dictionary.json');
    final extra = await rootBundle.loadString(
      'assets/data/dictionary_extra.json',
    );
    final keywords = await rootBundle.loadString(
      'assets/data/dictionary_keywords.json',
    );
    return WasteDictionary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      extra: jsonDecode(extra) as Map<String, dynamic>,
      keywords: jsonDecode(keywords) as Map<String, dynamic>,
    );
  }

  factory WasteDictionary.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? extra,
    Map<String, dynamic>? keywords,
  }) {
    final byName = (keywords?['keywords'] as Map<String, dynamic>?) ?? const {};
    final items = [
      for (final source in [json['items'], extra?['items']])
        for (final item in (source as List<dynamic>? ?? const []))
          WasteItem.fromJson({
            ...item as Map<String, dynamic>,
            // 言い換えは別ファイルで持つ。品目の出どころ（早見表／図解ページ）と
            // 分けておかないと、市の資料が変わったときに突き合わせられない。
            'keywords': byName[item['name']] ?? const <dynamic>[],
          }),
    ];
    // 五十音の索引が飛ばないよう、行の見出しで並べ直す。
    // 補いを後ろに繋いだままだと、「わ」の次に「い」が来る。
    items.sort((a, b) => _kanaOrder(a.kanaHead) - _kanaOrder(b.kanaHead));
    return WasteDictionary(
      items: items,
      source: json['source'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
    );
  }

  /// 五十音の並び順。冊子の並びに合わせる。
  static int _kanaOrder(String head) {
    const order =
        'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほ'
        'まみむめもやゆよらりるれろわをん';
    final index = order.indexOf(head);
    // 知らない見出しは末尾に置く。落とすと品目ごと消える。
    return index < 0 ? order.length : index;
  }

  /// [query]に当てはまる品目。空文字なら全件。
  ///
  /// 前方一致を先に出す。「ペット」で探したときに「ペットボトル」より先に
  /// 「カーペット」が出ると探しにくいため。
  List<WasteItem> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return items;

    final matched = items.where((item) => item.matches(trimmed)).toList();
    final normalized = WasteItem(
      name: trimmed,
      kanaHead: '',
      categoryId: '',
      categoryLabel: '',
      note: '',
    ).searchKey;

    matched.sort((a, b) {
      final aPrefix = a.searchKey.startsWith(normalized);
      final bPrefix = b.searchKey.startsWith(normalized);
      if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return matched;
  }
}
