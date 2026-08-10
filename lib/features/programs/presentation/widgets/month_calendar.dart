import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../domain/scheduled_workout_row.dart';
import '../programs_providers.dart';
import 'session_tile.dart';

/// Hand-rolled month grid. Each cell shows status dots for the day's sessions
/// and accepts a session dragged from the day sheet, so a move is: open a day,
/// drag its session onto another cell.
///
/// Deliberately not a calendar package — the pill-and-dot language mirrors the
/// dashboard's `WorkoutCalendarCard`, and a package would fight the theme.
class MonthCalendar extends ConsumerWidget {
  const MonthCalendar({
    super.key,
    required this.anchor,
    required this.programId,
    required this.selected,
    required this.onSelect,
  });

  /// Any date inside the month to show.
  final DateTime anchor;
  final int? programId;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final range = ScheduleRange.monthGrid(anchor, programId: programId);
    final byDate = ref.watch(scheduleByDateProvider(range));
    final events = ref.watch(externalEventsProvider).value ?? const [];

    final gridStart = range.from;
    final gridEnd = range.to;
    final dayCount = gridEnd.difference(gridStart).inDays + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        byDate.when(
          loading: () => const SizedBox(
            height: 260,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SizedBox(
            height: 260,
            child: Center(
              child: Text(
                'Could not load this month.',
                style: TextStyle(color: AppColors.secondary),
              ),
            ),
          ),
          data: (map) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.82,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: dayCount,
            itemBuilder: (context, i) {
              final date = gridStart.add(Duration(days: i));
              final iso = _iso(date);
              return _DayCell(
                date: date,
                rows: map[iso] ?? const [],
                inMonth: date.month == anchor.month,
                isSelected: _sameDay(date, selected),
                hasEvent: events.any(
                  (e) =>
                      iso.compareTo(e.dateFromIso) >= 0 &&
                      iso.compareTo(e.dateToIso) <= 0,
                ),
                onTap: () => onSelect(date),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _SelectedDayList(
          date: selected,
          rows: byDate.value?[_iso(selected)] ?? const [],
          onOpenSession: onSelect,
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.date,
    required this.rows,
    required this.inMonth,
    required this.isSelected,
    required this.hasEvent,
    required this.onTap,
  });

  final DateTime date;
  final List<ScheduledWorkoutRow> rows;
  final bool inMonth;
  final bool isSelected;
  final bool hasEvent;
  final VoidCallback onTap;

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => !rows.any((r) => r.id == d.data),
      onAcceptWithDetails: (d) async {
        Haptics.success();
        await ref
            .read(programsRepositoryProvider)
            .moveScheduledWorkout(scheduleId: d.data, newDate: date);
      },
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return GestureDetector(
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: hovering
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : isSelected
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : hasEvent
                  ? AppColors.tertiary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hovering || isSelected
                    ? AppColors.primary
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _isToday ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${date.day}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: _isToday ? FontWeight.w700 : FontWeight.w500,
                      color: _isToday
                          ? Colors.white
                          : inMonth
                          ? null
                          : AppColors.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final row in rows.take(3))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: scheduleStatusColor(
                              row.status,
                            ).withValues(alpha: inMonth ? 1 : 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (rows.length > 3)
                        Text(
                          '+${rows.length - 3}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 8,
                            color: AppColors.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The selected day's sessions, draggable onto any cell above.
class _SelectedDayList extends StatelessWidget {
  const _SelectedDayList({
    required this.date,
    required this.rows,
    required this.onOpenSession,
  });

  final DateTime date;
  final List<ScheduledWorkoutRow> rows;
  final ValueChanged<DateTime> onOpenSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE, MMM d').format(date).toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Rest day — tap the date to add a session',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LongPressDraggable<int>(
                data: row.id,
                onDragStarted: Haptics.medium,
                feedback: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width - 80,
                    child: Opacity(
                      opacity: 0.9,
                      child: SessionTile(row: row, compact: true),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: SessionTile(row: row, compact: true),
                ),
                child: SessionTile(
                  row: row,
                  onTap: () => onOpenSession(date),
                ),
              ),
            ),
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Long-press a session to drag it onto another date.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ),
      ],
    );
  }
}
