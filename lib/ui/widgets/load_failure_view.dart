import 'package:flutter/material.dart';

/// 同梱データや設定の読み込みに失敗したときの表示。
///
/// 同梱アセットの読み込みは通常失敗しないが、失敗した場合に生の例外文字列を
/// 見せても利用者には何もできない。何が起きていて次に何をすればよいかだけを
/// 伝え、やり直す手段を出す。
class LoadFailureView extends StatelessWidget {
  const LoadFailureView({super.key, required this.message, this.onRetry});

  /// 何が読み込めなかったのかを一言で。
  final String message;

  /// 再試行の手段。無いなら null。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'アプリを再起動しても直らない場合は、入れ直してみてください。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('もう一度試す'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
