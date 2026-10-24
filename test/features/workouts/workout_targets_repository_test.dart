import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workout_targets_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_database.dart';

class _Clock implements Clock {
  @override
  DateTime now() => DateTime(2026, 10, 15, 12);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SharedPreferences prefs;
  late WorkoutTargetsRepository targets;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openTestDatabase();
    targets = WorkoutTargetsRepository(db, _Clock(), prefs);
  });
  tearDown(() => db.close());
  Future<ExerciseCatalogData> exercise(
    String slug, {
    String modality = 'barbell',
    String metric = 'weight_reps',
  }) async {
    final existing =
        await (db.select(db.exerciseCatalog)
              ..where((t) => t.slug.equals(slug))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      await (db.update(
        db.exerciseCatalog,
      )..where((t) => t.id.equals(existing.id))).write(
        ExerciseCatalogCompanion(
          modality: Value(modality),
          loggingMetric: Value(metric),
        ),
      );
      return (db.select(
        db.exerciseCatalog,
      )..where((t) => t.id.equals(existing.id))).getSingle();
    }
    final id = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: slug,
            slug: Value(slug),
            primaryMuscle: 'Back',
            equipment: 'Test',
            mechanics: 'compound',
            force: 'pull',
            plane: 'vertical',
            modality: Value(modality),
            loggingMetric: Value(metric),
          ),
        );
    return (db.select(
      db.exerciseCatalog,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<WorkoutExerciseData> session(
    ExerciseCatalogData exercise, {
    required int daysAgo,
    String? variant,
    double weight = 100,
    int reps = 5,
    int? rpe,
    int count = 3,
    bool finished = true,
  }) async {
    final at = _Clock().now().subtract(Duration(days: daysAgo));
    final id = await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            startedAt: at,
            endedAt: Value(finished ? at.add(const Duration(hours: 1)) : null),
          ),
        );
    final we = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: id,
            exerciseId: exercise.id,
            orderIndex: 0,
            equipmentVariant: Value(variant),
          ),
        );
    for (var i = 0; i < count; i++) {
      await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: we,
              setIndex: i + 1,
              weightKg: weight,
              reps: reps,
              rpeX10: Value(rpe),
              isCompleted: Value(finished),
              plannedRepsMin: const Value(5),
              plannedRepsMax: const Value(5),
              plannedRpeX10: const Value(80),
            ),
          );
    }
    return (db.select(
      db.workoutExercises,
    )..where((t) => t.id.equals(we))).getSingle();
  }

  PlannedSessionSnapshot plan(
    ExerciseCatalogData ex, {
    String? variant,
    double? weight = 100,
    int reps = 5,
    List<PlannedSetSnapshot>? sets,
    int? programExerciseSlotId,
  }) => PlannedSessionSnapshot(
    name: 'Test',
    exercises: [
      PlannedExerciseSnapshot(
        exerciseId: ex.id,
        orderIndex: 0,
        restSeconds: 90,
        slotRole: 'main',
        trainingMethod: 'straight_sets',
        why: 'Original program',
        equipmentVariant: variant,
        programExerciseSlotId: programExerciseSlotId,
        allowsAdvancedTechniques: false,
        sets:
            sets ??
            [
              for (var i = 1; i <= 3; i++)
                PlannedSetSnapshot(
                  index: i,
                  repsMin: reps,
                  repsMax: reps,
                  weightKg: weight,
                  isWarmup: false,
                  setType: 'standard',
                  intent: 'rir2',
                  rpeX10: 80,
                ),
            ],
      ),
    ],
  );
  test('newer history on different equipment cannot seed a target', () async {
    final ex = await exercise('test-press');
    await session(ex, daysAgo: 3, variant: 'barbell', weight: 80, reps: 4);
    await session(ex, daysAgo: 1, variant: 'dumbbell', weight: 30);
    final snapshot = await WorkoutsRepository(
      db,
      _Clock(),
    ).lastPerformanceSnapshotFor(ex.id, equipmentVariant: 'barbell');
    expect(snapshot!.sets.first.weightKg, 80);
    expect(
      await WorkoutsRepository(
        db,
        _Clock(),
      ).lastPerformanceSnapshotFor(ex.id, equipmentVariant: 'cable'),
      isNull,
    );
  });
  test(
    'live stream recomputes on late RPE, undo and a fresh repository',
    () async {
      final ex = await exercise('test-press');
      final id = await PlannedSessionResolver(
        db,
      ).materialize(plan(ex), startedAt: _Clock().now());
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(id))).getSingle();
      final rows = await WorkoutsRepository(
        db,
        _Clock(),
      ).watchSetsForWorkoutExercise(we.id).first;
      final repository = WorkoutsRepository(db, _Clock());
      await repository.updateSet(
        setId: rows.first.id,
        weightKg: 100,
        reps: 4,
        isCompleted: true,
      );
      expect(
        (await targets
                .watch(we.id, ProgressionGoal.muscleGain)
                .first)[rows[1].id]!
            .weightKg,
        95,
      );
      await repository.updateSet(setId: rows.first.id, rpeX10: 95);
      expect(
        (await targets
                .watch(we.id, ProgressionGoal.muscleGain)
                .first)[rows[1].id]!
            .weightKg,
        92.5,
      );
      final restarted = WorkoutTargetsRepository(db, _Clock(), prefs);
      expect(
        (await restarted
                .watch(we.id, ProgressionGoal.muscleGain)
                .first)[rows[1].id]!
            .weightKg,
        92.5,
      );
      await repository.updateSet(setId: rows.first.id, isCompleted: false);
      expect(
        (await targets
                .watch(we.id, ProgressionGoal.muscleGain)
                .first)[rows[1].id]!
            .weightKg,
        100,
      );
      final unchanged = await repository
          .watchSetsForWorkoutExercise(we.id)
          .first;
      expect(unchanged[1].plannedWeightKg, 100);
      expect(unchanged[1].rpeX10, isNull);
    },
  );
  test(
    'legacy machine catalog exposes assistance input and retains machine history',
    () async {
      final ex = await exercise(
        'assisted-pull-up-machine-wide-grip',
        modality: 'bodyweight',
        metric: 'reps',
      );
      expect(
        effectiveLoggingMetric(exercise: ex, equipmentVariant: 'bodyweight'),
        LoggingMetric.weightReps,
      );
      expect(equipmentVariantsFor(ex), ['machine_selectorized']);
      await session(ex, daysAgo: 2, variant: 'bodyweight', weight: 20);
      final current = await session(
        ex,
        daysAgo: 0,
        variant: 'machine_selectorized',
        weight: 0,
        finished: false,
      );
      final rows = await WorkoutsRepository(
        db,
        _Clock(),
      ).watchSetsForWorkoutExercise(current.id).first;
      final result = await targets.resolve(
        exercise: ex,
        workoutExercise: current,
        sets: rows,
      );
      expect(result.values.first.isAssistance, true);
      expect(result.values.first.weightKg, 17.5);
      await const AssistanceSettings(
        stepKg: 5,
        transitionKg: 4,
      ).save(prefs, ex.id);
      final configured = await targets.resolve(
        exercise: ex,
        workoutExercise: current,
        sets: rows,
      );
      expect(configured.values.first.weightKg, 15);
      expect(AssistanceSettings.read(prefs, ex.id).transitionKg, 4);
    },
  );
  test(
    'machine readiness overrides program next session, and can be undone',
    () async {
      final assisted = await exercise(
        'assisted-pull-up-machine-wide-grip',
        modality: 'machine_selectorized',
      );
      final strict = await exercise(
        'pull-up-wide-grip',
        modality: 'bodyweight',
        metric: 'reps',
      );
      await session(assisted, daysAgo: 4, weight: 5, reps: 8, rpe: 80);
      await session(assisted, daysAgo: 2, weight: 5, reps: 8, rpe: 80);
      final original = plan(assisted, reps: 8, weight: 5);
      final id = await PlannedSessionResolver(
        db,
      ).materialize(original, startedAt: _Clock().now());
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(id))).getSingle();
      expect(we.exerciseId, strict.id);
      expect(we.equipmentVariant, 'bodyweight');
      final rows = await WorkoutsRepository(
        db,
        _Clock(),
      ).watchSetsForWorkoutExercise(we.id).first;
      expect(rows, hasLength(3));
      expect(rows.first.plannedRepsMin, 5);
      expect(rows.first.plannedWeightKg, isNull);
      expect(rows.first.plannedRpeX10, 80);
      expect(original.exercises.single.exerciseId, assisted.id);
      expect(
        await WorkoutsRepository(db, _Clock()).undoAutomaticProgression(we.id),
        true,
      );
      final restored = await (db.select(
        db.workoutExercises,
      )..where((t) => t.id.equals(we.id))).getSingle();
      expect(restored.exerciseId, assisted.id);
      final restoredSets = await WorkoutsRepository(
        db,
        _Clock(),
      ).watchSetsForWorkoutExercise(we.id).first;
      expect(restoredSets.first.plannedRepsMin, 8);
      expect(restoredSets.first.plannedWeightKg, 5);
      expect(
        jsonDecode(restoredSets.first.setTypeMetaJson ?? '{}'),
        isNot(contains('promotionOriginal')),
      );
    },
  );
  test('configured threshold prevents an early machine transition', () async {
    final assisted = await exercise(
      'assisted-pull-up-machine-wide-grip',
      modality: 'machine_selectorized',
    );
    await exercise('pull-up-wide-grip', modality: 'bodyweight', metric: 'reps');
    await session(assisted, daysAgo: 4, weight: 5, reps: 8, rpe: 80);
    await session(assisted, daysAgo: 2, weight: 5, reps: 8, rpe: 80);
    await const AssistanceSettings(transitionKg: 4).save(prefs, assisted.id);
    final id = await PlannedSessionResolver(
      db,
    ).materialize(plan(assisted), startedAt: _Clock().now());
    final we = await (db.select(
      db.workoutExercises,
    )..where((t) => t.sessionId.equals(id))).getSingle();
    expect(we.exerciseId, assisted.id);
  });

  test(
    'materialization removes rounded duplicates and excessive automatic warmups',
    () async {
      final ex = await exercise('test-press');
      final input = plan(
        ex,
        sets: [
          for (final (i, p) in [.4, .55, .7, .8].indexed)
            PlannedSetSnapshot(
              index: i + 1,
              repsMin: 5,
              repsMax: 5,
              isWarmup: true,
              setType: 'standard',
              intent: 'technical',
              percentOf1Rm: p,
              setTypeMetaJson: '{"automaticWarmup":true}',
            ),
          const PlannedSetSnapshot(
            index: 5,
            repsMin: 5,
            repsMax: 5,
            weightKg: 10,
            percentOf1Rm: .7,
            isWarmup: false,
            setType: 'standard',
            intent: 'rir2',
          ),
        ],
      );
      final id = await PlannedSessionResolver(
        db,
      ).materialize(input, startedAt: _Clock().now());
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(id))).getSingle();
      final sets = await WorkoutsRepository(
        db,
        _Clock(),
      ).watchSetsForWorkoutExercise(we.id).first;
      expect(sets.where((s) => s.isWarmup), hasLength(2));
      final resolved = await targets.resolve(
        exercise: ex,
        workoutExercise: we,
        sets: sets,
      );
      expect(
        resolved.values.where((s) => s.weightKg != null).map((s) => s.weightKg),
        [5, 7.5, 10],
      );
      expect(
        sets.where((s) => s.isWarmup).every((s) => s.plannedRpeX10 == null),
        true,
      );
    },
  );
  test('zero assistance stays an explicit value after reload', () async {
    final ex = await exercise(
      'assisted-pull-up-machine-wide-grip',
      modality: 'machine_selectorized',
    );
    final current = await session(ex, daysAgo: 0, weight: 0, finished: false);
    final repo = WorkoutsRepository(db, _Clock());
    final rows = await repo.watchSetsForWorkoutExercise(current.id).first;
    expect(rows.first.hasEnteredWeight, false);
    await repo.updateSet(setId: rows.first.id, weightKg: 0);
    expect(
      (await repo.watchSetsForWorkoutExercise(current.id).first)
          .first
          .hasEnteredWeight,
      true,
    );
  });

  test(
    'editing a program as a template preserves percentages and target RPE',
    () async {
      final ex = await exercise('test-template-press');
      final original = plan(
        ex,
        variant: 'barbell',
        sets: [
          const PlannedSetSnapshot(
            index: 1,
            repsMin: 5,
            repsMax: 5,
            isWarmup: true,
            setType: 'standard',
            intent: 'technical',
            rpeX10: 60,
            percentOf1Rm: .4,
          ),
          const PlannedSetSnapshot(
            index: 2,
            repsMin: 5,
            repsMax: 5,
            isWarmup: false,
            setType: 'standard',
            intent: 'rir3',
            rpeX10: 70,
            percentOf1Rm: .75,
          ),
        ],
      );
      final template = await TemplatesRepository(
        db,
      ).createFromPlannedSession(original);
      final restored = await PlannedSessionResolver(
        db,
      ).resolveTemplate(template.id);
      expect(restored.exercises.single.equipmentVariant, 'barbell');
      expect(restored.exercises.single.sets.first.rpeX10, 60);
      expect(restored.exercises.single.sets.last.rpeX10, 70);
      expect(restored.exercises.single.sets.last.percentOf1Rm, .75);
    },
  );

  test(
    'band readiness promotes only with two recorded matching assistance sessions',
    () async {
      final assisted = await exercise(
        'band-assisted-pull-up-wide-grip',
        modality: 'bodyweight',
        metric: 'reps',
      );
      final strict = await exercise(
        'pull-up-wide-grip',
        modality: 'bodyweight',
        metric: 'reps',
      );
      final band = await db
          .into(db.bands)
          .insert(
            BandsCompanion.insert(
              name: 'Test assistance',
              color: 'blue',
              tensionKg: 10,
            ),
          );
      for (final days in [4, 2]) {
        final we = await session(
          assisted,
          daysAgo: days,
          variant: 'band',
          weight: 0,
          reps: 8,
          rpe: 80,
        );
        for (final row in await WorkoutsRepository(
          db,
          _Clock(),
        ).watchSetsForWorkoutExercise(we.id).first) {
          await db
              .into(db.setBands)
              .insert(
                SetBandsCompanion.insert(
                  setEntryId: row.id,
                  bandId: band,
                  mode: const Value('assistance'),
                ),
              );
        }
      }
      final id = await PlannedSessionResolver(db).materialize(
        plan(assisted, variant: 'band', weight: null),
        startedAt: _Clock().now(),
      );
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(id))).getSingle();
      expect(we.exerciseId, strict.id);
      expect(we.equipmentVariant, 'bodyweight');
    },
  );

  test(
    'an explicit RPE6 program target is not silently changed to RPE8',
    () async {
      final ex = await exercise('test-rpe-six');
      final program = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'RPE test'));
      final week = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: program, weekIndex: 0),
          );
      final day = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: week,
              dayOfWeek: 1,
              name: 'Test',
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: day,
              exerciseId: ex.id,
              orderIndex: 0,
              targetSets: const Value(3),
              targetRepsMin: const Value(5),
              targetRpe: const Value(6),
              trainingMethod: const Value('straight_sets'),
            ),
          );
      final resolved = await PlannedSessionResolver(db).resolveProgramDay(day);
      expect(resolved.exercises.single.sets.first.rpeX10, 60);
      expect(resolved.exercises.single.sets.first.rir, 4);
    },
  );
  test(
    'smart-program calisthenics targets use the history-aware three-set dose',
    () async {
      final strict = await exercise(
        'pull-up',
        modality: 'bodyweight',
        metric: 'reps',
      );
      await session(
        strict,
        daysAgo: 2,
        variant: 'bodyweight',
        weight: 0,
        reps: 8,
        rpe: 80,
      );
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'Calisthenics'));
      final slotId = await db
          .into(db.programExerciseSlots)
          .insert(
            ProgramExerciseSlotsCompanion.insert(
              programId: programId,
              slotKey: 'pull-up-main',
              daySlotLabel: 'Upper',
              orderIndex: 0,
            ),
          );
      final id = await PlannedSessionResolver(db).materialize(
        plan(
          strict,
          variant: 'bodyweight',
          weight: 0,
          reps: 8,
          programExerciseSlotId: slotId,
          sets: [
            for (var i = 1; i <= 4; i++)
              PlannedSetSnapshot(
                index: i,
                repsMin: 8,
                repsMax: 8,
                weightKg: 0,
                isWarmup: false,
                setType: 'standard',
                intent: 'rir2',
                rpeX10: 80,
              ),
          ],
        ),
        startedAt: _Clock().now(),
      );
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(id))).getSingle();
      final sets = await (db.select(
        db.setEntries,
      )..where((t) => t.workoutExerciseId.equals(we.id))).get();

      expect(sets, hasLength(3));
      expect(sets.map((set) => set.plannedRepsMin), everyElement(8));
      expect(sets.map((set) => set.plannedRepsMax), everyElement(8));
      expect(sets.map((set) => set.plannedRpeX10), everyElement(80));
    },
  );
  test(
    'an achieved strict pull-up level continues to override the old assisted program',
    () async {
      final assisted = await exercise(
        'assisted-pull-up-machine-wide-grip',
        modality: 'machine_selectorized',
      );
      final strict = await exercise(
        'pull-up-wide-grip',
        modality: 'bodyweight',
        metric: 'reps',
      );
      await session(assisted, daysAgo: 6, weight: 5, reps: 8, rpe: 80);
      await session(assisted, daysAgo: 4, weight: 5, reps: 8, rpe: 80);
      await session(
        strict,
        daysAgo: 2,
        variant: 'bodyweight',
        weight: 0,
        reps: 5,
        rpe: 80,
      );
      final id = await PlannedSessionResolver(db).materialize(
        plan(assisted, reps: 8, weight: 5),
        startedAt: _Clock().now(),
      );
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(id))).getSingle();
      expect(we.exerciseId, strict.id);
      expect(we.equipmentVariant, 'bodyweight');
    },
  );
}
