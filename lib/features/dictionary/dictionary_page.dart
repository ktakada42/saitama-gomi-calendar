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

  /// かな見出しのキー。索引から飛んだあと、実際にどこに描かれたかを
  /// 見て位置を寄せ直すのに使う。品目ごとに行の高さが変わるので、
  /// 計算だけでは正確な位置を出せない。
  final _headerKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dictionary = ref.watch(wasteDictionaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分別'),
        actions: [
          // 出典は一覧の下に出しっぱなしにせず、ここから開く。
          // 品目を探している間ずっと見えている必要はないが、
          // 「この情報はどこから来たのか」を確かめたいときには要る。
          if (dictionary.hasValue)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: '出典',
              onPressed: () =>
                  _showSource(context, dictionary.requireValue.source),
            ),
        ],
      ),
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
                headerKeys: _headerKeys,
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
    );
  }

  void _showSource(BuildContext context, String source) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('出典'),
        content: Text(source),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.items,
    required this.query,
    required this.scrollController,
    required this.headerKeys,
  });

  final List<WasteItem> items;
  final String query;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;

  static const _headerHeight = 36.0;

  /// 品目1件分の高さの見積り。
  ///
  /// ListTileは注意点の有無と長さで1行・2行・3行に変わり、それぞれ
  /// 56・72・88になる。索引から飛ぶ位置の当たりを付けるのに使う。
  /// 画面外の行は組み立てられておらず実測できないので、まずこの見積りで
  /// 飛んでから、描かれた見出しの位置を見て寄せ直す（_KanaIndex._jumpTo）。
  static double _itemHeight(WasteItem item) {
    if (item.note.isEmpty) return 56;
    return item.note.length > 24 ? 88 : 72;
  }

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
      offset += _itemHeight(item);
    }

    final list = ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final header = row.header;
        if (header == null) return _ItemTile(row.item!);
        return _KanaHeader(
          header,
          key: headerKeys.putIfAbsent(header, GlobalKey.new),
        );
      },
    );

    // 絞り込み中は索引を出さない。件数が少なく、行が飛び飛びになって
    // かえって探しにくいため。
    if (query.trim().isNotEmpty || offsetOfKana.length < 2) return list;

    return Stack(
      children: [
        Padding(padding: const EdgeInsets.only(right: 30), child: list),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: _KanaIndex(
            offsets: offsetOfKana,
            scrollController: scrollController,
            headerKeys: headerKeys,
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
  const _KanaHeader(this.kana, {super.key});

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

/// 五十音の「行」と、その行に属するかな。
///
/// 索引はふだんこの行頭（あ・か・さ…）だけを出しておく。43文字を常に
/// 並べると1文字あたりが小さくなりすぎて、狙って押せないため。
const _kanaRows = [
  'あいうえお',
  'かきくけこ',
  'さしすせそ',
  'たちつてと',
  'なにぬねの',
  'はひふへほ',
  'まみむめも',
  'やゆよ',
  'らりるれろ',
  'わをん',
];

/// 右端に出す五十音の索引。
///
/// 行を押すと、その行のかなが開く。開いたかなを押すとそこへ飛ぶ。
/// 2段階にしているのは、43文字を一度に並べると1文字が小さくなりすぎて
/// 押し間違えるため。今いる行はいつも開いていて、現在地には丸を付ける。
class _KanaIndex extends StatefulWidget {
  const _KanaIndex({
    required this.offsets,
    required this.scrollController,
    required this.headerKeys,
  });

  /// かなごとの、一覧の中でのおおよその位置。並び順は一覧と同じ。
  final Map<String, double> offsets;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;

  @override
  State<_KanaIndex> createState() => _KanaIndexState();
}

class _KanaIndexState extends State<_KanaIndex> {
  /// 利用者が押して開いた行の行頭。nullなら今いる行が開く。
  String? _openedRow;

  /// 一覧の先頭に見えているかな。
  String? _current;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_syncCurrent);
    // 初回の描画時点ではまだスクロール位置を持っていないので、
    // 描画が終わってから現在地を取りにいく。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCurrent());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncCurrent);
    super.dispose();
  }

  /// 今どのかなの範囲を見ているかを、スクロール位置から求める。
  void _syncCurrent() {
    if (!widget.scrollController.hasClients) return;
    final offset = widget.scrollController.offset;
    String? found;
    for (final entry in widget.offsets.entries) {
      // 見出しが画面の上端を通り過ぎたら、そこから先はその行。
      if (entry.value <= offset + 1) {
        found = entry.key;
      } else {
        break;
      }
    }
    found ??= widget.offsets.keys.firstOrNull;
    if (found == _current) return;
    setState(() => _current = found);
  }

  /// [kana] を含む行の行頭。
  String? _rowHeadOf(String? kana) {
    if (kana == null) return null;
    for (final row in _kanaRows) {
      if (row.contains(kana)) return row[0];
    }
    return null;
  }

  /// [kana] の見出しが一覧の先頭に来るまで送る。
  ///
  /// 行の高さは品目によって変わるので、見積りだけでは行き過ぎたり
  /// 届かなかったりする。まず見積りで飛び、そこで実際に描かれた見出しの
  /// 位置を見て差の分だけ寄せ直す。近くまで来ていれば見出しは組み立てられて
  /// いるので、1〜2回で収まる。
  void _jumpTo(String kana) {
    final estimate = widget.offsets[kana];
    if (estimate == null || !widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    widget.scrollController.jumpTo(
      estimate.clamp(0.0, position.maxScrollExtent),
    );
    // 飛んだ先の行がそのまま開いた状態になるよう、手で開いた行は忘れる。
    setState(() => _openedRow = null);
    _settleOn(kana, remaining: 3);
  }

  void _settleOn(String kana, {required int remaining}) {
    if (remaining <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final context = widget.headerKeys[kana]?.currentContext;
      final box = context?.findRenderObject();
      final viewport = this.context.findRenderObject();
      if (box is! RenderBox || viewport is! RenderBox) return;
      // 見出しが索引の枠の上端からどれだけ下（＋）／上（−）にあるか。
      final delta = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (delta.abs() < 1) return;
      final position = widget.scrollController.position;
      widget.scrollController.jumpTo(
        (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
      );
      _settleOn(kana, remaining: remaining - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 手で開いた行があればそれを、なければ今いる行を開く。
    final opened = _openedRow ?? _rowHeadOf(_current);

    // 開いている行だけ、その行のかなをすべて並べる。
    final entries = <String>[];
    for (final row in _kanaRows) {
      final present = row.split('').where(widget.offsets.containsKey).toList();
      if (present.isEmpty) continue;
      if (row[0] == opened) {
        entries.addAll(present);
      } else {
        entries.add(present.first);
      }
    }

    return SizedBox(
      width: 30,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final kana in entries)
            _KanaIndexEntry(
              kana: kana,
              isCurrent: kana == _current,
              onTap: () {
                // 閉じている行の行頭は「開く」。開いている行のかなは「飛ぶ」。
                final head = _rowHeadOf(kana);
                if (kana == head && head != opened) {
                  setState(() => _openedRow = head);
                } else {
                  _jumpTo(kana);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _KanaIndexEntry extends StatelessWidget {
  const _KanaIndexEntry({
    required this.kana,
    required this.isCurrent,
    required this.onTap,
  });

  final String kana;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 26,
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: isCurrent
                ? BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  )
                : null,
            child: Text(
              kana,
              style: theme.textTheme.labelMedium?.copyWith(
                height: 1.0,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
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
