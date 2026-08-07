import 'package:flutter/material.dart';

/// 区切り線と見出しの組。一覧の中の話題の変わり目に置く。
///
/// 線の上下の余白を同じにしておかないと、上の項目に張り付いて見えたり、
/// 逆に間延びして見えたりする。各所で数字を書き分けずにここに集約する。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
