import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/collection_area.dart';
import '../../domain/collection_rule.dart';
import '../../domain/garbage_category.dart';
import '../../providers.dart';
import '../../ui/category_style.dart';

/// 区分ごとの入力状態。
///
/// 曜日は複数（もえるごみは週2回）、週指定は区分単位で1つ持つ。
/// 「第1木曜と毎週火曜」のような曜日ごとに頻度が違う組み合わせは、
/// さいたま市の収集では出てこないので入力できなくてよい。
class _CategoryDraft {
  _CategoryDraft({Set<int>? weekdays, this.weeksOfMonth})
    : weekdays = weekdays ?? <int>{};

  final Set<int> weekdays;
  Set<int>? weeksOfMonth;

  List<CollectionRule> toRules() {
    final sorted = weekdays.toList()..sort();
    return [
      for (final weekday in sorted)
        weeksOfMonth == null
            ? CollectionRule.weekly(weekday)
            : CollectionRule.monthly(weekday, weeksOfMonth!),
    ];
  }

  static _CategoryDraft fromRules(List<CollectionRule> rules) => _CategoryDraft(
    weekdays: {for (final rule in rules) rule.weekday},
    // 区分内で頻度は揃っている前提なので、先頭のルールの週指定を代表に使う。
    weeksOfMonth: rules.isEmpty ? null : rules.first.weeksOfMonth,
  );
}

/// 収集頻度の選択肢。値が null なら毎週。
class _FrequencyOption {
  const _FrequencyOption(this.label, this.weeks);

  final String label;
  final Set<int>? weeks;

  static const options = [
    _FrequencyOption('毎週', null),
    _FrequencyOption('第1・第3', {1, 3}),
    _FrequencyOption('第2・第4', {2, 4}),
    _FrequencyOption('第1のみ', {1}),
    _FrequencyOption('第2のみ', {2}),
    _FrequencyOption('第3のみ', {3}),
    _FrequencyOption('第4のみ', {4}),
  ];

  static _FrequencyOption match(Set<int>? weeks) {
    for (final option in options) {
      if (option.weeks == null && weeks == null) return option;
      if (option.weeks != null &&
          weeks != null &&
          option.weeks!.length == weeks.length &&
          option.weeks!.containsAll(weeks)) {
        return option;
      }
    }
    return options.first;
  }
}

/// 地区（＝収集曜日）の設定画面。初回設定と設定変更で同じ画面を使う。
class AreaEditorPage extends ConsumerStatefulWidget {
  const AreaEditorPage({super.key, this.initial, this.isOnboarding = false});

  /// 変更のときは現在の設定。初回は null。
  final CollectionArea? initial;

  /// 初回設定として開いているか。戻るボタンと文言が変わる。
  final bool isOnboarding;

  @override
  ConsumerState<AreaEditorPage> createState() => _AreaEditorPageState();
}

