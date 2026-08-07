import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../providers.dart';
import '../../ui/widgets/external_link.dart';
import '../../ui/widgets/section_header.dart';

/// アプリの素性を並べる画面。
///
/// 収集日を知りたいだけの利用者には用のない画面だが、
/// 「この情報はどこから来たのか」「個人情報はどう扱われるのか」を
/// 確かめたい人には要る。設定の最下部から入る。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  /// プライバシーポリシーの掲載先。アプリの外にあるので、
  /// 文面を直したいときはこのアプリのリリースを待たずに直せる。
  static const privacyPolicyUrl =
      'https://ktakada42.github.io/saitama-gomi-site/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalog = ref.watch(areaCatalogProvider).value;
    final dictionary = ref.watch(wasteDictionaryProvider).value;
    final packageInfo = ref.watch(packageInfoProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('このアプリについて')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appNameWithDisclaimer,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'さいたま市の家庭ごみの収集日と分別を確認するアプリです。'
                  'さいたま市が提供する公式のアプリではありません。',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SectionHeader('データの出典'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '収集日も分別も、さいたま市が公開している資料をもとにした要約です。'
              '町名地番や収集ルールの変更が反映されるまでにずれが生じることがあります。'
              '判断に迷うものや最新の情報は市の公式ページで確認してください。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // 収集日と分別早見表は別の資料から取っているので、それぞれ出す。
          // どちらか一方だけを見て「出典はこれ」と受け取られないようにする。
          if (catalog != null && catalog.source.isNotEmpty)
            _SourceTile(label: '収集日・地区', source: catalog.source),
          if (dictionary != null && dictionary.source.isNotEmpty)
            _SourceTile(label: '分別早見表', source: dictionary.source),
          if (catalog != null && catalog.sourceUrl.isNotEmpty) ...[
            const Divider(height: 1),
            ExternalLinkTile(
              icon: Icons.public,
              title: 'さいたま市の公式ページ',
              url: catalog.sourceUrl,
            ),
          ],
          const SectionHeader('このアプリ'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('バージョン'),
            trailing: Text(
              packageInfo == null
                  ? '—'
                  : '${packageInfo.version} (${packageInfo.buildNumber})',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const Divider(height: 1),
          const ExternalLinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'プライバシーポリシー',
            url: privacyPolicyUrl,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('ライセンス'),
            subtitle: const Text('このアプリが使っているソフトウェアとフォント'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: appNameWithDisclaimer,
              applicationVersion: packageInfo == null
                  ? null
                  : '${packageInfo.version} (${packageInfo.buildNumber})',
            ),
          ),
        ],
      ),
    );
  }
}

/// 出典の一件。押せる項目と紛れないよう、右端には何も置かない。
class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.label, required this.source});

  final String label;
  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(source, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
