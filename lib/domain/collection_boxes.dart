import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 小型家電・電池の回収ボックス。
///
/// 早見表は「回収ボックスへ」としか書いていない。どこにあるのかが分からず、
/// 結局そのまま家に置かれる。冊子のP12には市内55か所の一覧がある。
///
/// このアプリは地区を設定してもらっているので、区が分かる。
/// 全55か所を読ませずに、その区のぶんだけ先に出せる。
class CollectionBoxes {
  const CollectionBoxes({
    required this.source,
    required this.sourceUrl,
    required this.hours,
    required this.notes,
    required this.boxes,
    required this.places,
    required this.tooLarge,
    required this.homePickup,
  });

  static Future<CollectionBoxes> load() async {
    final raw = await rootBundle.loadString(
      'assets/data/collection_boxes.json',
    );
    return CollectionBoxes.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  final String source;
  final String sourceUrl;
  final String hours;
  final List<String> notes;

  /// 箱は2種類。黄色（小型家電）と白色（電池）。
  final List<BoxKind> boxes;

  /// 区ごとの設置場所。
  final List<WardPlaces> places;

  final TooLargeGuide tooLarge;
  final HomePickup homePickup;

  factory CollectionBoxes.fromJson(Map<String, dynamic> json) =>
      CollectionBoxes(
        source: json['source'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        hours: json['hours'] as String? ?? '',
        notes: [
          for (final n in (json['notes'] as List<dynamic>? ?? const []))
            n as String,
        ],
        boxes: [
          for (final b in (json['boxes'] as List<dynamic>? ?? const []))
            BoxKind.fromJson(b as Map<String, dynamic>),
        ],
        places: [
          for (final p in (json['places'] as List<dynamic>? ?? const []))
            WardPlaces.fromJson(p as Map<String, dynamic>),
        ],
        tooLarge: TooLargeGuide.fromJson(
          json['tooLarge'] as Map<String, dynamic>? ?? const {},
        ),
        homePickup: HomePickup.fromJson(
          json['homePickup'] as Map<String, dynamic>? ?? const {},
        ),
      );

  /// [ward]の設置場所。設定していない区や、知らない区名なら null。
  WardPlaces? placesIn(String? ward) {
    if (ward == null) return null;
    for (final place in places) {
      if (place.ward == ward) return place;
    }
    return null;
  }

  int get totalPlaces =>
      places.fold(0, (sum, place) => sum + place.names.length);
}

class BoxKind {
  const BoxKind({
    required this.id,
    required this.name,
    required this.color,
    required this.accepts,
    required this.examples,
    required this.notes,
  });

  final String id;
  final String name;

  /// 「黄色」「白色」。現地で見分けるのに要る。
  final String color;

  final String accepts;
  final List<String> examples;
  final List<String> notes;

  factory BoxKind.fromJson(Map<String, dynamic> json) => BoxKind(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    color: json['color'] as String? ?? '',
    accepts: json['accepts'] as String? ?? '',
    examples: [
      for (final e in (json['examples'] as List<dynamic>? ?? const []))
        e as String,
    ],
    notes: [
      for (final n in (json['notes'] as List<dynamic>? ?? const []))
        n as String,
    ],
  );
}

class WardPlaces {
  const WardPlaces({required this.ward, required this.names});

  final String ward;
  final List<String> names;

  factory WardPlaces.fromJson(Map<String, dynamic> json) => WardPlaces(
    ward: json['ward'] as String? ?? '',
    names: [
      for (final n in (json['names'] as List<dynamic>? ?? const []))
        n as String,
    ],
  );
}

class TooLargeGuide {
  const TooLargeGuide({
    required this.title,
    required this.body,
    required this.examples,
    required this.place,
    required this.notes,
  });

  final String title;
  final String body;
  final String examples;
  final String place;
  final List<String> notes;

  factory TooLargeGuide.fromJson(Map<String, dynamic> json) => TooLargeGuide(
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    examples: json['examples'] as String? ?? '',
    place: json['place'] as String? ?? '',
    notes: [
      for (final n in (json['notes'] as List<dynamic>? ?? const []))
        n as String,
    ],
  );
}

class HomePickup {
  const HomePickup({
    required this.title,
    required this.body,
    required this.phone,
    required this.hours,
    required this.url,
    required this.notes,
  });

  final String title;
  final String body;
  final String phone;
  final String hours;
  final String url;
  final List<String> notes;

  factory HomePickup.fromJson(Map<String, dynamic> json) => HomePickup(
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    hours: json['hours'] as String? ?? '',
    url: json['url'] as String? ?? '',
    notes: [
      for (final n in (json['notes'] as List<dynamic>? ?? const []))
        n as String,
    ],
  );
}
