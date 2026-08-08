import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/collection_calendar.dart';
import '../../domain/date_label.dart';
import '../../domain/garbage_category.dart';
import '../../providers.dart';
import '../../ui/category_style.dart';
import '../../ui/widgets/category_badge.dart';
import '../../ui/widgets/day_detail_sheet.dart';

/// 当月のごみ出し日を一覧するカレンダー。
/// 月をまたいで前後に送れる（来月の予定を確認したいことがあるため）。
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  /// 表示中の月。日は1に固定しておく。
  DateTime? _month;

  /// 月をまたぐ送りを、指の動きに追従させるための紙送り。
  ///
  /// 月は無限に続くので、ページに端は作らない。真ん中を今月として、
  /// そこからの差でどの月かを決める。前後に約100年ぶんあれば、
  /// 端に突き当たることはない。
  PageController? _pageController;
  static const _basePage = 1200;

  /// [_basePage] の指す月。ここを起点にページ番号と月を行き来する。
  DateTime? _baseMonth;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  DateTime _monthOfPage(int page) =>
      DateTime(_baseMonth!.year, _baseMonth!.month + page - _basePage);

  int _pageOfMonth(DateTime month) =>
      _basePage +
      (month.year - _baseMonth!.year) * 12 +
      (month.month - _baseMonth!.month);

  @override
  Widget build(BuildContext context) {
    final calendar = ref.watch(calendarProvider);
    final today = ref.watch(todayProvider);
    if (calendar == null) return const SizedBox.shrink();

    final month = _month ??= DateTime(today.year, today.month);
    _baseMonth ??= DateTime(today.year, today.month);
    _pageController ??= PageController(initialPage: _pageOfMonth(month));

    final isThisMonth = month.year == today.year && month.month == today.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('カレンダー'),
        actions: [
          // 月送りとは別のボタンにする。年月の並びに混ぜると、
          // 出たり消えたりするたびに年月が中央からずれてしまう。
          if (!isThisMonth)
            TextButton(
              onPressed: () => _goTo(DateTime(today.year, today.month)),
              child: const Text('今月に戻る'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        children: [
          _MonthHeader(
            month: month,
            onPrevious: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          const SizedBox(height: 8),
          const _WeekdayHeader(),
          const SizedBox(height: 4),
          // 左右になぞって月を送る。紙送りにしてあるので、指の動きに合わせて
          // 今の月が横へ抜け、隣の月が入ってくる。
          //
          // 高さは6週ぶんで固定する。月によって5週と6週があり、そのままだと
          // 送るたびに表の高さが変わって下の凡例が上下に動く。
          SizedBox(
            height: _MonthGrid.rowHeight * _MonthGrid.maxRows,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (page) =>
                  setState(() => _month = _monthOfPage(page)),
              itemBuilder: (context, page) {
                final pageMonth = _monthOfPage(page);
                return _MonthGrid(
                  month: pageMonth,
                  days: calendar.month(pageMonth.year, pageMonth.month),
                  today: today,
                  onTapDay: (day) => showDayDetailSheet(
                    context,
                    day: day,
                    area: calendar.area,
                    today: today,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const _Legend(),
        ],
      ),
    );
  }

  void _shiftMonth(int delta) {
    final current = _month!;
    _goTo(DateTime(current.year, current.month + delta));
  }

  /// ボタンから月を変えるときも、なぞったときと同じように送る。
  void _goTo(DateTime month) {
    _pageController!.animateToPage(
      _pageOfMonth(month),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: '前の月',
        ),
        Expanded(
          child: Center(
            child: Text(
              DateLabel.yearMonth(month.year, month.month),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: '次の月',
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _labels = ['日', '月', '火', '水', '木', '金', '土'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                _labels[i],
                style: theme.textTheme.labelMedium?.copyWith(
                  color: switch (i) {
                    0 => theme.colorScheme.error,
                    6 => theme.colorScheme.primary,
                    _ => theme.colorScheme.onSurfaceVariant,
                  },
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  /// 1週ぶんの高さ。
  static const rowHeight = 74.0;

  /// 月が取りうる最大の週数。1日が土曜で31日ある月がこれになる。
  static const maxRows = 6;

  const _MonthGrid({
    required this.month,
    required this.days,
    required this.today,
    required this.onTapDay,
  });

  final DateTime month;
  final List<CollectionDay> days;
  final DateTime today;
  final void Function(CollectionDay) onTapDay;

  @override
  Widget build(BuildContext context) {
    // 日曜始まりの表なので、1日の前に置く空きマスの数は
    // 「1日の曜日」を日曜=0に読み替えた値になる。
    final leading = DateTime(month.year, month.month, 1).weekday % 7;
    final cells = <Widget?>[
      for (var i = 0; i < leading; i++) null,
      for (final day in days)
        _DayCell(
          day: day,
          isToday: CollectionCalendar.isSameDate(day.date, today),
          onTap: () => onTapDay(day),
        ),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      // 6週に満たない月は下に空きを残す。表の高さを揃えるため。
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (var row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: SizedBox(
                    height: rowHeight,
                    child: cells[row * 7 + col] ?? const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.onTap,
  });

  final CollectionDay day;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = day.date.weekday;
    final numberColor = switch (weekday) {
      DateTime.sunday => theme.colorScheme.error,
      DateTime.saturday => theme.colorScheme.primary,
      _ => theme.colorScheme.onSurface,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isToday
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : null,
          border: isToday
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '${day.date.day}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: numberColor,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            // 区分名は幅に入りきらないので、セルでは色の帯＋短い名称にする。
            // 名称も出しておかないと色だけが手がかりになってしまうため。
            Expanded(
              child: Column(
                children: [
                  // マスに入るのは3段まで。4区分以上ある日は3段目を
                  // 「+2」の表示に使う。帯を3本出したうえで「+2」を足すと
                  // 4段になってマスから溢れる。
                  for (final category in day.categories.take(
                    day.categories.length > _maxStrips
                        ? _maxStrips - 1
                        : _maxStrips,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: _CategoryStrip(category: category),
                    ),
                  if (day.categories.length > _maxStrips)
                    Text(
                      '+${day.categories.length - _maxStrips + 1}',
                      // 帯と同じ行送りにする。既定の行送りだと3段目だけ
                      // 高くなり、マスから溢れる。
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// マスに収まる段数。区分名の帯と「+2」の表示を合わせてこの数まで。
const _maxStrips = 3;

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.category});

  final GarbageCategory category;

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.colorOf(category, context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            category.shortLabel,
            style: TextStyle(
              fontSize: 10,
              height: 1.3,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in GarbageCategory.values) CategoryBadge(category),
      ],
    );
  }
}
