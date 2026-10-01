import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/kana.dart';
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
    this.changeSource = '',
    this.changeSourceUrl = '',
  });

  final List<WasteItem> items;

  /// 出典の名前。
  final String source;

  /// 出典のURL。
  final String sourceUrl;

  /// 分別の変更を反映するのに使った資料の名前。反映していなければ空。
  final String changeSource;

  /// その資料のURL。
  final String changeSourceUrl;

  /// 早見表と、図解ページからの補い、分別の変更を合わせて読む。
  ///
  /// 早見表（`dictionary.json`）は抽出スクリプトの出力そのままにしておく。
  /// 補い（`dictionary_extra.json`）を混ぜて書き戻すと、市が資料を更新して
  /// 抽出をやり直したときに、手で足したぶんが消える。
  ///
  /// 令和8年10月のプラスチックの分別変更（`dictionary_plastic2026.json`）も
  /// 同じ理由で分けてある。早見表は4月に配られた時点の区分のままで、
  /// 市が後からリーフレットで名指しした品目だけを、読むときに上書きする。
  static Future<WasteDictionary> load() async {
    final raw = await rootBundle.loadString('assets/data/dictionary.json');
    final extra = await rootBundle.loadString(
      'assets/data/dictionary_extra.json',
    );
    final changes = await rootBundle.loadString(
      'assets/data/dictionary_plastic2026.json',
    );
    final keywords = await rootBundle.loadString(
      'assets/data/dictionary_keywords.json',
    );
    final kana = await rootBundle.loadString(
      'assets/data/dictionary_kana.json',
    );
    return WasteDictionary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      extra: jsonDecode(extra) as Map<String, dynamic>,
      changes: jsonDecode(changes) as Map<String, dynamic>,
      keywords: jsonDecode(keywords) as Map<String, dynamic>,
      kana: jsonDecode(kana) as Map<String, dynamic>,
    );
  }

  factory WasteDictionary.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? extra,
    Map<String, dynamic>? changes,
    Map<String, dynamic>? keywords,
    Map<String, dynamic>? kana,
  }) {
    final byName = (keywords?['keywords'] as Map<String, dynamic>?) ?? const {};
    final kanaByName = (kana?['kana'] as Map<String, dynamic>?) ?? const {};
    // 名指しで上書きする品目。書いてある項目（区分・注意点）だけを差し替え、
    // 書いていない項目は早見表のまま残す。
    final overrides = {
      for (final override
          in (changes?['overrides'] as List<dynamic>? ?? const []))
        (override as Map<String, dynamic>)['name']: override,
    };
    final items = [
      for (final source in [json['items'], extra?['items'], changes?['items']])
        for (final item in (source as List<dynamic>? ?? const []))
          WasteItem.fromJson({
            // 早見表の品目の読みは別ファイルで持つ。dictionary.jsonは抽出
            // スクリプトの出力そのままなので、手で足した読みをそちらに
            // 書くと、市が資料を更新して抽出をやり直したときに消える。
            'kana': kanaByName[item['name']],
            ...item as Map<String, dynamic>,
            ...?overrides[item['name']],
            // 言い換えは別ファイルで持つ。品目の出どころ（早見表／図解ページ）と
            // 分けておかないと、市の資料が変わったときに突き合わせられない。
            'keywords': byName[item['name']] ?? const <dynamic>[],
          }),
    ];
    // 読みの五十音順に並べる。
    //
    // 行の見出し（市が付けたもの）を第1キーにして、行そのものは資料どおりに
    // 置く。読みを1つ書き間違えても品目が別の行へ飛ばないようにするため。
    // 同じ読みが並んだとき（「衣装ケース」とその括弧付き、「びん・かんの
    // フタ」のあり／なし）は資料の並び順を保つ。List.sortは安定ではない
    // ので、元の位置を最後のキーに添える。
    final order =
        [
          for (var i = 0; i < items.length; i++)
            (_kanaOrder(items[i].kanaHead), items[i].sortKana, i),
        ]..sort((a, b) {
          if (a.$1 != b.$1) return a.$1 - b.$1;
          final byKana = KanaCollation.compare(a.$2, b.$2);
          return byKana != 0 ? byKana : a.$3 - b.$3;
        });
    return WasteDictionary(
      items: [for (final (_, _, i) in order) items[i]],
      source: json['source'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      changeSource: changes?['source'] as String? ?? '',
      changeSourceUrl: changes?['sourceUrl'] as String? ?? '',
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
