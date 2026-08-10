import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/local/database.dart';
import '../../../../theme/colors.dart';
import '../../domain/scheduled_workout_row.dart';
import '../programs_providers.dart';
import 'day_column_card.dart';

/// Monday–Sunday board for one week, with drag-to-reorder inside a day and
/// drag-between-days across the board.
class WeekBoard extends ConsumerWidget {
  const WeekBoard({
    super.key,
    required this.anchor,
    required this.programId,
    required this.onOpenDay,
    required this.onOpenSession,
  });

  /// Any date inside the week to show.
  final DateTime anchor;
  final int? programId;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<ScheduledWorkoutRow> onOpenSession;

  static DateTime mondayOf(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
  ).subtract(Duration(days: day.weekday - DateTime.monday));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ScheduleRange.week(anchor, programId: programId);
    final byDate = ref.watch(scheduleByDateProvider(range));
    final events = ref.watch(externalEventsProvider).value ?? const [];
    final monday = mondayOf(anchor);

    return byDate.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(
          child: Text(
            'Could not load this week.\n$e',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondary),
          ),
        ),
      ),
      data: (map) => Column(
        children: [
          for (var i = 0; i < 7; i++)
            () {
              final date = monday.add(Duration(days: i));
              final iso = _iso(date);
              return DayColumnCard(
                key: ValueKey('day_$iso'),
                date: date,
                rows: map[iso] ?? const [],
                event: _eventFor(events, iso),
                onOpenDay: onOpenDay,
                onOpenSession: onOpenSession,
              );
            }(),
        ],
      ),
    );
  }

  static ExternalEventData? _eventFor(
    List<ExternalEventData> events,
    String iso,
  ) {
    for (final e in events) {
      if (iso.compareTo(e.dateFromIso) >= 0 && iso.compareTo(e.dateToIso) <= 0) {
        return e;
      }
    }
    return null;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
