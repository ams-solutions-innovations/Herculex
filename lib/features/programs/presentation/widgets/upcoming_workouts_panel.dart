import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/scheduled_workout_row.dart';
import 'package:herculex/features/programs/presentation/widgets/session_tile.dart';
import 'package:intl/intl.dart';

/// "When is my next workout?" — the sessions still to train over the next few
/// weeks, grouped by day, so a wide window can show the answer beside the
/// calendar instead of making you page to it.
class UpcomingWorkoutsPanel extends ConsumerWidget {
  const UpcomingWorkoutsPanel({
    super.key,
    required this.programId,
    required this.onOpenSession,
    this.horizonDays = 21,
  });

  final int? programId;
  final ValueChanged<ScheduledWorkoutRow> onOpenSession;

  /// How far ahead to look, counting today.
  final int horizonDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider).now();
    final today = DateTime(now.year, now.month, now.day);
    final range = ScheduleRange(
      fromIso: _iso(today),
      toIso: _iso(DateTime(today.year, today.month, today.day + horizonDays)),
      programId: programId,
    );
    final byDate = ref.watch(scheduleByDateProvider(range));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                'Coming up',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'Next ${horizonDays ~/ 7} weeks',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          byDate.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Could not load your schedule.',
                style: TextStyle(color: AppColors.secondary),
              ),
            ),
            data: (map) {
              final days = upcomingDays(map, today: today);
              if (days.isEmpty) return const _NothingPlanned();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final day in days) ...[
                    _DayLabel(date: day.date, today: today),
                    const SizedBox(height: 6),
                    for (final row in day.rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SessionTile(
                          row: row,
                          compact: true,
                          onTap: () => onOpenSession(row),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// The days from [today] that still have a session to train — open sessions,
  /// plus anything already done today — in date order, each day's sessions
  /// by start time. Rest days and skipped sessions are left out.
  static List<({DateTime date, List<ScheduledWorkoutRow> rows})> upcomingDays(
    Map<String, List<ScheduledWorkoutRow>> byDate, {
    required DateTime today,
  }) {
    final isoToday = _iso(today);
    final result = <({DateTime date, List<ScheduledWorkoutRow> rows})>[];
    final keys = byDate.keys.where((k) => k.compareTo(isoToday) >= 0).toList()
      ..sort();
    for (final key in keys) {
      final rows = sortedByStartTime(
        byDate[key]!
            .where(
              (r) =>
                  !r.isRestDay &&
                  (ScheduleStatus.isOpen(r.status) ||
                      (r.isDone && key == isoToday)),
            )
            .toList(),
      );
      if (rows.isNotEmpty) result.add((date: DateTime.parse(key), rows: rows));
    }
    return result;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = date.difference(today).inDays;
    final title = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => DateFormat('EEEE').format(date),
    };
    final detail = days <= 1
        ? DateFormat('EEE, MMM d').format(date)
        : '${DateFormat('MMM d').format(date)} · in $days days';
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: days == 0 ? AppColors.primary : AppColors.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingPlanned extends StatelessWidget {
  const _NothingPlanned();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_rounded,
            size: 36,
            color: AppColors.secondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Nothing planned in the next few weeks',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
