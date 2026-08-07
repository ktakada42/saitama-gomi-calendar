import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/kana.dart';
import '../../domain/waste_item.dart';
import '../../providers.dart';
import '../../ui/widgets/category_pill.dart';
import '../../ui/widgets/load_failure_view.dart';
import 'waste_item_sheet.dart';

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
                manualUrl: value.sourceUrl,
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
    required this.manualUrl,
  });

  final List<WasteItem> items;
  final String query;
  final String manualUrl;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;

  static const _headerHeight = 36.0;

  /// 行の下段（subtitle）が何行になるか。
  ///
  /// 印を持つ品目は、注意点の下に「押せば続きがある」ことを1行足す。
  /// 3行に膨らまないよう、そのときは注意点を1行に丸める。
  static int subtitleLines(WasteItem item) {
    if (item.hasDetail) return item.note.isEmpty ? 1 : 2;
    if (item.note.isEmpty) return 0;
    return item.note.length > 24 ? 2 : 1;
  }

  /// 品目1件分の高さの見積り。
  ///
  /// ListTileは下段の行数で1行・2行・3行に変わり、それぞれ56・72・88になる。
  /// 索引から飛ぶ位置の当たりを付けるのに使う。画面外の行は組み立てられて
  /// おらず実測できないので、まずこの見積りで飛んでから、描かれた見出しの
  /// 位置を見て寄せ直す（_KanaIndex._jumpTo）。
  static double _itemHeight(WasteItem item) => switch (subtitleLines(item)) {
    0 => 56,
    1 => 72,
    _ => 88,
  };

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

    // 行ごとの区切りを差し込んだ表示用の並びを作る。
    final rows = <_Row>[];
    final offsetOfRow = <String, double>{};
    var offset = 0.0;
    String? previous;
    for (final item in items) {
      final head = KanaRow.headOf(item.kanaHead);
      if (head != null && head != previous) {
        offsetOfRow[head] = offset;
        rows.add(_Row.header(head));
        offset += _headerHeight;
        previous = head;
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
        if (header == null) {
          return _ItemTile(row.item!, manualUrl: manualUrl);
        }
        return _KanaHeader(
          header,
          key: headerKeys.putIfAbsent(header, GlobalKey.new),
        );
      },
    );

    // 絞り込み中は索引を出さない。件数が少なく、行が飛び飛びになって
    // かえって探しにくいため。
    if (query.trim().isNotEmpty || offsetOfRow.length < 2) return list;

    return Stack(
      children: [
        Padding(padding: const EdgeInsets.only(right: 30), child: list),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: _KanaIndex(
            offsets: offsetOfRow,
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
  const _KanaHeader(this.head, {super.key});

  /// 行の頭文字。見出しには「あ行」のように書いて、索引の「あ」と見分ける。
  final String head;

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
        '$head行',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 右端に出す五十音の索引。なぞると、触れている行へ送る。
///
/// iOSの連絡先と同じ形。行は10個しかないので全部並べても1つが小さくならず、
/// 指を滑らせるだけで端から端まで送れる。今いる行には丸を付ける。
class _KanaIndex extends StatefulWidget {
  const _KanaIndex({
    required this.offsets,
    required this.scrollController,
    required this.headerKeys,
  });

  /// 行ごとの、一覧の中でのおおよその位置。並び順は一覧と同じ。
  final Map<String, double> offsets;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;

  @override
  State<_KanaIndex> createState() => _KanaIndexState();
}

class _KanaIndexState extends State<_KanaIndex> {
  /// 一覧の先頭に見えている行。
  String? _current;

  /// なぞっている最中かどうか。触れている間は丸を濃くする。
  bool _dragging = false;

  /// 索引を操作している間は、現在地をスクロール位置から拾い直さない。
  ///
  /// 一覧の終わりに近い行は、送ってもその見出しが画面の上端まで来ない。
  /// 実際、わ行は3件しかないので一番下まで送っても上端には届かず、
  /// スクロール位置から拾うと手前のら行のままになって、わを選べなかった。
  /// 索引を触っている間は触れた行を現在地とする（iOSの索引も指に従う）。
  bool _scrubbing = false;

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

  /// 今どの行を見ているかを、スクロール位置から求める。
  void _syncCurrent() {
    if (_scrubbing || !widget.scrollController.hasClients) return;
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

  /// 指の位置から、その真下にある行へ送る。
  void _handleTouch(Offset localPosition, double itemHeight) {
    final heads = widget.offsets.keys.toList();
    if (heads.isEmpty) return;
    final index = (localPosition.dy / itemHeight).floor().clamp(
      0,
      heads.length - 1,
    );
    final head = heads[index];
    if (head == _current) return;
    // 時刻のホイールと同じく、送るたびに手応えを返す。
    // どこまで来たかを画面から目を離さずに掴めるようにする。
    HapticFeedback.selectionClick();
    setState(() {
      _scrubbing = true;
      _current = head;
    });
    _jumpTo(head);
  }

  /// [head] の見出しが一覧の先頭に来るまで送る。
  ///
  /// 行の高さは品目によって変わるので、見積りだけでは行き過ぎたり
  /// 届かなかったりする。まず見積りで飛び、そこで実際に描かれた見出しの
  /// 位置を見て差の分だけ寄せ直す。近くまで来ていれば見出しは組み立てられて
  /// いるので、1〜2回で収まる。
  void _jumpTo(String head) {
    final estimate = widget.offsets[head];
    if (estimate == null || !widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    widget.scrollController.jumpTo(
      estimate.clamp(0.0, position.maxScrollExtent),
    );
    _settleOn(head, remaining: 3);
  }

  void _settleOn(String head, {required int remaining}) {
    if (remaining <= 0) {
      _finishScrub();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final context = widget.headerKeys[head]?.currentContext;
      final box = context?.findRenderObject();
      final viewport = this.context.findRenderObject();
      if (box is! RenderBox || viewport is! RenderBox) return;
      // 見出しが索引の枠の上端からどれだけ下（＋）／上（−）にあるか。
      final delta = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (delta.abs() < 1) {
        _finishScrub();
        return;
      }
      final position = widget.scrollController.position;
      widget.scrollController.jumpTo(
        (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
      );
      _settleOn(head, remaining: remaining - 1);
    });
  }

  void _endDrag() {
    if (_dragging) setState(() => _dragging = false);
    _finishScrub();
  }

  /// 索引から手が離れ、送りも落ち着いたら、現在地の追従を戻す。
  ///
  /// 一覧が動いていない間はスクロールの通知も来ないので、
  /// 戻した時点で現在地が勝手に書き換わることはない。
  /// 次に利用者が一覧そのものを動かしたときから追従が効く。
  void _finishScrub() {
    if (!_scrubbing || _dragging) return;
    _scrubbing = false;
  }

  @override
  Widget build(BuildContext context) {
    final heads = widget.offsets.keys.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 枠の高さを行数で割って、1行ぶんの高さにする。指を滑らせたときに
        // 端から端まで途切れずに送れるよう、隙間を空けずに敷き詰める。
        final itemHeight = constraints.maxHeight / heads.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) {
            setState(() => _dragging = true);
            _handleTouch(d.localPosition, itemHeight);
          },
          onVerticalDragUpdate: (d) =>
              _handleTouch(d.localPosition, itemHeight),
          onVerticalDragEnd: (_) => _endDrag(),
          onVerticalDragCancel: _endDrag,
          onTapDown: (d) => _handleTouch(d.localPosition, itemHeight),
          child: SizedBox(
            width: 30,
            child: Column(
              children: [
                for (final head in heads)
                  SizedBox(
                    height: itemHeight,
                    child: Center(
                      child: _KanaIndexEntry(
                        head: head,
                        isCurrent: head == _current,
                        isDragging: _dragging,
                      ),
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

class _KanaIndexEntry extends StatelessWidget {
  const _KanaIndexEntry({
    required this.head,
    required this.isCurrent,
    required this.isDragging,
  });

  final String head;
  final bool isCurrent;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
        head,
        style: theme.textTheme.labelMedium?.copyWith(
          height: 1.0,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent
              ? theme.colorScheme.onPrimary
              // なぞっている間は触っていない行も少し濃くして、
              // 索引そのものが今の操作対象であることを示す。
              : isDragging
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 一覧の1行。
///
/// 早見表の印（★2・▶P9参照）を持つ品目は、行に収まる短さでは事情を
/// 伝えきれないので、押すと詳しい出し方を出す。印を持たない品目は
/// 行の文字がすべてなので押せるようにしない。
class _ItemTile extends StatelessWidget {
  const _ItemTile(this.item, {required this.manualUrl});

  final WasteItem item;
  final String manualUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetail = item.hasDetail;
    return ListTile(
      title: Text(item.name),
      subtitle: _subtitle(theme, hasDetail: hasDetail),
      trailing: CategoryPill(item: item),
      isThreeLine: _Results.subtitleLines(item) > 1,
      onTap: hasDetail
          ? () => showWasteItemSheet(context, item: item, manualUrl: manualUrl)
          : null,
    );
  }

  Widget? _subtitle(ThemeData theme, {required bool hasDetail}) {
    final note = item.note;
    if (!hasDetail) {
      return note.isEmpty
          ? null
          : Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
    }
    // 押せば続きがあることを、行の中で示す。注意点と同じ行に並べると
    // どちらも半端に切れるので、下に重ねる。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note.isNotEmpty)
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 13,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                item.marks.first.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
