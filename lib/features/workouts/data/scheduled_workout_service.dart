import 'package:drift/drift.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';
import '../../programs/data/programs_repository.dart';
import '../../programs/domain/schedule_status.dart';
import 'templates_repository.dart';

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
  final TemplatesRepository _templates;

  ScheduledWorkoutService(this._db, this._clock, this._programs, this._templates);

  static String _dateIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The (first) workout scheduled for today, or null when nothing is planned.
  Future<TodaysScheduledWorkout?> todaysWorkout() async {
    final iso = _dateIso(_clock.now());
    final schedule =
        await (_db.select(_db.scheduledWorkouts)
              ..where((t) => t.dateIso.equals(iso))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])
              ..limit(1))
            .getSingleOrNull();
    if (schedule == null) return null;

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

  /// Starts a session pre-populated from the scheduled day and links it back to
  /// the schedule. Returns the new session id. [gymId] tags the session like a
  /// normal start.
  Future<int> startScheduledWorkout(
    TodaysScheduledWorkout today, {
    int? gymId,
  }) async {
    final templateId =
        today.schedule.templateIdOverride ?? today.programDay.templateId;

    final sessionId = templateId != null
        // Reuse the template start path so scheduled sessions inherit template
        // sets, set types and warmups rather than a thinner copy of them.
        ? await _templates.startSessionFromTemplate(
            templateId,
            startedAt: _clock.now(),
            gymId: gymId,
            notes: today.title,
          )
        : await _startFromInlineExercises(today, gymId: gymId);

    await (_db.update(_db.scheduledWorkouts)
          ..where((t) => t.id.equals(today.schedule.id)))
        .write(
          ScheduledWorkoutsCompanion(
            completedSessionId: Value(sessionId),
            // Starting is not finishing — `markScheduleCompleted` flips this to
            // done when the session actually ends.
            status: const Value(ScheduleStatus.inProgress),
          ),
        );

    return sessionId;
  }

  Future<int> _startFromInlineExercises(
    TodaysScheduledWorkout today, {
    int? gymId,
  }) {
    return _db.transaction(() async {
      final sessionId = await _db
          .into(_db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: _clock.now(),
              notes: Value(today.programDay.name),
              gymId: Value(gymId),
            ),
          );

      final exercises =
          await (_db.select(_db.programDayExercises)
                ..where((t) => t.programDayId.equals(today.programDay.id))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();

      for (final (i, pde) in exercises.indexed) {
        final catalogRow = await (_db.select(
          _db.exerciseCatalog,
        )..where((t) => t.id.equals(pde.exerciseId))).getSingleOrNull();
        await _db
            .into(_db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                sessionId: sessionId,
                exerciseId: pde.exerciseId,
                orderIndex: i,
                targetRestSeconds: Value(catalogRow?.defaultRestSeconds),
                equipmentVariant: Value(pde.equipmentVariant),
              ),
            );
      }

      return sessionId;
    });
  }
}
