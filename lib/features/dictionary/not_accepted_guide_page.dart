import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/not_accepted_guide.dart';
import '../../providers.dart';
import '../../ui/paren_wrap.dart';
import '../../ui/widgets/external_link.dart';
import '../../ui/widgets/load_failure_view.dart';
import '../../ui/widgets/section_header.dart';

/// 市では収集・処理できないものの持って行き先。
///
/// 「市では無理です」で終わらせず、どこへ連絡すればよいかまで見せる。
/// 品目から開いたときは、その品目の行き先だけを出す。全部を読ませて
/// 自分で探させると、行き先を取り違える。
class NotAcceptedGuidePage extends ConsumerWidget {
  const NotAcceptedGuidePage({this.focusedItem, super.key});

  /// どの品目から来たか。行き先が決まっていれば、それだけを出す。
  final String? focusedItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(notAcceptedGuideProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('市では収集できないもの')),
      body: switch (guide) {
        AsyncData(:final value) => _Body(
          guide: value,
          focusedItem: focusedItem,
        ),
        AsyncError() => LoadFailureView(
          message: '持って行き先の案内を読み込めませんでした。',
          onRetry: () => ref.invalidate(notAcceptedGuideProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.guide, required this.focusedItem});

  final NotAcceptedGuide guide;
  final String? focusedItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = focusedItem == null
        ? null
        : guide.destinationFor(focusedItem!);
    final shown = focused == null ? guide.destinations : [focused];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            focused == null
                ? guide.lead
                : '「$focusedItem」は市では収集・処理できません。次の窓口へご相談ください。',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        for (final destination in shown) ...[
          const SizedBox(height: 20),
          _DestinationCard(destination: destination),
        ],

        // 品目から来たときは、他の行き先も見られるようにしておく。
        // 「これで合っているのか」を確かめたくなることがある。
        if (focused != null) ...[
          const SectionHeader('ほかの持って行き先'),
          for (final other in guide.destinations)
            if (other.id != focused.id)
              ListTile(
                dense: true,
                title: Text(other.title),
                subtitle: other.summary.isEmpty ? null : Text(other.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _SingleDestinationPage(destination: other),
                  ),
                ),
              ),
        ],

        if (focused == null) ...[
          const SectionHeader('そのほか'),
          for (final note in guide.otherNotes)
            _Bullet(text: note, style: theme.textTheme.bodyMedium),
        ],

        const SectionHeader('出典'),
        ExternalLinkTile(
          icon: Icons.description_outlined,
          title: guide.source,
          subtitle: 'さいたま市（窓口・連絡先はこの資料の記載です）',
          url: guide.sourceUrl,
        ),
      ],
    );
  }
}

class _SingleDestinationPage extends StatelessWidget {
  const _SingleDestinationPage({required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(destination.title)),
      body: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 32),
        children: [_DestinationCard(destination: destination)],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                Text(
                  destination.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (destination.summary.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    keepParenthesesTogether(destination.summary),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  keepParenthesesTogether(destination.body),
                  style: theme.textTheme.bodyMedium,
                ),
                if (destination.options.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '出し方',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final option in destination.options)
                    _Bullet(
                      text: option,
                      style: theme.textTheme.bodySmall,
                      inset: false,
                    ),
                ],
              ],
            ),
          ),
          if (destination.contacts.isNotEmpty) const SizedBox(height: 6),
          for (final contact in destination.contacts) ...[
            ListTile(
              leading: const Icon(Icons.call),
              title: Text(contact.phone),
              subtitle: Text(_contactSubtitle(contact)),
              isThreeLine: _contactSubtitle(contact).contains('\n'),
              onTap: () => _call(context, contact.phone),
            ),
            if (contact.url.isNotEmpty)
              ExternalLinkTile(
                icon: Icons.public,
                title: contact.name,
                url: contact.url,
              ),
          ],
          if (destination.notes.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                destination.contacts.isEmpty ? 12 : 4,
                16,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final note in destination.notes)
                    _Bullet(
                      text: note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      inset: false,
                    ),
                ],
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }

  String _contactSubtitle(Contact contact) {
    final lines = [
      if (contact.detail.isNotEmpty)
        '${contact.name}（${contact.detail}）'
      else
        contact.name,
      if (contact.hours.isNotEmpty) contact.hours,
    ];
    return lines.join('\n');
  }

  Future<void> _call(BuildContext context, String phone) async {
    final placed = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (placed || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('電話をかけられませんでした。')));
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.style, this.inset = true});

  final String text;
  final TextStyle? style;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(inset ? 16 : 0, 0, inset ? 16 : 0, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Icon(
              Icons.circle,
              size: 5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(child: Text(keepParenthesesTogether(text), style: style)),
        ],
      ),
    );
  }
}
