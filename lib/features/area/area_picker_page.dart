import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/paren_wrap.dart';
import '../../data/area_catalog.dart';
import '../../domain/collection_area.dart';
import '../../providers.dart';
import '../../ui/widgets/load_failure_view.dart';
import 'area_editor_page.dart';

/// 初回設定・地区の選び直しの入口。
///
/// 収集曜日は利用者が決めるものではなく地区ごとに市が決めているものなので、
/// 曜日を直接入力させるのではなく、まず地区を特定することを目的にした画面。
/// 郵便番号か一覧のどちらかで地区の候補を絞り込み、選んだ結果を
/// [AreaEditorPage] に渡して曜日の確認・保存につなげる。地区が見つからない
/// 場合だけ、曜日を手入力する[AreaEditorPage]の代替経路に進む。
class AreaPickerPage extends ConsumerStatefulWidget {
  const AreaPickerPage({super.key, this.isOnboarding = false});

  /// 初回設定として開いているか。戻るボタンと文言が変わる。
  final bool isOnboarding;

  @override
  ConsumerState<AreaPickerPage> createState() => _AreaPickerPageState();
}

class _AreaPickerPageState extends ConsumerState<AreaPickerPage> {
  final _postalController = TextEditingController();

  /// 郵便番号検索の結果。null は「まだ検索していない」。
  List<CollectionArea>? _postalResults;

  /// 一覧モードで選択中の区。null は「一覧モードを開いていない」。
  String? _listWard;

  /// 郵便番号が7桁そろっているか。そろうまで「探す」は押せない。
  bool get _canSearch => _postalController.text.trim().length == 7;

  @override
  void dispose() {
    _postalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogState = ref.watch(areaCatalogProvider);
    final catalog = catalogState.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('お住まいの地区を確認'),
        automaticallyImplyLeading: !widget.isOnboarding,
      ),
      body: catalog == null
          ? (catalogState.hasError
                // 同梱アセットなので通常は失敗しないが、失敗したまま
                // ローディングを回し続けると何も分からない。再試行に加えて、
                // 地区データが無くても曜日を手入力すれば使えるので、
                // その導線だけは残しておく。
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: LoadFailureView(
                          message: '地区データを読み込めませんでした。',
                          onRetry: () => ref.invalidate(areaCatalogProvider),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: TextButton(
                          onPressed: _selectManual,
                          child: const Text('収集曜日を自分で設定する'),
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (widget.isOnboarding) ...[
                  Text(
                    'ごみの収集曜日は地区ごとに市が決めています。郵便番号か一覧から、'
                    'お住まいの地区を選んでください。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                ],
                _SectionTitle('郵便番号で探す'),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _postalController,
                        keyboardType: TextInputType.number,
                        maxLength: 7,
                        decoration: const InputDecoration(
                          labelText: '郵便番号（7桁）',
                          hintText: '3300000',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        // 桁がそろった時点でボタンの活性を切り替える。
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _search(catalog),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      // 7桁そろうまでは押させない。途中の桁で押しても
                      // 「該当なし」としか返せず、入力を間違えたのか
                      // 対応する地区が無いのかが分からない。
                      onPressed: _canSearch ? () => _search(catalog) : null,
                      child: const Text('探す'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '郵便番号は地区を確認するためだけに使い、保存はされません。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_postalResults != null) ...[
                  const SizedBox(height: 16),
                  _PostalResults(
                    results: _postalResults!,
                    onSelect: _selectArea,
                  ),
                ],
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 20),
                _SectionTitle('一覧から選ぶ'),
                const SizedBox(height: 4),
                Text(
                  '郵便番号を入力したくない場合は、区を選んで一覧から選べます。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ward in saitamaWards)
                      ChoiceChip(
                        label: Text(ward),
                        selected: _listWard == ward,
                        onSelected: (_) => setState(() => _listWard = ward),
                      ),
                  ],
                ),
                if (_listWard != null) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final wardAreas = catalog.areasInWard(_listWard!);
                      if (wardAreas.isEmpty) {
                        return Text(
                          'この区の地区データはまだありません。'
                          '「自分の地区が見つからない」から設定してください。',
                          style: theme.textTheme.bodySmall,
                        );
                      }
                      return Column(
                        children: [
                          for (final area in wardAreas)
                            _AreaTile(
                              area: area,
                              onTap: () => _selectArea(area),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: 28),
                Center(
                  child: TextButton(
                    onPressed: _selectManual,
                    child: const Text('自分の地区が見つからない'),
                  ),
                ),
              ],
            ),
    );
  }

  void _search(AreaCatalog catalog) {
    setState(
      () => _postalResults = catalog.areasForPostalCode(_postalController.text),
    );
  }

  void _selectArea(CollectionArea area) => _openEditor(area);

  void _selectManual() => _openEditor(null);

  void _openEditor(CollectionArea? area) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AreaEditorPage(initial: area, isOnboarding: widget.isOnboarding),
      ),
    );
  }
}

class _PostalResults extends StatelessWidget {
  const _PostalResults({required this.results, required this.onSelect});

  final List<CollectionArea> results;
  final void Function(CollectionArea) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'この郵便番号からは地区を特定できませんでした。一覧から選ぶか、'
          '下の「自分の地区が見つからない」から設定してください。',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          results.length == 1
              ? 'この郵便番号の地区が見つかりました。'
              : 'この郵便番号には複数の候補があります。あてはまる地区を選んでください。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final area in results)
          _AreaTile(
            area: area,
            highlight: results.length == 1,
            onTap: () => onSelect(area),
          ),
      ],
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({
    required this.area,
    required this.onTap,
    this.highlight = false,
  });

  final CollectionArea area;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlight ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        title: Text(keepParenthesesTogether('${area.ward}　${area.name}')),
        subtitle: area.earlyMorning ? const Text('もえるごみ早朝収集地区') : null,
        trailing: const Icon(Icons.chevron_right),
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
