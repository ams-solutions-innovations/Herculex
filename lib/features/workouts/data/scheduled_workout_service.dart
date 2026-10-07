import 'package:drift/drift.dart';

import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';

/// Today's scheduled workout resolved with its program-day name and exercise
/// count, for the dashboard smart launcher (§18).
class TodaysScheduledWorkout {
  final ScheduledWorkoutData schedule;
  final ProgramDayData programDay;
  final int exerciseCount;

  /// The template the session will be built from, if the day links one.
  final WorkoutTemplateData? template;

  const TodaysScheduledWorkout({
    required this.schedule,
    required this.programDay,
    required this.exerciseCount,
    this.template,
  });

  /// Only a finished session counts as done. Starting a workout marks the
  /// schedule [isInProgress]; it becomes done when the session ends.
  bool get isDone => schedule.status == ScheduleStatus.done;

  bool get isInProgress => schedule.status == ScheduleStatus.inProgress;

  /// A session exists for this schedule, whether or not it has ended.
  bool get isStarted => schedule.completedSessionId != null;

  String get title {
    final slot = programDay.slotLabel?.trim();
    if (slot != null && slot.isNotEmpty) return slot;
    return programDay.name;
  }
}

/// Smart workout launcher (§18): reads the day's scheduled workout and starts a
/// real session pre-populated from whatever the program day resolves to — its
/// linked template, or its own inline prescribed exercises.
class ScheduledWorkoutService {
  final AppDatabase _db;
  final Clock _clock;
  final ProgramsRepository _programs;

  ScheduledWorkoutService(
    this._db,
    this._clock,
    this._programs,
    TemplatesRepository _,
  );

  static String _dateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Every workout scheduled for today, in its display order.
  ///
  /// The dashboard still presents the first item as its compact smart
  /// launcher, but calendar actions must resolve their own [scheduleId]. In
  /// particular, querying with `limit(1)` here used to make a tap on a second
  /// same-day workout accidentally operate on the first one.
  Future<List<TodaysScheduledWorkout>> todaysWorkouts() async {
    final iso = _dateIso(_clock.now());
    final schedules =
        await (_db.select(_db.scheduledWorkouts)
              ..where((t) => t.dateIso.equals(iso))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
    final workouts = <TodaysScheduledWorkout>[];
    for (final schedule in schedules) {
      final workout = await _resolveSchedule(schedule);
      if (workout != null) workouts.add(workout);
    }
    return workouts;
  }

  /// The first workout scheduled for today, for the dashboard's compact smart
  /// launcher. Calendar callers should use [workoutForSchedule] instead.
  Future<TodaysScheduledWorkout?> todaysWorkout() async {
    final workouts = await todaysWorkouts();
    return workouts.isEmpty ? null : workouts.first;
  }

  /// Resolves exactly one scheduled occurrence. This is intentionally keyed by
  /// [scheduleId], not date, so two sessions on the same day cannot cross over.
  Future<TodaysScheduledWorkout?> workoutForSchedule(int scheduleId) async {
    final schedule = await (_db.select(
      _db.scheduledWorkouts,
    )..where((t) => t.id.equals(scheduleId))).getSingleOrNull();
    return schedule == null ? null : _resolveSchedule(schedule);
  }

  Future<TodaysScheduledWorkout?> _resolveSchedule(
    ScheduledWorkoutData schedule,
  ) async {
    final day = await (_db.select(
      _db.programDays,
    )..where((t) => t.id.equals(schedule.programDayId))).getSingleOrNull();
    if (day == null) return null;

    final templateId = schedule.templateIdOverride ?? day.templateId;
    final template = templateId == null
        ? null
        : await (_db.select(
            _db.workoutTemplates,
          )..where((t) => t.id.equals(templateId))).getSingleOrNull();

    // Resolved, not read straight from ProgramDayExercises — a template-linked
    // day has no inline rows and would otherwise report "0 exercises".
    final exerciseCount = await _programs.countDayExercises(
      day.id,
      templateOverride: schedule.templateIdOverride,
    );

    return TodaysScheduledWorkout(
      schedule: schedule,
      programDay: day,
      exerciseCount: exerciseCount,
      template: template,
    );
  }

  /// Resolves the current planned content without creating a workout session.
  /// This keeps the calendar's “View workout” action safely read-only.
  Future<PlannedSessionSnapshot?> previewScheduledWorkout(
    int scheduleId,
  ) async {
    final workout = await workoutForSchedule(scheduleId);
    if (workout == null) return null;
    return PlannedSessionResolver(_db).resolveProgramDay(
      workout.programDay.id,
      templateOverride: workout.schedule.templateIdOverride,
    );
  }

  /// Starts a session pre-populated from the scheduled day and links it back to
  /// the schedule. Returns the new session id. [gymId] tags the session like a
  /// normal start.
  Future<int> startScheduledWorkout(
    TodaysScheduledWorkout today, {
    int? gymId,
  }) => startScheduledWorkoutById(today.schedule.id, gymId: gymId);

  /// Starts the exact scheduled occurrence, or returns its existing open
  /// session when the user taps Resume. The existing link is never replaced;
  /// that protects in-progress logging from a duplicate materialization.
  Future<int> startScheduledWorkoutById(int scheduleId, {int? gymId}) async {
    final today = await workoutForSchedule(scheduleId);
    if (today == null) {
      throw StateError('This scheduled workout no longer exists.');
    }
    if (today.schedule.dateIso != _dateIso(_clock.now())) {
      throw StateError(
        'This workout can only be started on its scheduled day.',
      );
    }

    final linkedSessionId = today.schedule.completedSessionId;
    if (linkedSessionId != null) {
      final linked = await (_db.select(
        _db.workoutSessions,
      )..where((t) => t.id.equals(linkedSessionId))).getSingleOrNull();
      if (linked != null && linked.endedAt == null) return linked.id;
      throw StateError('This scheduled workout has already been completed.');
    }

    final resolver = PlannedSessionResolver(_db);
    final plan = await resolver.resolveProgramDay(
      today.programDay.id,
      templateOverride: today.schedule.templateIdOverride,
    );

    return _db.transaction(() async {
      final sessionId = await resolver.materialize(
        plan,
        startedAt: _clock.now(),
        gymId: gymId,
        notes: today.title,
      );

      await (_db.update(
        _db.scheduledWorkouts,
      )..where((t) => t.id.equals(today.schedule.id))).write(
        ScheduledWorkoutsCompanion(
          completedSessionId: Value(sessionId),
          // Starting is not finishing — `markScheduleCompleted` flips this to
          // done when the session actually ends.
          status: const Value(ScheduleStatus.inProgress),
        ),
      );

      return sessionId;
    });
  }
}
