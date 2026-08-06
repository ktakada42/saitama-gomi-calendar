import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/collection_area.dart';

/// アセットに同梱した地区データ。
///
/// `areas` は町丁目から確定できる地区の一覧、`presets` は曜日を入力するときの
/// 出発点になる雛形（地区が見つからない代替経路でのみ使う）。`postalAreas` は
/// 郵便番号から`areas`を絞り込むための補助インデックス。
class AreaCatalog {
  const AreaCatalog({
    required this.areas,
    required this.presets,
    required this.disclaimer,
    required this.source,
    required this.postalAreas,
  });

  /// 確定した収集地区。
  final List<CollectionArea> areas;

  /// 曜日入力の雛形。
  final List<CollectionArea> presets;

  /// データの確からしさについての但し書き。設定画面に出す。
  final String disclaimer;

  /// 出典URL。
  final String source;

  /// 郵便番号（ハイフン無し7桁）→ 該当しうる[areas]の`id`一覧。
  ///
  /// 1つの郵便番号が複数の地区にまたがることが実際にあるため（同じ郵便番号の
  /// 範囲内で収集パターンが分かれている場合）、必ずしも1件には絞れない。
  final Map<String, List<String>> postalAreas;

  List<CollectionArea> areasInWard(String ward) =>
      areas.where((area) => area.ward == ward).toList();

  /// [rawPostalCode]（ハイフンや空白が混ざっていてもよい）から特定できる地区の候補。
  ///
  /// 郵便番号はこの検索にだけ使い、呼び出し側でも保存しないこと
  /// （[requirements.md](../../docs/requirements.md) 4.1節）。
  /// 該当が無ければ空リストを返す。
  List<CollectionArea> areasForPostalCode(String rawPostalCode) {
    final digits = rawPostalCode.replaceAll(RegExp(r'[^0-9]'), '');
    final ids = postalAreas[digits];
    if (ids == null) return const [];
    return [
      for (final id in ids)
        for (final area in areas)
          if (area.id == id) area,
    ];
  }

  static const assetPath = 'assets/data/areas.json';

  static Future<AreaCatalog> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return AreaCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory AreaCatalog.fromJson(Map<String, dynamic> json) {
    List<CollectionArea> parse(String key) => [
      for (final entry in (json[key] as List<dynamic>? ?? const []))
        CollectionArea.fromJson(entry as Map<String, dynamic>),
    ];
    final rawPostalAreas =
        (json['postalAreas'] as Map<String, dynamic>?) ?? const {};
    return AreaCatalog(
      areas: parse('areas'),
      presets: parse('presets'),
      disclaimer: json['disclaimer'] as String? ?? '',
      source: json['source'] as String? ?? '',
      postalAreas: {
        for (final entry in rawPostalAreas.entries)
          entry.key: (entry.value as List<dynamic>).cast<String>(),
      },
    );
  }
}
