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
          // 収集日と分別早見表は表が別なので、それぞれ出す。どちらか一方だけを
          // 見て「出典はこれ」と受け取られないようにする。どちらも同じ
          // 「家庭ごみの出し方マニュアル」の中の別の表なので、開く先は同じになる。
          if (catalog != null && catalog.source.isNotEmpty) ...[
            ExternalLinkTile(
              icon: Icons.event_note_outlined,
              title: '収集日・地区',
              subtitle: catalog.source,
              url: catalog.sourceUrl,
            ),
            const Divider(height: 1),
          ],
          if (dictionary != null && dictionary.source.isNotEmpty)
            ExternalLinkTile(
              icon: Icons.menu_book_outlined,
              title: '分別早見表',
              subtitle: dictionary.source,
              url: dictionary.sourceUrl,
            ),
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
