import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 外部のページを開く一覧の項目。
///
/// アプリ内のWebViewではなく外部ブラウザ（Safari）で開く。市の公式ページや
/// プライバシーポリシーを、このアプリの一部と誤解させないため。
/// 開くのはブラウザに引き渡すだけなので、アプリ自身は通信しない。
class ExternalLinkTile extends StatelessWidget {
  const ExternalLinkTile({
    required this.icon,
    required this.title,
    required this.url,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      // 次の画面へ進むのではなく、アプリの外へ出ることを右端で示す。
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ページを開けませんでした。')));
  }
}
