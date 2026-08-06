import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/collection_area.dart';

/// アセットに同梱した地区データ。
///
/// `areas` は町丁目から確定できる地区の一覧、`presets` は曜日を入力するときの
/// 出発点になる雛形。現時点で同梱しているのは雛形だけで、`areas` は空になっている。
/// 市の収集日カレンダーの地区表を取り込めるようになったら `areas` を埋めれば、
/// アプリ側のコードを変えずに「地区を選ぶ」導線がそのまま使える。
class AreaCatalog {
  const AreaCatalog({
    required this.areas,
    required this.presets,
    required this.disclaimer,
    required this.source,
  });

  /// 確定した収集地区。空でありうる。
  final List<CollectionArea> areas;

  /// 曜日入力の雛形。
  final List<CollectionArea> presets;

  /// データの確からしさについての但し書き。設定画面に出す。
  final String disclaimer;

  /// 出典URL。
  final String source;

  List<CollectionArea> areasInWard(String ward) =>
      areas.where((area) => area.ward == ward).toList();

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
    return AreaCatalog(
      areas: parse('areas'),
      presets: parse('presets'),
      disclaimer: json['disclaimer'] as String? ?? '',
      source: json['source'] as String? ?? '',
    );
  }
}
