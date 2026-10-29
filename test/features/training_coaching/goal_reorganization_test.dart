import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/training_coaching/data/training_coaching_repository.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_database.dart';
import 'coaching_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CoachingFixture f;
  late TrainingCoachingRepository repo;
  late int curl, abs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    f = CoachingFixture(db);
    await f.init();
    repo = TrainingCoachingRepository(db, f.clock);
    Future<int> exercise(String name, String muscle) => db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: muscle,
            equipment: 'Cable',
            mechanics: 'isolation',
            force: 'pull',
            plane: 'sagittal',
            modality: const Value('cable'),
            isCustom: const Value(true),
            recoveryImpact: const Value(1),
          ),
        );
    curl = await exercise('Coaching curl', 'Biceps');
    abs = await exercise('Coaching crunch', 'Abs');
    await db
        .into(db.programDayExercises)
        .insert(
          ProgramDayExercisesCompanion.insert(
            programDayId: f.dayId,
            exerciseId: curl,
            orderIndex: 1,
            targetSets: const Value(3),
            targetRepsMin: const Value(8),
            targetRepsMax: const Value(12),
            trainingMethod: const Value('straight_sets'),
            slotRole: const Value('accessory'),
          ),
        );
  });
  tearDown(() => db.close());

  Future<TrainingCoachingProposalData> prepare({
    bool protectArms = false,
  }) async {
    await db
        .into(db.physiqueProgrammingProfiles)
        .insert(
          PhysiqueProgrammingProfilesCompanion.insert(
            prioritiesJson: jsonEncode({
              'musclePriorities': [
                {'muscleId': 'abs', 'priority': 'high'},
                if (protectArms) {'muscleId': 'biceps', 'priority': 'high'},
              ],
            }),
          ),
        );
    for (var i = 0; i < 4; i++) {
      final at = DateTime(2026, 10, 7 + i * 7, 12);
      f.clock.set(at);
      final resolver = PlannedSessionResolver(db, clock: f.clock);
      final session = await resolver.materialize(
        await resolver.resolveProgramDay(f.dayId),
        startedAt: at,
      );
      await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: CoachingFixture.iso(at),
              programDayId: Value(f.dayId),
              programId: Value(f.programId),
              completedSessionId: Value(session),
              status: const Value('in_progress'),
            ),
          );
      final workouts = WorkoutsRepository(db, f.clock);
      await workouts.addExerciseToSession(
        sessionId: session,
        exerciseId: abs,
        targetSets: 2,
        equipmentVariant: 'cable',
      );
      final entries = await (db.select(
        db.workoutExercises,
      )..where((e) => e.sessionId.equals(session))).get();
      final sets =
          await (db.select(db.setEntries)..where(
                (s) => s.workoutExerciseId.isIn(entries.map((e) => e.id)),
              ))
              .get();
      for (final set in sets) {
        await (db.update(
          db.setEntries,
        )..where((s) => s.id.equals(set.id))).write(
          SetEntriesCompanion(
            isCompleted: const Value(true),
            completedAt: Value(at.add(Duration(minutes: set.setIndex + 1))),
            weightKg: const Value(30),
            reps: const Value(10),
            rpeX10: const Value(80),
          ),
        );
      }
      f.clock.advance(const Duration(minutes: 45));
      await workouts.endSession(session);
    }
    f.clock.set(DateTime(2026, 10, 28, 18));
    await repo.refresh();
    await f.schedule(DateTime(2026, 11, 2, 17));
    await f.schedule(DateTime(2026, 11, 9, 17));
    return (db.select(
      db.trainingCoachingProposals,
    )..where((p) => p.kind.equals('goalGap'))).getSingle();
  }

  test(
    'repeated abs additions reorganize optional work within the growth budget',
    () async {
      final proposal = await prepare();
      final preview = await repo.preview(proposal.id);
      expect(preview.signal.detail, contains('confirmed physique priority'));
      final after = preview.changes.first.after;
      expect(
        after.exercises
            .singleWhere((e) => e.exerciseId == f.exerciseId)
            .sets
            .length,
        4,
      );
      expect(
        after.exercises.singleWhere((e) => e.exerciseId == curl).sets.length,
        2,
      );
      expect(
        after.exercises.singleWhere((e) => e.exerciseId == abs).sets.length,
        2,
      );
      expect(preview.changes.first.afterVolume['Abs'], 2);
      expect(preview.changes.first.beforeMinutes, isNonNegative);
      expect((await db.select(db.programDayExercises).get()).length, 2);
    },
  );
  test(
    'another confirmed priority is protected during reorganization',
    () async {
      final proposal = await prepare(protectArms: true);
      final preview = await repo.preview(proposal.id);
      final after = preview.changes.first.after;
      expect(
        after.exercises.singleWhere((e) => e.exerciseId == curl).sets.length,
        3,
      );
      expect(
        after.exercises.singleWhere((e) => e.exerciseId == abs).sets.length,
        1,
      );
    },
  );
}
