import 'package:flutter/material.dart';

import '../../domain/garbage_category.dart';
import '../category_style.dart';

/// 区分ひとつを表す小さなラベル。リストやカレンダーの詳細で使う。
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.dense = false});

  final GarbageCategory category;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.colorOf(category, context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CategoryStyle.iconOf(category),
            size: dense ? 14 : 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            category.label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 区分の色を持つ小さな点。カレンダーのセルに並べる。
class CategoryDot extends StatelessWidget {
  const CategoryDot(this.category, {super.key, this.size = 6});

  final GarbageCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: CategoryStyle.colorOf(category, context),
        shape: BoxShape.circle,
      ),
    );
  }
}
