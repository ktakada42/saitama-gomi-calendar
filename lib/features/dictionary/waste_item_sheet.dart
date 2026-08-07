import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/waste_item.dart';
import '../../ui/widgets/category_pill.dart';

/// 品目1件の詳しい出し方。
///
/// 早見表は紙の冊子なので、注意点に「★2」「▶P9参照」といった印だけを置き、
/// 意味は脚注や別のページに書いてある。冊子を持たない利用者には通じないので、
/// ここで言葉にして見せる。
Future<void> showWasteItemSheet(
  BuildContext context, {
  required WasteItem item,
  required String manualUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _WasteItemSheet(item: item, manualUrl: manualUrl),
  );
}

class _WasteItemSheet extends StatelessWidget {
  const _WasteItemSheet({required this.item, required this.manualUrl});

  final WasteItem item;
  final String manualUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = item.marks;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CategoryPill(item: item),
                ],
              ),
              if (item.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(item.note, style: theme.textTheme.bodyMedium),
              ],
              for (final mark in marks) ...[
                const SizedBox(height: 20),
                Text(
                  mark.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(mark.description, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              // 要約なので、判断に迷うときは元の資料に当たれるようにする。
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(manualUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('市の家庭ごみの出し方マニュアル'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
