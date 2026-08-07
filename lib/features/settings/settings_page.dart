import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/collection_rule.dart';
import '../../domain/garbage_category.dart';
import '../../providers.dart';
import '../../ui/category_style.dart';
import '../area/area_editor_page.dart';
import '../area/area_picker_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final area = ref.watch(selectedAreaProvider).value;
    final catalog = ref.watch(areaCatalogProvider).value;
    if (area == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // 「地区」は選び直すもの、「収集曜日」は確認・調整するもの、と
          // 役割で分ける。地区を選べば曜日は自動で決まるので、地区の項目から
          // 曜日の編集画面に入ると「地区を選んでも曜日が決まらない」ように見えてしまう。
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('お住まいの地区'),
            subtitle: Text('${area.ward}　${area.name}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AreaPickerPage()),
            ),
          ),
          const Divider(height: 1),
          const _ThemeModeTile(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '設定中の収集曜日',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final category in GarbageCategory.values)
            ListTile(
              dense: true,
              leading: Icon(
                CategoryStyle.iconOf(category),
                color: CategoryStyle.colorOf(category, context),
              ),
              title: Text(category.label),
              trailing: Text(
                _rulesLabel(area.rulesFor(category)),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (area.earlyMorning)
            const ListTile(
              dense: true,
              leading: Icon(Icons.schedule),
              title: Text('もえるごみの早朝収集地区'),
              trailing: Text('朝5:30まで'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('収集曜日を調整する'),
            subtitle: const Text('実際の収集日と違うときに直せます'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AreaEditorPage(initial: area),
              ),
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '区分と出し方',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final category in GarbageCategory.values)
            ExpansionTile(
              leading: Icon(
                CategoryStyle.iconOf(category),
                color: CategoryStyle.colorOf(category, context),
              ),
              title: Text(category.label),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.examples.join('・')),
                const SizedBox(height: 8),
                Text(
                  category.howTo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const Divider(height: 32),
          // 出典・データの但し書きは、普段は畳んでおく。
          // 収集日を知りたいだけの利用者には不要な情報だが、
          // 情報の正確さを確かめたい人には必要なので、設定の最下部に置く。
          ExpansionTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('このアプリについて'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '分別区分と出し方はさいたま市の案内をもとにした要約です。'
                '判断に迷うものや最新の情報は市の公式ページで確認してください。',
                style: theme.textTheme.bodySmall,
              ),
              if (catalog != null && catalog.disclaimer.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  catalog.disclaimer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (catalog != null && catalog.source.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  catalog.source,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _rulesLabel(List<CollectionRule> rules) {
    if (rules.isEmpty) return '未設定';
    // 「毎週月曜日」「毎週木曜日」と並べると冗長なので、頻度が同じなら曜日をまとめる。
    final first = rules.first;
    final sameFrequency = rules.every(
      (rule) => rule.weeksOfMonth == null
          ? first.weeksOfMonth == null
          : first.weeksOfMonth != null &&
                first.weeksOfMonth!.length == rule.weeksOfMonth!.length &&
                first.weeksOfMonth!.containsAll(rule.weeksOfMonth!),
    );
    if (!sameFrequency) return rules.map((rule) => rule.label).join('、');

    final weekdays =
        (rules.map((rule) => rule.weekday).toSet().toList()..sort())
            .map(CollectionRule.weekdayName)
            .join('・');
    final weeks = first.weeksOfMonth;
    if (weeks == null) return '毎週$weekdays曜日';
    final sorted = weeks.toList()..sort();
    return '第${sorted.join('・第')}$weekdays曜日';
  }
}

/// 外観（ライト／ダーク／システム）の切り替え。
///
/// 端末のダークモード設定に勝手に追従すると、カレンダーの区分色の見え方が
/// 変わって戸惑うことがあるため、既定はライト固定にして、
/// 追従したい人が明示的に「端末の設定に合わせる」を選べるようにしている。
class _ThemeModeTile extends ConsumerWidget {
  const _ThemeModeTile();

  static const _labels = {
    ThemeMode.light: 'ライト',
    ThemeMode.dark: 'ダーク',
    ThemeMode.system: '端末の設定に合わせる',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.light;

    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('画面の明るさ'),
      subtitle: Text(_labels[mode]!),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPicker(context, ref, mode),
    );
  }

  Future<void> _showPicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (context) => SafeArea(
        child: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in _labels.entries)
                RadioListTile<ThemeMode>(
                  value: entry.key,
                  title: Text(entry.value),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await ref.read(themeModeProvider.notifier).save(selected);
    }
  }
}
