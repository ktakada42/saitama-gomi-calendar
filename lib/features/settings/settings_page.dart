import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/collection_rule.dart';
import '../../domain/garbage_category.dart';
import '../../providers.dart';
import '../../ui/category_style.dart';
import '../area/area_editor_page.dart';

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
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('お住まいの地区'),
            subtitle: Text('${area.ward}　${area.name}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AreaEditorPage(initial: area),
              ),
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'このアプリについて',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '分別区分と出し方はさいたま市の案内をもとにした要約です。'
                  '判断に迷うものや最新の情報は市の公式ページで確認してください。',
                  style: theme.textTheme.bodySmall,
                ),
                if (catalog != null && catalog.source.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(catalog.source, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
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
