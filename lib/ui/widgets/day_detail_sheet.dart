import 'package:flutter/material.dart';

import '../paren_wrap.dart';
import '../../domain/collection_area.dart';
import '../../domain/collection_calendar.dart';
import '../../domain/date_label.dart';
import '../../domain/garbage_category.dart';
import '../category_style.dart';

/// ある日の収集内容を出すボトムシート。カレンダーの日タップとホームから共用する。
Future<void> showDayDetailSheet(
  BuildContext context, {
  required CollectionDay day,
  required CollectionArea area,
  required DateTime today,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // 高さの上限を決めておく。決めないと、5区分が重なる日を狭い画面で開いた
    // ときにシートが画面いっぱいに広がり、外側を押して閉じることも
    // つまみを掴んで下げることもできなくなる。
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    builder: (context) => _DayDetailSheet(day: day, area: area, today: today),
  );
}

class _DayDetailSheet extends StatelessWidget {
  const _DayDetailSheet({
    required this.day,
    required this.area,
    required this.today,
  });

  final CollectionDay day;
  final CollectionArea area;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateLabel.headline(day.date, today),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (day.isEmpty)
              Text(
                CollectionCalendar.isSuspended(day.date)
                    ? '年末年始のため収集はお休みです。'
                    : '収集はありません。',
                style: theme.textTheme.bodyLarge,
              )
            else
              for (final category in day.categories) ...[
                _CategoryDetail(
                  category: category,
                  deadline: area.depositDeadline(category),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _CategoryDetail extends StatelessWidget {
  const _CategoryDetail({required this.category, required this.deadline});

  final GarbageCategory category;
  final String deadline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = CategoryStyle.colorOf(category, context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CategoryStyle.iconOf(category), color: color),
              const SizedBox(width: 8),
              Text(
                category.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '朝$deadlineまで',
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            keepParenthesesTogether(category.examples.join('・')),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            keepParenthesesTogether(category.howTo),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