class _AreaEditorPageState extends ConsumerState<AreaEditorPage> {
  late String _ward;
  late bool _earlyMorning;
  late final TextEditingController _nameController;
  late final Map<GarbageCategory, _CategoryDraft> _drafts;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _ward = initial?.ward ?? saitamaWards.first;
    _earlyMorning = initial?.earlyMorning ?? false;
    _nameController = TextEditingController(
      text: initial == null || initial.name == _defaultName ? '' : initial.name,
    );
    _drafts = {
      for (final category in GarbageCategory.values)
        category: _CategoryDraft.fromRules(
          initial?.rulesFor(category) ?? const [],
        ),
    };
  }

  static const _defaultName = 'わたしの地区';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _hasAnyDay => _drafts.values.any((d) => d.weekdays.isNotEmpty);

  /// 地区が特定できず、曜日をゼロから手入力する経路かどうか。
  ///
  /// `AreaPickerPage`で地区を選んだ場合は曜日が確定した状態で渡ってくるので、
  /// 入力を助けるための雛形（プリセット）を出す意味がない。
  /// 「自分の地区が見つからない」を選んだときだけ雛形を出す。
  bool get _isManualEntry => widget.initial == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(areaCatalogProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(_isManualEntry ? '収集曜日を自分で設定' : '収集曜日の確認')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Text(
            _isManualEntry
                ? 'お住まいの区と、区分ごとの収集曜日を設定してください。'
                      '曜日は市から配布される収集日カレンダーで確認できます。'
                : '選んだ地区の収集曜日です。実際の収集日と違う場合はここで調整できます。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _SectionTitle('お住まいの区'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ward in saitamaWards)
                ChoiceChip(
                  label: Text(ward),
                  selected: _ward == ward,
                  onSelected: (_) => setState(() => _ward = ward),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isManualEntry &&
              catalog != null &&
              catalog.presets.isNotEmpty) ...[
            _SectionTitle('入力の出発点'),
            const SizedBox(height: 4),
            Text(
              'もえるごみの曜日だけ入った雛形です。当てはまるものを選んでから、残りの区分を足してください。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in catalog.presets)
                  ActionChip(
                    avatar: const Icon(Icons.auto_fix_high, size: 18),
                    label: Text(preset.name),
                    onPressed: () => _applyPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          _SectionTitle('収集曜日'),
          const SizedBox(height: 8),
          for (final category in GarbageCategory.values) ...[
            _CategoryEditor(
              category: category,
              draft: _drafts[category]!,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          _SectionTitle('その他'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _earlyMorning,
            onChanged: (value) => setState(() => _earlyMorning = value),
            title: const Text('もえるごみの早朝収集地区'),
            subtitle: const Text('大宮区・浦和区の一部が該当します。朝5時30分までに出す必要があります。'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '地区の名前（任意）',
              hintText: _defaultName,
              border: OutlineInputBorder(),
            ),
          ),
          // データの出典・但し書きはここには出さない。
          // 曜日を確認・調整している最中に読ませる情報ではないので、
          // 設定画面の「このアプリについて」にまとめてある。
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FilledButton(
          onPressed: _hasAnyDay ? _save : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(widget.isOnboarding ? 'この設定ではじめる' : '保存する'),
        ),
      ),
    );
  }

  void _applyPreset(CollectionArea preset) {
    setState(() {
      for (final category in GarbageCategory.values) {
        final rules = preset.rulesFor(category);
        // 雛形に入っていない区分は今の入力を消さずに残す。
        if (rules.isEmpty) continue;
        final draft = _CategoryDraft.fromRules(rules);
        _drafts[category]!
          ..weekdays.clear()
          ..weekdays.addAll(draft.weekdays)
          ..weeksOfMonth = draft.weeksOfMonth;
      }
      if (preset.earlyMorning) _earlyMorning = true;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final area = CollectionArea(
      id: CollectionArea.customAreaId,
      ward: _ward,
      name: name.isEmpty ? _defaultName : name,
      earlyMorning: _earlyMorning,
      rules: {
        for (final entry in _drafts.entries)
          if (entry.value.weekdays.isNotEmpty) entry.key: entry.value.toRules(),
      },
    );
    await ref.read(selectedAreaProvider.notifier).save(area);
    if (!mounted) return;
    // この画面は常に AreaPickerPage（初回設定時）か SettingsPage（変更時）から
    // push されて開くので、保存後は常に pop してよい。初回設定時は pop した先の
    // _Root が selectedAreaProvider の更新を検知して HomeShell に切り替わる。
    Navigator.of(context).pop();
  }
}

class _CategoryEditor extends StatelessWidget {
  const _CategoryEditor({
    required this.category,
    required this.draft,
    required this.onChanged,
  });

  final GarbageCategory category;
  final _CategoryDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = CategoryStyle.colorOf(category, context);
    final frequency = _FrequencyOption.match(draft.weeksOfMonth);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CategoryStyle.iconOf(category), color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                category.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var weekday = 1; weekday <= 7; weekday++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _WeekdayToggle(
                      label: CollectionRule.weekdayName(weekday),
                      selected: draft.weekdays.contains(weekday),
                      color: color,
                      onTap: () {
                        if (!draft.weekdays.remove(weekday)) {
                          draft.weekdays.add(weekday);
                        }
                        onChanged();
                      },
                    ),
                  ),
                ),
            ],
          ),
          if (draft.weekdays.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('頻度', style: theme.textTheme.bodySmall),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: frequency.label,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      for (final option in _FrequencyOption.options)
                        DropdownMenuItem(
                          value: option.label,
                          child: Text(option.label),
                        ),
                    ],
                    onChanged: (label) {
                      draft.weeksOfMonth = _FrequencyOption.options
                          .firstWhere((option) => option.label == label)
                          .weeks;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekdayToggle extends StatelessWidget {
  const _WeekdayToggle({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : theme.colorScheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selected ? color : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
