import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_merge.dart';

import 'support/test_database.dart';

/// Proves the merge engine before any real merge ships.
///
/// The risk being guarded against is silent: repointing a logged set at
/// another catalog row loses which equipment it was actually performed with,
/// because a null `equipmentVariant` resolves through the catalog row's
/// current modality. That only becomes visible when the user opens their PR
/// history, long after the migration ran.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ExerciseMergeEngine engine;

  setUp(() async {
    db = await openTestDatabase();
    engine = ExerciseMergeEngine(db);
  });
  tearDown(() async => db.close());

  Future<int> insertExercise({
    required String slug,
    required String name,
    String modality = 'barbell',
    String equipment = 'Barbell',
    String? aka,
  }) {
    return db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            slug: Value(slug),
            name: name,
            primaryMuscle: 'Back',
            equipment: equipment,
            mechanics: 'compound',
            force: 'pull',
            plane: 'horizontal',
            modality: Value(modality),
            aka: Value(aka),
          ),
        );
  }

  /// Logs one set against [exerciseId] and returns the workout-exercise id.
  Future<int> logSet(int exerciseId, {String? equipmentVariant}) async {
    final sessionId = await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 6, 1)),
        );
    final workoutExerciseId = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: 0,
            equipmentVariant: Value(equipmentVariant),
          ),
        );
    await db
        .into(db.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: workoutExerciseId,
            setIndex: 0,
            weightKg: 100,
            reps: 5,
          ),
        );
    return workoutExerciseId;
  }

  Future<WorkoutExerciseData> readWorkoutExercise(int id) {
    return (db.select(db.workoutExercises)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// The in-memory DB runs the real onCreate path, so the 398-row catalog is
  /// already present. Assertions look only at the `fx-` fixtures.
  Future<List<String?>> fixtureSlugs() async {
    final catalog = await db.select(db.exerciseCatalog).get();
    return [
      for (final e in catalog)
        if (e.slug?.startsWith('fx-') ?? false) e.slug,
    ];
  }

  test('history survives the merge and keeps its equipment', () async {
    final winner = await insertExercise(slug: 'fx-row-bb', name: 'Fixture Row BB');
    final loser = await insertExercise(
      slug: 'fx-row-db',
      name: 'Fixture Row DB',
      modality: 'dumbbell',
      equipment: 'Dumbbell',
    );

    // A log with no explicit variant — the dangerous case, because its
    // equipment is implied by the catalog row it points at.
    final implicit = await logSet(loser);
    // A log that already recorded its variant explicitly.
    final explicit = await logSet(loser, equipmentVariant: 'smith');

    final outcomes = await engine.apply([
      const ExerciseMerge(loser: 'fx-row-db', winner: 'fx-row-bb'),
    ]);

    expect(outcomes.single.applied, isTrue);
    expect(outcomes.single.repointedWorkoutExercises, 2);

    final implicitRow = await readWorkoutExercise(implicit);
    expect(implicitRow.exerciseId, winner);
    expect(
      implicitRow.equipmentVariant,
      'dumbbell',
      reason: 'the loser modality must be preserved, not inherited from winner',
    );

    final explicitRow = await readWorkoutExercise(explicit);
    expect(explicitRow.exerciseId, winner);
    expect(
      explicitRow.equipmentVariant,
      'smith',
      reason: 'an already-recorded variant must never be overwritten',
    );

    // The sets themselves are untouched.
    final sets = await db.select(db.setEntries).get();
    expect(sets, hasLength(2));

    // Loser row is gone; winner remains.
    expect(await fixtureSlugs(), ['fx-row-bb']);
  });

  test('the merged name stays resolvable as an alias', () async {
    await insertExercise(slug: 'fx-row-bb', name: 'Fixture Row BB');
    await insertExercise(
      slug: 'fx-row-two-arm',
      name: 'Fixture Two-Arm Row',
      aka: 'DB Row, Bent Row',
    );

    await engine.apply([
      const ExerciseMerge(
        loser: 'fx-row-two-arm',
        winner: 'fx-row-bb',
      ),
    ]);

    final aliases = await db.select(db.exerciseAliases).get();
    // Program CSV import and watch sync both resolve by name, so the old name
    // and its aliases must keep pointing somewhere.
    expect(
      aliases.map((a) => a.alias),
      containsAll(['Fixture Two-Arm Row', 'DB Row', 'Bent Row']),
    );
  });

  test('a unique-per-exercise override does not collide', () async {
    final winner = await insertExercise(slug: 'fx-row-bb', name: 'Fixture Row BB');
    final loser = await insertExercise(slug: 'fx-row-db', name: 'Fixture Row DB');

    for (final id in [winner, loser]) {
      await db
          .into(db.exerciseProgressions)
          .insert(ExerciseProgressionsCompanion.insert(exerciseId: id));
    }

    await engine.apply([
      const ExerciseMerge(loser: 'fx-row-db', winner: 'fx-row-bb'),
    ]);

    final progressions = await db.select(db.exerciseProgressions).get();
    expect(progressions, hasLength(1));
    expect(progressions.single.exerciseId, winner);
  });

  test('per-gym machine settings are carried over, not dropped', () async {
    final winner = await insertExercise(slug: 'fx-row-bb', name: 'Fixture Row BB');
    final loser = await insertExercise(slug: 'fx-row-db', name: 'Fixture Row DB');

    for (final id in [winner, loser]) {
      await db
          .into(db.machineSettings)
          .insert(
            MachineSettingsCompanion.insert(
              exerciseId: id,
              settingsJson: '{"seat":"6"}',
            ),
          );
    }

    await engine.apply([
      const ExerciseMerge(loser: 'fx-row-db', winner: 'fx-row-bb'),
    ]);

    // Settings are keyed per gym, not per exercise, so both rows are real
    // user data and both must survive.
    final settings = await db.select(db.machineSettings).get();
    expect(settings, hasLength(2));
    expect(settings.map((s) => s.exerciseId), everyElement(winner));
  });

  test('re-running a merge is a no-op rather than an error', () async {
    await insertExercise(slug: 'fx-row-bb', name: 'Fixture Row BB');
    await insertExercise(slug: 'fx-row-db', name: 'Fixture Row DB');
    const merge = ExerciseMerge(loser: 'fx-row-db', winner: 'fx-row-bb');

    expect((await engine.apply([merge])).single.applied, isTrue);

    final second = await engine.apply([merge]);
    expect(second.single.applied, isFalse);
    expect(second.single.skippedReason, contains('not found'));
    expect(await fixtureSlugs(), ['fx-row-bb']);
  });

  test('an unresolvable winner leaves the catalog untouched', () async {
    final loser = await insertExercise(
      slug: 'fx-row-db',
      name: 'Fixture Row DB',
    );
    await logSet(loser);

    final outcomes = await engine.apply([
      const ExerciseMerge(loser: 'fx-row-db', winner: 'does-not-exist'),
    ]);

    expect(outcomes.single.applied, isFalse);
    expect(await fixtureSlugs(), ['fx-row-db']);
    expect(await db.select(db.setEntries).get(), hasLength(1));
  });

  test('a loser can be addressed by name when it has no slug', () async {
    await insertExercise(slug: 'fx-row-bb', name: 'Fixture Row BB');
    // Rows auto-created by watch sync have no slug.
    await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Fixture Row (Watch Created)',
            primaryMuscle: 'Back',
            equipment: 'Other',
            mechanics: 'compound',
            force: 'pull',
            plane: 'horizontal',
            isCustom: const Value(true),
          ),
        );

    final outcomes = await engine.apply([
      const ExerciseMerge(loser: 'Fixture Row (Watch Created)', winner: 'fx-row-bb'),
    ]);

    expect(outcomes.single.applied, isTrue);
    expect(await fixtureSlugs(), ['fx-row-bb']);
  });
}
