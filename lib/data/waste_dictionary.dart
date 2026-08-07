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

  static Future<WasteDictionary> load() async {
    final raw = await rootBundle.loadString('assets/data/dictionary.json');
    return WasteDictionary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory WasteDictionary.fromJson(Map<String, dynamic> json) =>
      WasteDictionary(
        items: [
          for (final item in (json['items'] as List<dynamic>? ?? const []))
            WasteItem.fromJson(item as Map<String, dynamic>),
        ],
        source: json['source'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
      );

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
