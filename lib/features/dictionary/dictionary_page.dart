import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/waste_item.dart';
import '../../providers.dart';
import '../../ui/category_style.dart';
import '../../ui/widgets/load_failure_view.dart';

/// 品目から出し先を調べる画面。
///
/// 収集日を知りたいのがホーム・カレンダーなら、こちらは「これは何ごみか」を
/// 調べるための画面。名前で絞り込めることが第一なので、検索欄を最上部に置く。
class DictionaryPage extends ConsumerStatefulWidget {
  const DictionaryPage({super.key});

  @override
  ConsumerState<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends ConsumerState<DictionaryPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dictionary = ref.watch(wasteDictionaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('分別')),
      body: switch (dictionary) {
        AsyncData(:final value) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '品目名で探す（例：ペットボトル）',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: '入力を消す',
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: _Results(items: value.search(_query), query: _query),
            ),
          ],
        ),
        AsyncError() => LoadFailureView(
          message: '分別の一覧を読み込めませんでした。',
          onRetry: () => ref.invalidate(wasteDictionaryProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: dictionary.hasValue
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '出典：${dictionary.requireValue.source}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.items, required this.query});

  final List<WasteItem> items;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '「$query」は一覧にありません。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '別の言い方で探すか、市のごみ分別辞典で確認してください。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) => _ItemTile(items[index]),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile(this.item);

  final WasteItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = item.category;
    // 5区分なら区分色を使う。粗大ごみなど収集日を持たない出し先は、
    // 区分色と紛らわしくならないよう控えめな色にする。
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : CategoryStyle.colorOf(category, context);

    return ListTile(
      leading: Icon(
        category == null
            ? Icons.place_outlined
            : CategoryStyle.iconOf(category),
        color: color,
      ),
      title: Text(item.name),
      subtitle: item.note.isEmpty
          ? null
          : Text(
              item.note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Text(
        item.categoryLabel,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      isThreeLine: item.note.length > 24,
    );
  }
}
