import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/calisthenics_progression_repository.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/calisthenics_set_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_database.dart';

class _Clock implements Clock {
  @override
  DateTime now() => DateTime(2026, 10, 14, 12);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late AppDatabase db;
  late CalisthenicsProgressionRepository progression;
  late WorkoutsRepository workouts;
  late int exerciseId;
  setUp(() async {
    db = await openTestDatabase();
    progression = CalisthenicsProgressionRepository(db, _Clock());
    workouts = WorkoutsRepository(db, _Clock());
    exerciseId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Test Pull-Up',
            slug: const Value('pull-up'),
            primaryMuscle: 'Back',
            equipment: 'Bodyweight',
            mechanics: 'compound',
            force: 'pull',
            plane: 'vertical',
            modality: const Value('bodyweight'),
            loggingMetric: const Value('reps'),
            supportsWeightedBodyweight: const Value(true),
          ),
        );
  });
  tearDown(() async => db.close());

  Future<int> completed(
    int daysAgo, {
    String variant = 'bodyweight',
    bool warmup = false,
    bool ended = true,
  }) async {
    final at = _Clock().now().subtract(Duration(days: daysAgo));
    final id = await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            startedAt: at,
            endedAt: Value(ended ? at.add(const Duration(hours: 1)) : null),
          ),
        );
    final we = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: id,
            exerciseId: exerciseId,
            orderIndex: 0,
            equipmentVariant: Value(variant),
          ),
        );
    for (var i = 0; i < 3; i++) {
      await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: we,
              setIndex: i,
              weightKg: 0,
              reps: 8,
              isCompleted: const Value(true),
              isWarmup: Value(warmup),
            ),
          );
    }
    return id;
  }

  test(
    'completed history produces one crossing and excludes active workouts',
    () async {
      await completed(4);
      final active = await completed(0, ended: false);
      expect((await progression.recommendations())['pull-up']!.ready, false);
      await workouts.endSession(active);
      expect((await progression.newlyReady(active)).map((r) => r.path.id), [
        'pull-up',
      ]);
      final third = await completed(0);
      expect(await progression.newlyReady(third), isEmpty);
    },
  );
  test('warmups and tombstoned sets do not qualify', () async {
    await completed(4, warmup: true);
    final latest = await completed(0);
    expect((await progression.recommendations())['pull-up']!.ready, false);
    await completed(2);
    expect((await progression.recommendations())['pull-up']!.ready, true);
    final wes = await (db.select(
      db.workoutExercises,
    )..where((t) => t.sessionId.equals(latest))).get();
    await (db.update(db.setEntries)
          ..where((t) => t.workoutExerciseId.equals(wes.single.id)))
        .write(SetEntriesCompanion(deletedAt: Value(_Clock().now())));
    expect((await progression.recommendations())['pull-up']!.ready, false);
  });
  test(
    'picker prescription creates three editable sets with frozen rep targets',
    () async {
      final session = await workouts.startSession();
      final we = await workouts.addExerciseToSession(
        sessionId: session,
        exerciseId: exerciseId,
        equipmentVariant: 'weighted',
        targetSets: 3,
        targetReps: 5,
        targetWeightKg: 1.25,
      );
      final sets = await (db.select(
        db.setEntries,
      )..where((t) => t.workoutExerciseId.equals(we))).get();
      expect(sets.length, 3);
      for (final set in sets) {
        expect(set.reps, 0);
        expect(set.weightKg, 0);
        expect(set.plannedRepsMin, 5);
        expect(set.plannedWeightKg, 1.25);
        expect(set.isCompleted, false);
      }
    },
  );
  test('template preserves selected variant, reps and added weight', () async {
    final templates = TemplatesRepository(db);
    final template = await templates.createTemplate(name: 'Calisthenics');
    await templates.addExerciseToTemplate(
      templateId: template.id,
      exerciseId: exerciseId,
      equipmentVariant: 'weighted',
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 5,
      targetWeightKg: 1.25,
    );
    final snapshot = await PlannedSessionResolver(
      db,
    ).resolveTemplate(template.id);
    expect(snapshot.exercises.single.equipmentVariant, 'weighted');
    expect(snapshot.exercises.single.sets.length, 3);
    expect(snapshot.exercises.single.sets.first.weightKg, 1.25);
    expect(snapshot.exercises.single.sets.first.repsMin, 5);
  });
  test(
    'hold plan metadata round trips and rejects malformed or future formats',
    () {
      final source = const CalisthenicsSetPlan('bodyweight', 12).encode();
      expect(CalisthenicsSetPlan.decode(source)!.durationSeconds, 12);
      for (final invalid in [
        '{',
        '[]',
        '{"calisthenicsPlan":{"version":2,"variant":"band"}}',
        '{"calisthenicsPlan":{"version":1,"variant":"machine"}}',
      ]) {
        expect(CalisthenicsSetPlan.decode(invalid), null);
      }
    },
  );
}
