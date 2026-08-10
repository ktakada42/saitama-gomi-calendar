import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/collection_boxes.dart';
import '../../providers.dart';
import '../../ui/paren_wrap.dart';
import '../../ui/widgets/external_link.dart';
import '../../ui/widgets/load_failure_view.dart';
import '../../ui/widgets/section_header.dart';

/// 小型家電・電池の回収ボックス。
///
/// 早見表は「回収ボックスへ」としか書いておらず、どこにあるのかが分からない。
/// このアプリは地区を設定してもらっているので区が分かる。
/// 全55か所を読ませずに、その区のぶんを先に出す。
class CollectionBoxesPage extends ConsumerWidget {
  const CollectionBoxesPage({this.focusedBoxId, super.key});

  /// どの箱から来たか。品目が小型家電か電池かで、先に見せるものが変わる。
  final String? focusedBoxId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boxes = ref.watch(collectionBoxesProvider);
    final ward = ref.watch(selectedAreaProvider).value?.ward;

    return Scaffold(
      appBar: AppBar(title: const Text('回収ボックス')),
      body: switch (boxes) {
        AsyncData(:final value) => _Body(
          boxes: value,
          ward: ward,
          focusedBoxId: focusedBoxId,
        ),
        AsyncError() => LoadFailureView(
          message: '回収ボックスの案内を読み込めませんでした。',
          onRetry: () => ref.invalidate(collectionBoxesProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.boxes,
    required this.ward,
    required this.focusedBoxId,
  });

  final CollectionBoxes boxes;
  final String? ward;
  final String? focusedBoxId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = boxes.placesIn(ward);

    // 品目から来たときは、その箱を先に。順番を入れ替えるだけで、
    // どちらも見られる状態は保つ（どちらに入れるか迷う品目がある）。
    final kinds = [...boxes.boxes]
      ..sort((a, b) {
        if (a.id == focusedBoxId) return -1;
        if (b.id == focusedBoxId) return 1;
        return 0;
      });

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // 設定済みの区があるなら、そこを最初に出す。
        // 55か所の一覧から自分の区を探させるのは、地区を知っている
        // アプリのやることではない。
        if (mine != null) ...[
          const SizedBox(height: 16),
          _MyWardCard(places: mine, hours: boxes.hours),
        ],

        for (final kind in kinds) ...[
          const SizedBox(height: 20),
          _BoxCard(kind: kind),
        ],

        SectionHeader(mine == null ? '設置場所' : 'ほかの区の設置場所'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '市内${boxes.totalPlaces}か所。${boxes.hours}。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final place in boxes.places)
          if (place.ward != ward) _WardTile(places: place),

        for (final note in boxes.notes)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              keepParenthesesTogether(note),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        const SectionHeader('入らない大きさのとき'),
        _TooLargeCard(guide: boxes.tooLarge),

        const SectionHeader('自宅まで取りに来てもらう'),
        _HomePickupCard(pickup: boxes.homePickup),

        const SectionHeader('出典'),
        ExternalLinkTile(
          icon: Icons.description_outlined,
          title: boxes.source,
          subtitle: 'さいたま市（設置場所はこの資料の記載です）',
          url: boxes.sourceUrl,
        ),
      ],
    );
  }
}

class _MyWardCard extends StatelessWidget {
  const _MyWardCard({required this.places, required this.hours});

  final WardPlaces places;
  final String hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                '${places.ward}の設置場所',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final name in places.names)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                keepParenthesesTogether(name),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            hours,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoxCard extends StatelessWidget {
  const _BoxCard({required this.kind});

  final BoxKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kind.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 現地では色で見分ける。名前より先に目に入る手がかり。
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  kind.color,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            keepParenthesesTogether(kind.accepts),
            style: theme.textTheme.bodyMedium,
          ),
          if (kind.examples.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final example in kind.examples)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(example, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ],
          for (final note in kind.notes) ...[
            const SizedBox(height: 8),
            Text(
              keepParenthesesTogether(note),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WardTile extends StatelessWidget {
  const _WardTile({required this.places});

  final WardPlaces places;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(places.ward, style: theme.textTheme.bodyMedium),
        subtitle: Text(
          '${places.names.length}か所',
          style: theme.textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final name in places.names)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                keepParenthesesTogether(name),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _TooLargeCard extends StatelessWidget {
  const _TooLargeCard({required this.guide});

  final TooLargeGuide guide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            keepParenthesesTogether(guide.body),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text('例：${guide.examples}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('場所：${guide.place}', style: theme.textTheme.bodySmall),
          for (final note in guide.notes) ...[
            const SizedBox(height: 4),
            Text(
              keepParenthesesTogether(note),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomePickupCard extends StatelessWidget {
  const _HomePickupCard({required this.pickup});

  final HomePickup pickup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            keepParenthesesTogether(pickup.body),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 6),
        ListTile(
          leading: const Icon(Icons.call),
          title: Text(pickup.phone),
          subtitle: Text(pickup.hours),
          onTap: () => _call(context, pickup.phone),
        ),
        ExternalLinkTile(
          icon: Icons.public,
          title: 'リネットジャパンリサイクル',
          url: pickup.url,
        ),
        for (final note in pickup.notes)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              keepParenthesesTogether(note),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
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
