import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/workout_report/data/workout_report_journal.dart';
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
    if (slot != null && slot.isNotEmpty) {
      return slot;
    }
    return programDay.name;
  }
}

/// Smart workout launcher (§18): reads the day's scheduled workout and starts a
/// real session pre-populated from whatever the program day resolves to — its
/// linked template, or its own inline prescribed exercises.
class ScheduledWorkoutService {
  final AppDatabase _db;
  final Clock _clock;

  ScheduledWorkoutService(
    this._db,
    this._clock,
    ProgramsRepository _,
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
  Future<List<TodaysScheduledWorkout>> todaysWorkouts() =>
      _workoutsForDay(_clock.now());

  /// Every source that can change the resolved plan participates in invalidation.
  Stream<List<TodaysScheduledWorkout>> watchWorkoutsForDay(DateTime day) => _db
      .customSelect(
        'SELECT id FROM scheduled_workouts WHERE date_iso = ?',
        variables: [Variable.withString(_dateIso(day))],
        readsFrom: {
          _db.scheduledWorkouts,
          _db.programDays,
          _db.programs,
          _db.programWeeks,
          _db.programDayExercises,
          _db.workoutTemplates,
          _db.templateExercises,
          _db.templateSets,
          _db.rotationAssignments,
          _db.adaptationOverrides,
          _db.adaptationProposals,
          _db.programExerciseSlots,
          _db.programSlotPoolMembers,
          _db.prescriptionTemplates,
        },
      )
      .watch()
      .asyncMap((_) => _workoutsForDay(day));

  Future<List<TodaysScheduledWorkout>> _workoutsForDay(DateTime day) async {
    final schedules =
        await (_db.select(_db.scheduledWorkouts)
              ..where(
                (t) =>
                    t.dateIso.equals(_dateIso(day)) &
                    t.deletedAt.isNull() &
                    t.status.isIn([
                      ScheduleStatus.planned,
                      ScheduleStatus.moved,
                      ScheduleStatus.inProgress,
                      ScheduleStatus.done,
                    ]),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.orderIndex),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    final workouts = <TodaysScheduledWorkout>[];
    for (final schedule in schedules) {
      final workout = await _resolveSchedule(schedule);
      if (workout != null) {
        workouts.add(workout);
      }
    }
    return workouts;
  }

  static TodaysScheduledWorkout? primaryWorkout(
    List<TodaysScheduledWorkout> workouts,
  ) {
    for (final w in workouts) {
      if (w.isInProgress) {
        return w;
      }
    }
    for (final w in workouts) {
      if (!w.isDone) {
        return w;
      }
    }
    return workouts.isEmpty ? null : workouts.last;
  }

  /// The first workout scheduled for today, for the dashboard's compact smart
  /// launcher. Calendar callers should use [workoutForSchedule] instead.
  Future<TodaysScheduledWorkout?> todaysWorkout() async {
    final workouts = await todaysWorkouts();
    return primaryWorkout(workouts);
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
    if (day == null || day.deletedAt != null) {
      return null;
    }

    final templateId = schedule.templateIdOverride ?? day.templateId;
    final template = templateId == null
        ? null
        : await (_db.select(
            _db.workoutTemplates,
          )..where((t) => t.id.equals(templateId))).getSingleOrNull();

    // Resolved, not read straight from ProgramDayExercises — a template-linked
    // day has no inline rows and would otherwise report "0 exercises".
    final exerciseCount = (await PlannedSessionResolver(
      _db,
    ).resolveScheduledWorkout(schedule)).exercises.length;

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
    if (workout == null) {
      return null;
    }
    final resolver = PlannedSessionResolver(_db);
    return resolver.prepare(
      await resolver.resolveScheduledWorkout(workout.schedule),
      at: _clock.now(),
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
    if (today.schedule.deletedAt != null ||
        !ScheduleStatus.isOpen(today.schedule.status)) {
      throw StateError(
        'This scheduled workout is no longer available to start.',
      );
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
      if (linked != null && linked.endedAt == null) {
        return linked.id;
      }
      throw StateError('This scheduled workout has already been completed.');
    }

    final resolver = PlannedSessionResolver(_db);
    final plan = await resolver.resolveScheduledWorkout(today.schedule);

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

      final accepted =
          await (_db.select(_db.adaptationOverrides)..where(
                (o) =>
                    o.scheduleId.equals(today.schedule.id) &
                    o.deletedAt.isNull(),
              ))
              .get();
      if (accepted.isNotEmpty) {
        final original = await resolver.resolveProgramDay(
          today.schedule.programDayId,
          templateOverride: today.schedule.templateIdOverride,
        );
        final originalCount = original.exercises.fold<int>(
          0,
          (n, e) => n + e.sets.where((s) => !s.isWarmup).length,
        );
        final catalog =
            await (_db.select(_db.exerciseCatalog)..where(
                  (e) => e.id.isIn(original.exercises.map((e) => e.exerciseId)),
                ))
                .get();
        final muscles = {for (final e in catalog) e.id: e.primaryMuscle};
        final counts = <String, int>{};
        for (final e in original.exercises) {
          counts.update(
            muscles[e.exerciseId] ?? 'Unknown',
            (n) => n + e.sets.where((s) => !s.isWarmup).length,
            ifAbsent: () => e.sets.where((s) => !s.isWarmup).length,
          );
        }
        final captured = await (_db.select(
          _db.workoutReportPlans,
        )..where((p) => p.sessionId.equals(sessionId))).getSingle();
        final baseline = jsonDecode(captured.planJson) as Map<String, dynamic>;
        baseline['originalSets'] = originalCount;
        baseline['originalMuscles'] = counts;
        await (_db.update(
          _db.workoutReportPlans,
        )..where((p) => p.sessionId.equals(sessionId))).write(
          WorkoutReportPlansCompanion(planJson: Value(jsonEncode(baseline))),
        );
        await WorkoutReportJournal(
          _db,
          _clock,
        ).record(sessionId, 'adapted_plan', {'originalSets': originalCount});
      }
      return sessionId;
    });
  }
}
