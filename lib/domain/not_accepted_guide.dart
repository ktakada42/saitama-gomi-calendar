import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 市では収集・処理できないものの持って行き先。
///
/// 早見表は「販売店、専門業者へ」「許可業者（㈲太盛）へ」までしか書いておらず、
/// どこへ連絡すればよいのかが分からない。「市では無理です」で終わらせると、
/// 結局その先を自分で調べることになる。
///
/// 冊子のP10・P11には、窓口の名前・電話番号・URLまで載っている。
/// ここまで持ってきて、はじめて「捨てられる」に届く。
class NotAcceptedGuide {
  const NotAcceptedGuide({
    required this.source,
    required this.sourceUrl,
    required this.lead,
    required this.destinations,
    required this.otherNotes,
  });

  static Future<NotAcceptedGuide> load() async {
    final raw = await rootBundle.loadString('assets/data/not_accepted.json');
    return NotAcceptedGuide.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  final String source;
  final String sourceUrl;
  final String lead;
  final List<Destination> destinations;
  final List<String> otherNotes;

  factory NotAcceptedGuide.fromJson(Map<String, dynamic> json) =>
      NotAcceptedGuide(
        source: json['source'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        lead: json['lead'] as String? ?? '',
        destinations: [
          for (final d in (json['destinations'] as List<dynamic>? ?? const []))
            Destination.fromJson(d as Map<String, dynamic>),
        ],
        otherNotes: [
          for (final n in (json['otherNotes'] as List<dynamic>? ?? const []))
            n as String,
        ],
      );

  /// 早見表の品目[itemName]の持って行き先。決まっていなければ null。
  ///
  /// 名前で機械的に照合してはいけない。「ボンベ」で拾うと「炭酸ボンベ」も
  /// 「プロパンガスボンベ」も同じ扱いになるし、「石」は「石こうボード」にも
  /// 「消火器」にも当たる。行き先を間違えると、持って行った先で断られる。
  /// 当てはまる品目をデータ側に書き出し、そこに無いものには出さない。
  Destination? destinationFor(String itemName) {
    for (final destination in destinations) {
      if (destination.appliesTo.contains(itemName)) return destination;
    }
    return null;
  }
}

class Destination {
  const Destination({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.appliesTo,
    required this.contacts,
    required this.options,
    required this.notes,
  });

  final String id;
  final String title;

  /// 見出しの下に出す一行。何が当てはまるのかを先に分からせる。
  final String summary;

  final String body;

  /// この行き先が当てはまる早見表の品目名。完全一致で見る。
  final List<String> appliesTo;

  /// 連絡先。無い行き先（販売店へ、など）もある。
  final List<Contact> contacts;

  /// 選べる方法。順番に意味がある（安い順・手軽な順）。
  final List<String> options;

  final List<String> notes;

  factory Destination.fromJson(Map<String, dynamic> json) => Destination(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    body: json['body'] as String? ?? '',
    appliesTo: [
      for (final n in (json['appliesTo'] as List<dynamic>? ?? const []))
        n as String,
    ],
    contacts: [
      for (final c in (json['contacts'] as List<dynamic>? ?? const []))
        Contact.fromJson(c as Map<String, dynamic>),
    ],
    options: [
      for (final o in (json['options'] as List<dynamic>? ?? const []))
        o as String,
    ],
    notes: [
      for (final n in (json['notes'] as List<dynamic>? ?? const []))
        n as String,
    ],
  );
}

class Contact {
  const Contact({
    required this.name,
    required this.detail,
    required this.phone,
    required this.hours,
    required this.url,
  });

  final String name;
  final String detail;
  final String phone;
  final String hours;
  final String url;

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    name: json['name'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    hours: json['hours'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );
}
