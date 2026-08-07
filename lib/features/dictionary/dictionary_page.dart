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
///
/// 一覧は市の早見表と同じ五十音順で、右端に索引を出す。443件あるので、
/// 検索語を思いつかないときに「た行あたり」と当たりを付けて飛べる必要がある。
class DictionaryPage extends ConsumerStatefulWidget {
  const DictionaryPage({super.key});

  @override
  ConsumerState<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends ConsumerState<DictionaryPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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
              child: _Results(
                items: value.search(_query),
                query: _query,
                scrollController: _scrollController,
              ),
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
  const _Results({
    required this.items,
    required this.query,
    required this.scrollController,
  });

  final List<WasteItem> items;
  final String query;
  final ScrollController scrollController;

  /// 一覧の各行の高さ。索引から飛ぶ位置を計算するのに使う。
  ///
  /// 注意点の有無で行の高さが変わるので、実測ではなく固定にしている。
  /// 索引は「だいたいその辺り」に飛べれば用が足りるので、多少ずれてよい。
  static const _rowHeight = 72.0;
  static const _headerHeight = 36.0;

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

    // かな行ごとの区切りを差し込んだ表示用の並びを作る。
    final rows = <_Row>[];
    final offsetOfKana = <String, double>{};
    var offset = 0.0;
    String? previous;
    for (final item in items) {
      if (item.kanaHead.isNotEmpty && item.kanaHead != previous) {
        offsetOfKana[item.kanaHead] = offset;
        rows.add(_Row.header(item.kanaHead));
        offset += _headerHeight;
        previous = item.kanaHead;
      }
      rows.add(_Row.item(item));
      offset += _rowHeight;
    }

    final list = ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return row.header != null
            ? _KanaHeader(row.header!)
            : _ItemTile(row.item!);
      },
    );

    // 絞り込み中は索引を出さない。件数が少なく、行が飛び飛びになって
    // かえって探しにくいため。
    if (query.trim().isNotEmpty || offsetOfKana.length < 2) return list;

    return Stack(
      children: [
        Padding(padding: const EdgeInsets.only(right: 22), child: list),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: _KanaIndex(
            offsets: offsetOfKana,
            scrollController: scrollController,
          ),
        ),
      ],
    );
  }
}

/// 一覧に差し込む行。かな行の見出しか、品目のどちらか。
class _Row {
  const _Row.header(this.header) : item = null;
  const _Row.item(this.item) : header = null;

  final String? header;
  final WasteItem? item;
}

class _KanaHeader extends StatelessWidget {
  const _KanaHeader(this.kana);

  final String kana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        kana,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 右端に出す五十音の索引。触った位置の行へ飛ぶ。
class _KanaIndex extends StatefulWidget {
  const _KanaIndex({required this.offsets, required this.scrollController});

  final Map<String, double> offsets;
  final ScrollController scrollController;

  @override
  State<_KanaIndex> createState() => _KanaIndexState();
}

class _KanaIndexState extends State<_KanaIndex> {
  String? _touching;

  void _jumpTo(String kana) {
    final offset = widget.offsets[kana];
    if (offset == null || !widget.scrollController.hasClients) return;
    final max = widget.scrollController.position.maxScrollExtent;
    widget.scrollController.jumpTo(offset.clamp(0.0, max));
  }

  /// 指の位置から、その真下にあるかなを求める。
  ///
  /// 1文字ずつタップさせるには索引の文字が小さすぎるので、
  /// なぞって動かせるようにしている。
  void _handle(Offset localPosition, double height) {
    final keys = widget.offsets.keys.toList();
    if (keys.isEmpty) return;
    final index = (localPosition.dy / height * keys.length).floor().clamp(
      0,
      keys.length - 1,
    );
    final kana = keys[index];
    if (kana == _touching) return;
    setState(() => _touching = kana);
    _jumpTo(kana);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = widget.offsets.keys.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => _handle(d.localPosition, height),
          onVerticalDragUpdate: (d) => _handle(d.localPosition, height),
          onVerticalDragEnd: (_) => setState(() => _touching = null),
          onVerticalDragCancel: () => setState(() => _touching = null),
          onTapDown: (d) => _handle(d.localPosition, height),
          onTapUp: (_) => setState(() => _touching = null),
          child: SizedBox(
            width: 22,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final kana in keys)
                  Text(
                    kana,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      height: 1.0,
                      fontWeight: kana == _touching
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: kana == _touching
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile(this.item);

  final WasteItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(item.name),
      subtitle: item.note.isEmpty
          ? null
          : Text(
              item.note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: _CategoryPill(item),
      isThreeLine: item.note.length > 24,
    );
  }
}

/// 出し先を表すピル。ホームやカレンダーの区分バッジと同じ見た目にする。
///
/// 5区分でない出し先（粗大ごみ・小型家電・電池・収集できないもの）にも
/// 同じ形を使う。利用者から見ればどれも「どこに出すか」で区別はないため。
class _CategoryPill extends StatelessWidget {
  const _CategoryPill(this.item);

  final WasteItem item;

  /// 5区分に入らない出し先のアイコン。
  static const _fallbackIcons = {
    'oversized': Icons.chair_outlined,
    'smallAppliance': Icons.devices_other,
    'battery': Icons.battery_full,
    'notAccepted': Icons.block,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = item.category;
    // 5区分なら区分色を使う。収集日を持たない出し先は、区分色と
    // 紛らわしくならないよう控えめな色にする。
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : CategoryStyle.colorOf(category, context);
    final icon = category == null
        ? (_fallbackIcons[item.categoryId] ?? Icons.place_outlined)
        : CategoryStyle.iconOf(category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            item.shortCategoryLabel,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
