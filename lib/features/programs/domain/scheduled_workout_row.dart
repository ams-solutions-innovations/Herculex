import '../../../data/local/database.dart';
import 'schedule_status.dart';

/// One scheduled session with everything the UI needs to render it, resolved in
/// a single join rather than a query per row.
class ScheduledWorkoutRow {
  const ScheduledWorkoutRow({
    required this.schedule,
    required this.day,
    required this.week,
    required this.program,
    this.template,
    this.exerciseCount = 0,
  });

  final ScheduledWorkoutData schedule;
  final ProgramDayData day;
  final ProgramWeekData week;
  final ProgramData program;

  /// The template this session will be built from — the schedule's one-off
  /// override if set, otherwise the program day's live link. Null means the
  /// day's inline [ProgramDayExercises] are used instead.
  final WorkoutTemplateData? template;

  /// Number of exercises the session will start with, from whichever source
  /// [template] resolves to.
  final int exerciseCount;

  int get id => schedule.id;
  String get dateIso => schedule.dateIso;
  DateTime get date => DateTime.parse(schedule.dateIso);
  String get status => schedule.status;
  int get orderIndex => schedule.orderIndex;

  /// Minutes since midnight this occurrence is scheduled to start, or null
  /// for "no particular time" (v28).
  int? get startTimeMinutes => schedule.startTimeMinutes;
  bool get hasStartTime => startTimeMinutes != null;

  /// "HH:mm", or null when [hasStartTime] is false.
  String? get startTimeLabel {
    final minutes = startTimeMinutes;
    if (minutes == null) return null;
    final hour = (minutes ~/ 60) % 24;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  bool get isRestDay => day.isRest;
  bool get isDone => schedule.status == ScheduleStatus.done;
  bool get isInProgress => schedule.status == ScheduleStatus.inProgress;
  bool get isSkipped => schedule.status == ScheduleStatus.skipped;
  bool get isMoved => schedule.status == ScheduleStatus.moved;

  /// True when this session was swapped for this occurrence only.
  bool get hasTemplateOverride => schedule.templateIdOverride != null;

  /// Whether the content comes from a template rather than inline exercises.
  bool get isTemplateBacked => template != null;

  bool get isEmpty => exerciseCount == 0;

  String get title {
    final slot = day.slotLabel?.trim();
    if (slot != null && slot.isNotEmpty) return slot;
    final name = day.name.trim();
    return name.isEmpty ? 'Training session' : name;
  }

  String get statusLabel => ScheduleStatus.label(schedule.status);

  /// The periodization phase of the week this session falls in, or a deload
  /// label when the week's volume has been dialled back.
  String get phaseLabel {
    if (week.adjustmentFactor < 0.95) return 'Deload';
    final phase = week.blockPhase;
    return switch (phase) {
      'accumulation' => 'Accumulation',
      'transmutation' => 'Transmutation',
      'realization' => 'Realization',
      _ => 'Week ${week.weekIndex + 1}',
    };
  }
}

/// Chronological-first ordering for read-only session lists: timed sessions
/// by [ScheduledWorkoutRow.startTimeMinutes] ascending, untimed ones after
/// them, [ScheduledWorkoutRow.orderIndex] breaking ties in both groups.
///
/// Deliberately NOT used inside a drag-reorderable list — `orderIndex` is
/// the authoritative order there (dragging writes it via
/// `ProgramsRepository.reorderScheduledOnDate`), and a display-only re-sort
/// would desync a `ReorderableListView`'s `oldIndex`/`newIndex` from what
/// that write path assumes.
List<ScheduledWorkoutRow> sortedByStartTime(List<ScheduledWorkoutRow> rows) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    final at = a.startTimeMinutes;
    final bt = b.startTimeMinutes;
    if (at == null && bt == null) return a.orderIndex.compareTo(b.orderIndex);
    if (at == null) return 1;
    if (bt == null) return -1;
    if (at != bt) return at.compareTo(bt);
    return a.orderIndex.compareTo(b.orderIndex);
  });
  return sorted;
}
