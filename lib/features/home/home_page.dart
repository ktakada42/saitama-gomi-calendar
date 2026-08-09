import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/paren_wrap.dart';
import '../../domain/collection_area.dart';
import '../../domain/collection_calendar.dart';
import '../../domain/date_label.dart';
import '../../domain/garbage_category.dart';
import '../../providers.dart';
import '../../ui/category_style.dart';
import '../../ui/widgets/category_badge.dart';
import '../../ui/widgets/day_detail_sheet.dart';

/// トップページ。知りたいのはまず「明日は何ごみか」なので、
/// 明日をいちばん大きく出し、今日・その先はその下に置く。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendar = ref.watch(calendarProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowProvider);
    if (calendar == null) return const SizedBox.shrink();

    final area = calendar.area;
    // 収集日の朝は、出す期限を過ぎるまで「今日」を大きく出す。
    // まだ出しに行けるのに「明日」を大きく出すと、その日の収集を逃す。
    final featured = calendar.featuredDay(now);
    final isFeaturingToday = CollectionCalendar.isSameDate(
      featured.date,
      today,
    );
    // 大きく出していない方を、下の小さい行に回す。
    final secondary = calendar.dayOf(
      isFeaturingToday ? today.add(const Duration(days: 1)) : today,
    );
    // 今日と明日は個別に出すので、一覧はあさって以降から。
    final upcoming = calendar.upcoming(
      today.add(const Duration(days: 2)),
      limit: 6,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(keepParenthesesTogether('${area.ward}　${area.name}')),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _FeaturedCard(
            day: featured,
            area: area,
            today: today,
            label: isFeaturingToday ? '今日' : '明日',
          ),
          const SizedBox(height: 12),
          _SecondaryRow(
            day: secondary,
            area: area,
            today: today,
            label: isFeaturingToday ? '明日' : '今日',
          ),
          const SizedBox(height: 24),
          if (area.isEmpty)
            const _EmptyAreaNotice()
          else ...[
            _SectionTitle('この先の収集'),
            const SizedBox(height: 8),
            if (upcoming.isEmpty)
              const Text('この先しばらく収集の予定がありません。')
            else
              for (final day in upcoming)
                _UpcomingTile(day: day, area: area, today: today),
            const SizedBox(height: 24),
            _SectionTitle('分別ごとの次の収集'),
            const SizedBox(height: 8),
            _NextByCategory(calendar: calendar, today: today),
          ],
        ],
      ),
    );
  }
}

/// いちばん大きく出す収集日。ふだんは明日、収集日の朝は今日。
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.day,
    required this.area,
    required this.today,
    required this.label,
  });

  final CollectionDay day;
  final CollectionArea area;
  final DateTime today;

  /// 「今日」か「明日」。
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 複数区分ある日は先頭の色で塗る。カードの色はあくまで手がかりで、
    // 中身は下のバッジで全部読めるようにしてある。
    final accent = day.isEmpty
        ? theme.colorScheme.outline
        : CategoryStyle.colorOf(day.categories.first, context);

    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () =>
            showDayDetailSheet(context, day: day, area: area, today: today),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateLabel.monthDay(day.date),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (day.isEmpty)
                Text(
                  CollectionCalendar.isSuspended(day.date)
                      ? '年末年始のお休み'
                      : '収集はありません',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                for (final category in day.categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          CategoryStyle.iconOf(category),
                          color: CategoryStyle.colorOf(category, context),
                          size: 32,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            category.label,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: CategoryStyle.colorOf(category, context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '朝${area.depositDeadline(day.categories.first)}までに出す',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  day.categories.first.howTo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 大きく出していない方の日。今日か明日のどちらか。
class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({
    required this.day,
    required this.area,
    required this.today,
    required this.label,
  });

  final CollectionDay day;
  final CollectionArea area;
  final DateTime today;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () =>
          showDayDetailSheet(context, day: day, area: area, today: today),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: day.isEmpty
                  ? Text(
                      '収集なし',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final category in day.categories)
                          CategoryBadge(category, dense: true),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({
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
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () =>
          showDayDetailSheet(context, day: day, area: area, today: today),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                DateLabel.headlineWrapped(day.date, today),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in day.categories)
                    CategoryBadge(category, dense: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「次のもえないごみはいつか」を1画面で答えるための一覧。
/// 月1回しかない区分は日付一覧を眺めても見つけにくいので独立して出す。
class _NextByCategory extends StatelessWidget {
  const _NextByCategory({required this.calendar, required this.today});

  final CollectionCalendar calendar;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final category in GarbageCategory.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                CategoryBadge(category, dense: true),
                const Spacer(),
                Builder(
                  builder: (context) {
                    final next = calendar.nextFor(category, today);
                    if (next == null) {
                      return Text(
                        '未設定',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }
                    return Text(
                      DateLabel.headline(next.date, today),
                      style: theme.textTheme.bodyMedium,
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyAreaNotice extends StatelessWidget {
  const _EmptyAreaNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '収集曜日がまだ設定されていません。「設定」から地区の曜日を登録してください。',
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
