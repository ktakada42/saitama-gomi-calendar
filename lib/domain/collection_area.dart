import 'garbage_category.dart';
import 'collection_rule.dart';

/// さいたま市の10区。区によって収集日が違うわけではないが、
/// 地区を選ぶときの絞り込みと、粗大ごみ受付など区単位の案内に使う。
const saitamaWards = <String>[
  '西区',
  '北区',
  '大宮区',
  '見沼区',
  '中央区',
  '桜区',
  '浦和区',
  '南区',
  '緑区',
  '岩槻区',
];

/// ひとつの収集地区。
///
/// 「どの区分がいつ収集されるか」がこのアプリの設定のすべてなので、
/// 区分ごとのルール一覧をそのまま持つ。もえるごみのように週2回ある区分は
/// ルールが2つ並ぶ。
class CollectionArea {
  const CollectionArea({
    required this.id,
    required this.ward,
    required this.name,
    required this.rules,
    this.earlyMorning = false,
    this.note,
  });

  /// 保存・参照用のID。ユーザーが自分で作った地区は [customAreaId]。
  final String id;

  /// 所属する区。
  final String ward;

  /// 地区名（プリセット名、または利用者がつけた名前）。
  final String name;

  /// 区分ごとの収集ルール。空リストの区分は「この地区では収集日が設定されていない」。
  final Map<GarbageCategory, List<CollectionRule>> rules;

  /// もえるごみの早朝収集地区かどうか。大宮区・浦和区の一部が該当し、
  /// この地区だけ朝5時30分までに出す必要がある。
  final bool earlyMorning;

  /// 補足（プリセットの出典など）。
  final String? note;

  static const customAreaId = 'custom';

  bool get isCustom => id == customAreaId;

  /// この区分をその日に出すときの期限。早朝収集地区のもえるごみだけ5:30。
  ///
  /// 「その日にまだ出せるか」の判定に使うので、表示用の文字列とは別に
  /// 時刻そのものを返す。
  DepositDeadline depositDeadlineAt(GarbageCategory category) =>
      earlyMorning && category == GarbageCategory.burnable
      ? const DepositDeadline(5, 30)
      : const DepositDeadline(8, 30);

  /// 表示用の期限。「5:30」「8:30」。
  String depositDeadline(GarbageCategory category) =>
      depositDeadlineAt(category).label;

  List<CollectionRule> rulesFor(GarbageCategory category) =>
      rules[category] ?? const [];

  /// 収集日がひとつも設定されていない状態。設定画面の入力途中で起きうる。
  bool get isEmpty => rules.values.every((list) => list.isEmpty);

  CollectionArea copyWith({
    String? id,
    String? ward,
    String? name,
    Map<GarbageCategory, List<CollectionRule>>? rules,
    bool? earlyMorning,
    String? note,
  }) => CollectionArea(
    id: id ?? this.id,
    ward: ward ?? this.ward,
    name: name ?? this.name,
    rules: rules ?? this.rules,
    earlyMorning: earlyMorning ?? this.earlyMorning,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ward': ward,
    'name': name,
    'earlyMorning': earlyMorning,
    if (note != null) 'note': note,
    'rules': {
      for (final entry in rules.entries)
        if (entry.value.isNotEmpty)
          entry.key.id: [for (final rule in entry.value) rule.toJson()],
    },
  };

  factory CollectionArea.fromJson(Map<String, dynamic> json) {
    final rawRules = (json['rules'] as Map<String, dynamic>?) ?? const {};
    final rules = <GarbageCategory, List<CollectionRule>>{};
    for (final entry in rawRules.entries) {
      final category = GarbageCategory.fromId(entry.key);
      // 知らない区分IDは無視する。区分が増えた新しいデータを古いアプリで
      // 読んでも、既知の区分だけで動き続けるほうが安全なため。
      if (category == null) continue;
      rules[category] = [
        for (final rule in entry.value as List<dynamic>)
          CollectionRule.fromJson(rule as Map<String, dynamic>),
      ];
    }
    return CollectionArea(
      id: json['id'] as String,
      ward: json['ward'] as String,
      name: json['name'] as String,
      rules: rules,
      earlyMorning: json['earlyMorning'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }

  /// 何も設定されていない、自分で作る地区のひな形。
  static CollectionArea emptyCustom(String ward) => CollectionArea(
    id: customAreaId,
    ward: ward,
    name: '自分で設定した地区',
    rules: const {},
  );
}

/// ごみを出せる時刻の期限。
///
/// 市の収集は朝8時30分まで（早朝収集地区のもえるごみは5時30分まで）。
/// それを過ぎると、その日はもう出せない。
class DepositDeadline {
  const DepositDeadline(this.hour, this.minute);

  final int hour;
  final int minute;

  String get label => '$hour:${minute.toString().padLeft(2, '0')}';

  /// [now] がこの期限を過ぎているか。ちょうど期限の時刻はまだ出せる扱い。
  bool isPassedAt(DateTime now) {
    final limit = DateTime(now.year, now.month, now.day, hour, minute);
    return now.isAfter(limit);
  }

  @override
  bool operator ==(Object other) =>
      other is DepositDeadline && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}
