import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import '../../support/fake_clock.dart';

class CoachingFixture {
  CoachingFixture(this.db);
  final AppDatabase db;
  final clock = FakeClock(DateTime(2026, 10, 28, 12));
  late int programId, dayId, exerciseId;
  Future<void> init() async {
    exerciseId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Coaching RDL',
            primaryMuscle: 'Hamstrings',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'pull',
            plane: 'sagittal',
            modality: const Value('barbell'),
            isCustom: const Value(true),
          ),
        );
    programId = await db
        .into(db.programs)
        .insert(
          ProgramsCompanion.insert(
            name: 'Coaching program',
            weeks: const Value(8),
            isActive: const Value(true),
          ),
        );
    final weekId = await db
        .into(db.programWeeks)
        .insert(
          ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
        );
    dayId = await db
        .into(db.programDays)
        .insert(
          ProgramDaysCompanion.insert(
            programWeekId: weekId,
            dayOfWeek: 1,
            name: 'Lower',
          ),
        );
    await db
        .into(db.programDayExercises)
        .insert(
          ProgramDayExercisesCompanion.insert(
            programDayId: dayId,
            exerciseId: exerciseId,
            orderIndex: 0,
            targetSets: const Value(4),
            targetRepsMin: const Value(8),
            targetRepsMax: const Value(12),
            targetRir: const Value(2),
            slotRole: const Value('main'),
            trainingMethod: const Value('straight_sets'),
            equipmentVariant: const Value('barbell'),
          ),
        );
  }

  Future<int> train(DateTime at, {int completed = 2}) async {
    clock.set(at);
    final resolver = PlannedSessionResolver(db, clock: clock);
    final plan = await resolver.resolveProgramDay(dayId);
    final sessionId = await resolver.materialize(plan, startedAt: at);
    await db
        .into(db.scheduledWorkouts)
        .insert(
          ScheduledWorkoutsCompanion.insert(
            dateIso: iso(at),
            programDayId: Value(dayId),
            programId: Value(programId),
            completedSessionId: Value(sessionId),
            status: const Value('in_progress'),
          ),
        );
    final exercise = await (db.select(
      db.workoutExercises,
    )..where((e) => e.sessionId.equals(sessionId))).getSingle();
    final sets =
        await (db.select(db.setEntries)
              ..where((s) => s.workoutExerciseId.equals(exercise.id))
              ..orderBy([(s) => OrderingTerm.asc(s.setIndex)]))
            .get();
    for (final s in sets.take(completed)) {
      await (db.update(db.setEntries)..where((e) => e.id.equals(s.id))).write(
        SetEntriesCompanion(
          isCompleted: const Value(true),
          completedAt: Value(at.add(Duration(minutes: s.setIndex + 1))),
          weightKg: const Value(80),
          reps: const Value(10),
          rpeX10: const Value(80),
        ),
      );
    }
    clock.set(at.add(const Duration(minutes: 40)));
    await WorkoutsRepository(db, clock).endSession(sessionId);
    return sessionId;
  }

  Future<int> schedule(DateTime at) => db
      .into(db.scheduledWorkouts)
      .insert(
        ScheduledWorkoutsCompanion.insert(
          dateIso: iso(at),
          programDayId: Value(dayId),
          programId: Value(programId),
          startTimeMinutes: Value(at.hour * 60 + at.minute),
        ),
      );
  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
