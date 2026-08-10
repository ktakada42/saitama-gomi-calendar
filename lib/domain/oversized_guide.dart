import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 粗大ごみの出し方。
///
/// 早見表は「直接持込みまたは戸別収集」としか書いておらず、いくらかかるのか、
/// どこへ申し込むのかが分からない。冊子ではP9にまとまっているが、
/// 冊子を持たない利用者には届かないので、ここで言葉にして持つ。
///
/// 金額は利用者の負担に直結するので、要約せず冊子の記載をそのまま写す。
/// 端数や消費税の扱いを言い換えると、実際の請求と食い違う。
class OversizedGuide {
  static Future<OversizedGuide> load() async {
    final raw = await rootBundle.loadString('assets/data/oversized.json');
    return OversizedGuide.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  const OversizedGuide({
    required this.source,
    required this.sourceUrl,
    required this.definition,
    required this.methods,
    required this.steps,
    required this.stepsNote,
    required this.specialFees,
    required this.exclusions,
  });

  final String source;
  final String sourceUrl;
  final OversizedDefinition definition;

  /// 出す方法。持込みと戸別収集の2つ。並べて比べられるようにしてある。
  final List<DisposalMethod> methods;

  /// 戸別収集の手順。
  final List<GuideStep> steps;
  final String stepsNote;

  final SpecialFees specialFees;

  /// 粗大ごみとしては出せないもの。
  final List<String> exclusions;

  factory OversizedGuide.fromJson(Map<String, dynamic> json) => OversizedGuide(
    source: json['source'] as String? ?? '',
    sourceUrl: json['sourceUrl'] as String? ?? '',
    definition: OversizedDefinition.fromJson(
      json['definition'] as Map<String, dynamic>? ?? const {},
    ),
    methods: [
      for (final m in (json['methods'] as List<dynamic>? ?? const []))
        DisposalMethod.fromJson(m as Map<String, dynamic>),
    ],
    steps: [
      for (final s in (json['steps'] as List<dynamic>? ?? const []))
        GuideStep.fromJson(s as Map<String, dynamic>),
    ],
    stepsNote: json['stepsNote'] as String? ?? '',
    specialFees: SpecialFees.fromJson(
      json['specialFees'] as Map<String, dynamic>? ?? const {},
    ),
    exclusions: [
      for (final e in (json['exclusions'] as List<dynamic>? ?? const []))
        e as String,
    ],
  );

  /// 早見表の品目[itemName]に、大きさによらない料金が決まっていればそれ。
  ///
  /// 名前で機械的に照合してはいけない。早見表と料金表は書き方が違ううえ
  /// （「マットレス（スプリングあり）」と「スプリング入りマットレス」）、
  /// 部分一致で拾うと「自転車のタイヤ・チューブ」（もえるごみ）に
  /// タイヤの550円が付く。金額の誤りは利用者の損害になるので、
  /// 当てはまる品目をデータ側に書き出し、そこに無いものには出さない。
  ///
  /// ソファーは早見表が一人がけ／二人がけを分けておらず額が定まらないため、
  /// あえて対応づけていない。料金表を見て判断してもらう。
  SpecialFeeItem? feeFor(String itemName) {
    for (final fee in specialFees.items) {
      if (fee.appliesTo.contains(itemName)) return fee;
    }
    return null;
  }
}

class OversizedDefinition {
  const OversizedDefinition({
    required this.oversized,
    required this.difficult,
    required this.tooLarge,
    required this.note,
  });

  /// 「最大の一辺又は直径が90cm以上2m未満のごみ」
  final String oversized;

  /// 市の処理施設では処理できないもの。
  final String difficult;

  /// 2m以上は市では扱えない。ここを書かないと、大きいほど粗大ごみだと思われる。
  final String tooLarge;

  final String note;

  factory OversizedDefinition.fromJson(Map<String, dynamic> json) =>
      OversizedDefinition(
        oversized: json['oversized'] as String? ?? '',
        difficult: json['difficult'] as String? ?? '',
        tooLarge: json['tooLarge'] as String? ?? '',
        note: json['note'] as String? ?? '',
      );
}

class DisposalMethod {
  const DisposalMethod({
    required this.id,
    required this.name,
    required this.badge,
    required this.fee,
    required this.feeNote,
    required this.payment,
    required this.contactName,
    required this.phone,
    required this.phoneHours,
    required this.url,
    required this.urlLabel,
    required this.notes,
  });

  final String id;
  final String name;

  /// 「完全予約制」など、名前の横に出す短い札。
  final String badge;

  /// 「10kgごとに180円」「1品 550円」
  final String fee;
  final String feeNote;
  final String payment;

  final String contactName;
  final String phone;
  final String phoneHours;
  final String url;
  final String urlLabel;

  final List<String> notes;

  factory DisposalMethod.fromJson(Map<String, dynamic> json) => DisposalMethod(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    badge: json['badge'] as String? ?? '',
    fee: json['fee'] as String? ?? '',
    feeNote: json['feeNote'] as String? ?? '',
    payment: json['payment'] as String? ?? '',
    contactName: json['contactName'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    phoneHours: json['phoneHours'] as String? ?? '',
    url: json['url'] as String? ?? '',
    urlLabel: json['urlLabel'] as String? ?? '',
    notes: [
      for (final n in (json['notes'] as List<dynamic>? ?? const []))
        n as String,
    ],
  );
}

class GuideStep {
  const GuideStep({required this.title, required this.body});

  final String title;
  final String body;

  factory GuideStep.fromJson(Map<String, dynamic> json) => GuideStep(
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
  );
}

class SpecialFees {
  const SpecialFees({required this.note, required this.items});

  final String note;
  final List<SpecialFeeItem> items;

  factory SpecialFees.fromJson(Map<String, dynamic> json) => SpecialFees(
    note: json['note'] as String? ?? '',
    items: [
      for (final i in (json['items'] as List<dynamic>? ?? const []))
        SpecialFeeItem.fromJson(i as Map<String, dynamic>),
    ],
  );
}

class SpecialFeeItem {
  const SpecialFeeItem({
    required this.name,
    required this.note,
    required this.dropOffYen,
    required this.doorToDoorYen,
    required this.appliesTo,
  });

  final String name;
  final String note;

  /// 直接持ち込んだ場合。
  final int dropOffYen;

  /// 取りに来てもらう場合。持込みより高い。
  final int doorToDoorYen;

  /// この料金が当てはまる早見表の品目名。完全一致で見る。
  final List<String> appliesTo;

  factory SpecialFeeItem.fromJson(Map<String, dynamic> json) => SpecialFeeItem(
    name: json['name'] as String? ?? '',
    note: json['note'] as String? ?? '',
    dropOffYen: json['dropOffYen'] as int? ?? 0,
    doorToDoorYen: json['doorToDoorYen'] as int? ?? 0,
    appliesTo: [
      for (final n in (json['appliesTo'] as List<dynamic>? ?? const []))
        n as String,
    ],
  );
}
