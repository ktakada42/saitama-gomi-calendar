import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/oversized_guide.dart';
import '../../providers.dart';
import '../../ui/paren_wrap.dart';
import '../../ui/widgets/external_link.dart';
import '../../ui/widgets/load_failure_view.dart';
import '../../ui/widgets/section_header.dart';

/// 粗大ごみの出し方。
///
/// 早見表は「直接持込みまたは戸別収集」としか書いていない。いくらかかるのか、
/// どこへ申し込むのかが分からないままでは、結局調べ直すことになる。
///
/// 知りたい順に並べる。まず自分のものが粗大ごみに当たるのか（大きさ）、
/// 次にいくらか、最後にどう申し込むか。
class OversizedGuidePage extends ConsumerWidget {
  const OversizedGuidePage({this.highlightedItem, super.key});

  /// どの品目から来たか。個別の料金が決まっていれば、それを先に出す。
  final String? highlightedItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(oversizedGuideProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('粗大ごみの出し方')),
      body: switch (guide) {
        AsyncData(:final value) => _Body(
          guide: value,
          highlightedItem: highlightedItem,
        ),
        AsyncError() => LoadFailureView(
          message: '粗大ごみの案内を読み込めませんでした。',
          onRetry: () => ref.invalidate(oversizedGuideProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.guide, required this.highlightedItem});

  final OversizedGuide guide;
  final String? highlightedItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = highlightedItem == null ? null : guide.feeFor(highlightedItem!);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _SizeCard(definition: guide.definition),

        // この品目だけ大きさに関わらず料金が決まっている、という場合。
        // 一般の料金を読ませてから訂正するより、先に出したほうがよい。
        if (fee != null) ...[
          const SectionHeader('この品目の料金'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SpecialFeeCard(fee: fee),
          ),
        ],

        const SectionHeader('出す方法は2つ'),
        for (final method in guide.methods)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _MethodCard(method: method),
          ),

        const SectionHeader('大きさに関わらず料金が決まっているもの'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            guide.specialFees.note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _FeeTable(fees: guide.specialFees.items, highlighted: fee),

        const SectionHeader('取りに来てもらう場合の手順'),
        for (final (index, step) in guide.steps.indexed)
          _StepTile(number: index + 1, step: step),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            guide.stepsNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        const SectionHeader('粗大ごみとしては出せないもの'),
        for (final item in guide.exclusions)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 8),
                  child: Icon(
                    Icons.remove,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Text(
                    keepParenthesesTogether(item),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

        const SectionHeader('出典'),
        ExternalLinkTile(
          icon: Icons.description_outlined,
          title: guide.source,
          subtitle: 'さいたま市（金額・受付先はこの資料の記載です）',
          url: guide.sourceUrl,
        ),
      ],
    );
  }
}

/// まず「自分のものが粗大ごみに当たるのか」に答える。
///
/// 2m以上を書いておかないと、大きいものほど粗大ごみだと思われる。
/// 実際には大きすぎると市では扱えない。
class _SizeCard extends StatelessWidget {
  const _SizeCard({required this.definition});

  final OversizedDefinition definition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '粗大ごみとは',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            definition.oversized,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            keepParenthesesTogether(definition.tooLarge),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(definition.note, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.method});

  final DisposalMethod method;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        method.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Badge(text: method.badge),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  method.fee,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(method.feeNote, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text('支払い：${method.payment}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 電話は、押したらかけられる。番号を覚えて電話アプリに打ち直させない。
          ListTile(
            leading: const Icon(Icons.call),
            title: Text(method.phone),
            subtitle: Text('${method.contactName}\n${method.phoneHours}'),
            isThreeLine: true,
            onTap: () => _call(context, method.phone),
          ),
          ExternalLinkTile(
            icon: Icons.event_available_outlined,
            title: method.urlLabel,
            url: method.url,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _Notes(notes: method.notes),
          ),
        ],
      ),
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    final placed = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (placed || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('電話をかけられませんでした。')));
  }
}

/// 注意書きは畳んでおく。数が多く、読まないと申し込めないものでもない。
class _Notes extends StatelessWidget {
  const _Notes({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (notes.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          '注意すること（${notes.length}件）',
          style: theme.textTheme.bodySmall,
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 6),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      keepParenthesesTogether(note),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeeTable extends StatelessWidget {
  const _FeeTable({required this.fees, required this.highlighted});

  final List<SpecialFeeItem> fees;
  final SpecialFeeItem? highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              const Spacer(),
              _headCell(theme, '持ち込む'),
              _headCell(theme, '来てもらう'),
            ],
          ),
        ),
        for (final fee in fees)
          Container(
            color: identical(fee, highlighted)
                ? theme.colorScheme.primaryContainer
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        keepParenthesesTogether(fee.name),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (fee.note.isNotEmpty)
                        Text(
                          keepParenthesesTogether(fee.note),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                _yenCell(theme, fee.dropOffYen),
                _yenCell(theme, fee.doorToDoorYen),
              ],
            ),
          ),
      ],
    );
  }

  Widget _headCell(ThemeData theme, String text) => SizedBox(
    width: 72,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _yenCell(ThemeData theme, int yen) => SizedBox(
    width: 72,
    child: Text(
      '${_comma(yen)}円',
      textAlign: TextAlign.right,
      // 桁を揃えて、金額の大小が縦に見えるようにする。
      style: theme.textTheme.bodyMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );

  static String _comma(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

class _SpecialFeeCard extends StatelessWidget {
  const _SpecialFeeCard({required this.fee});

  final SpecialFeeItem fee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            keepParenthesesTogether(fee.name),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _amount(theme, '持ち込む', fee.dropOffYen)),
              Expanded(child: _amount(theme, '来てもらう', fee.doorToDoorYen)),
            ],
          ),
          if (fee.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(fee.note, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _amount(ThemeData theme, String label, int yen) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: theme.textTheme.labelSmall),
      Text(
        '${_FeeTable._comma(yen)}円',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.step});

  final int number;
  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2, right: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  keepParenthesesTogether(step.body),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
