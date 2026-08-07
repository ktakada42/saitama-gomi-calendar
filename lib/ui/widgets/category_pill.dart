import 'package:flutter/material.dart';

import '../../domain/waste_item.dart';
import '../category_style.dart';

/// 出し先を表すピル。ホームやカレンダーの区分バッジと同じ見た目にする。
///
/// 5区分でない出し先（粗大ごみ・小型家電・電池・収集できないもの）にも
/// 同じ形を使う。利用者から見ればどれも「どこに出すか」で区別はないため。
class CategoryPill extends StatelessWidget {
  const CategoryPill({required this.item, super.key});

  final WasteItem item;

  /// 5区分に入らない出し先のアイコン。
  static const _fallbackIcons = {
    'oversized': Icons.chair_outlined,
    'smallAppliance': Icons.devices_other,
    'battery': Icons.battery_full,
    'notAccepted': Icons.block,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = item.category;
    // 5区分なら区分色を使う。収集日を持たない出し先は、区分色と
    // 紛らわしくならないよう控えめな色にする。
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : CategoryStyle.colorOf(category, context);
    final icon = category == null
        ? (_fallbackIcons[item.categoryId] ?? Icons.place_outlined)
        : CategoryStyle.iconOf(category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            item.shortCategoryLabel,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
