import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/scheduled_workout_row.dart';
import 'package:herculex/features/programs/presentation/widgets/day_column_card.dart';

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

  /// Narrowest the board goes to two lanes; each day card needs ~310 px.
  static const _twoLaneMinWidth = 640.0;

  static DateTime mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

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
      data: (map) {
        final cards = [
          for (var i = 0; i < 7; i++)
            () {
              final date = DateTime(monday.year, monday.month, monday.day + i);
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
        ];
        // A wide window reads as a board: Monday to Thursday down the left,
        // Friday to Sunday down the right. A phone keeps one column.
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _twoLaneMinWidth) {
              return Column(children: cards);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: cards.sublist(0, 4))),
                const SizedBox(width: 12),
                Expanded(child: Column(children: cards.sublist(4))),
              ],
            );
          },
        );
      },
    );
  }

  static ExternalEventData? _eventFor(
    List<ExternalEventData> events,
    String iso,
  ) {
    for (final e in events) {
      if (iso.compareTo(e.dateFromIso) >= 0 &&
          iso.compareTo(e.dateToIso) <= 0) {
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
