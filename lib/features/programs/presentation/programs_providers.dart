import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../data/programs_repository.dart';
import '../data/rotations_repository.dart';
import '../domain/scheduled_workout_row.dart';

final programsRepositoryProvider = Provider<ProgramsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ProgramsRepository(db);
});

/// Every non-archived block, active one first.
final programsListProvider = StreamProvider<List<ProgramData>>((ref) {
  return ref.watch(programsRepositoryProvider).watchPrograms();
});

/// The block the Blocks tab is showing, or null when none is active.
final activeProgramProvider = StreamProvider<ProgramData?>((ref) {
  return ref.watch(programsRepositoryProvider).watchActiveProgram();
});

final activeProgramsProvider = FutureProvider<List<ProgramData>>((ref) {
  return ref.watch(programsRepositoryProvider).getActivePrograms();
});

final programWeeksProvider =
    StreamProvider.family<List<ProgramWeekData>, int>((ref, programId) {
  return ref.watch(programsRepositoryProvider).watchProgramWeeks(programId);
});

final programDaysProvider =
    StreamProvider.family<List<ProgramDayData>, int>((ref, weekId) {
  return ref.watch(programsRepositoryProvider).watchProgramDaysForWeek(weekId);
});

/// A date window to load the schedule for. A value type, so the family does not
/// mint (and leak) a fresh provider on every rebuild the way a raw `DateTime`
/// key would.
class ScheduleRange {
  const ScheduleRange({
    required this.fromIso,
    required this.toIso,
    this.programId,
  });

  /// The Monday-anchored week containing [day].
  factory ScheduleRange.week(DateTime day, {int? programId}) {
    final monday = DateTime(
      day.year,
      day.month,
      day.day,
    ).subtract(Duration(days: day.weekday - DateTime.monday));
    return ScheduleRange(
      fromIso: _iso(monday),
      toIso: _iso(monday.add(const Duration(days: 6))),
      programId: programId,
    );
  }

  /// The whole month containing [day], padded to full weeks so the calendar
  /// grid's leading and trailing days are populated too.
  factory ScheduleRange.monthGrid(DateTime day, {int? programId}) {
    final first = DateTime(day.year, day.month, 1);
    final last = DateTime(day.year, day.month + 1, 0);
    final gridStart = first.subtract(
      Duration(days: first.weekday - DateTime.monday),
    );
    final gridEnd = last.add(Duration(days: DateTime.sunday - last.weekday));
    return ScheduleRange(
      fromIso: _iso(gridStart),
      toIso: _iso(gridEnd),
      programId: programId,
    );
  }

  final String fromIso;
  final String toIso;
  final int? programId;

  DateTime get from => DateTime.parse(fromIso);
  DateTime get to => DateTime.parse(toIso);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ScheduleRange &&
      other.fromIso == fromIso &&
      other.toIso == toIso &&
      other.programId == programId;

  @override
  int get hashCode => Object.hash(fromIso, toIso, programId);
}

/// The sessions in a date window, joined to day, week, program and template.
final scheduleRangeProvider =
    StreamProvider.family<List<ScheduledWorkoutRow>, ScheduleRange>((
      ref,
      range,
    ) {
      return ref
          .watch(programsRepositoryProvider)
          .watchScheduleRange(
            fromIso: range.fromIso,
            toIso: range.toIso,
            programId: range.programId,
          );
    });

/// The same rows bucketed by `dateIso`, for the week board and month grid.
final scheduleByDateProvider = StreamProvider.family<
  Map<String, List<ScheduledWorkoutRow>>,
  ScheduleRange
>((ref, range) {
  return ref
      .watch(programsRepositoryProvider)
      .watchScheduleRange(
        fromIso: range.fromIso,
        toIso: range.toIso,
        programId: range.programId,
      )
      .map((rows) {
        final byDate = <String, List<ScheduledWorkoutRow>>{};
        for (final row in rows) {
          (byDate[row.dateIso] ??= []).add(row);
        }
        return byDate;
      });
});

final externalEventsProvider = StreamProvider<List<ExternalEventData>>((ref) {
  return ref.watch(programsRepositoryProvider).watchExternalEvents();
});

/// Fatigue conflicts inside the visible window only — the old provider scanned
/// the entire schedule on every mutation.
final recoveryConflictsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, ScheduleRange>((
      ref,
      range,
    ) {
      // Re-run whenever the window's schedule changes.
      ref.watch(scheduleRangeProvider(range));
      return ref
          .watch(programsRepositoryProvider)
          .detectRecoveryConflicts(
            fromIso: range.fromIso,
            toIso: range.toIso,
            programId: range.programId,
          );
    });

// ── Blocks tab UI state ──────────────────────────────────────────────────────

enum BlocksViewMode { week, month }

/// Week or month, persisted so the tab reopens the way it was left.
class BlocksViewModeNotifier extends Notifier<BlocksViewMode> {
  static const _key = 'blocks_view_mode';

  @override
  BlocksViewMode build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(_key);
    return BlocksViewMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => BlocksViewMode.week,
    );
  }

  void set(BlocksViewMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

final blocksViewModeProvider =
    NotifierProvider<BlocksViewModeNotifier, BlocksViewMode>(
      BlocksViewModeNotifier.new,
    );

/// The day (and therefore week/month) the Blocks tab is focused on.
final selectedBlockDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

// ── Rotations ────────────────────────────────────────────────────────────────

final rotationsRepositoryProvider = Provider<RotationsRepository>((ref) {
  return RotationsRepository(ref.watch(appDatabaseProvider));
});

final rotationPoolsProvider = StreamProvider<List<ExerciseRotationData>>((ref) {
  return ref.watch(rotationsRepositoryProvider).watchRotations();
});

final rotationMembersProvider =
    StreamProvider.family<List<RotationMemberData>, int>((ref, rotationId) {
      return ref.watch(rotationsRepositoryProvider).watchMembers(rotationId);
    });
