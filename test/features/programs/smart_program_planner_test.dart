import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

import '../../support/test_database.dart';

/// Phase 18 Plan 05: two-pass per-day time-budget trim loop, codec-based
/// stored overrides, and persisted `allowTimeSavingSetTechniques`.
///
/// Every test here uses a synthetic, catalog-independent fixture (its own
/// zero-equipment gym plus hand-inserted `ExerciseCatalog` rows with
/// `requiredEquipmentKeys: '[]'`), matching the convention established by
/// `test/smart_program_planner_test.dart`'s "verifyPrerequisites wiring"
/// groups — this keeps the day's needs, targets, and resulting time
/// estimate fully deterministic and independent of the real seeded catalog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    db = await openTestDatabase();
    await db
        .into(db.gyms)
        .insert(
          GymsCompanion.insert(
            name: 'Isolated fixture gym',
            isDefault: const Value(true),
            allEquipment: const Value(false),
          ),
        );
  });
  tearDown(() => db.close());

  Future<int> insertExercise({
    required String slug,
    required String name,
    required String primaryMuscle,
    String? movementPattern,
    String mechanics = 'compound',
    String modality = 'barbell',
    int cnsScore = 5,
    String? movementPatternRaw,
    String allowedTrainingStylesJson = '["weightlifting"]',
    String loggingMetric = 'weight_reps',
    String category = 'strength',
  }) => db
      .into(db.exerciseCatalog)
      .insert(
        ExerciseCatalogCompanion.insert(
          slug: Value(slug),
          name: name,
          primaryMuscle: primaryMuscle,
          equipment: modality,
          mechanics: mechanics,
          force: 'push',
          plane: 'none',
          movementPattern: Value(movementPattern),
          movementPatternRaw: Value(movementPatternRaw),
          modality: Value(modality),
          cnsScore: Value(cnsScore),
          programmingDifficulty: const Value('novice'),
          programmingCommonness: const Value('basic'),
          allowedTrainingStyles: Value(allowedTrainingStylesJson),
          technicalEligibility: const Value('automatic'),
          requiredEquipmentKeys: const Value('[]'),
          loggingMetric: Value(loggingMetric),
          category: Value(category),
        ),
      );

  /// Seeds the five-slot "base" day layout `_needsFor` falls back to for any
  /// day label that matches none of its named keywords (main: squat pattern,
  /// supplemental: horizontal_push, accessory: horizontal_pull, accessory:
  /// hinge, isolation: shoulder), each pattern/muscle backed by exactly one
  /// eligible candidate so slot assignment is fully deterministic.
  Future<void> seedBaseDayCatalog({
    String mainModality = 'barbell',
    String? isolationMovementPatternRaw,
  }) async {
    await insertExercise(
      slug: 'fixture-main-squat',
      name: 'Fixture Main Squat',
      primaryMuscle: 'Quads',
      movementPattern: 'squat',
      modality: mainModality,
    );
    await insertExercise(
      slug: 'fixture-supplemental-push',
      name: 'Fixture Supplemental Push',
      primaryMuscle: 'Chest',
      movementPattern: 'horizontal_push',
    );
    await insertExercise(
      slug: 'fixture-accessory-pull',
      name: 'Fixture Accessory Pull',
      primaryMuscle: 'Back',
      movementPattern: 'horizontal_pull',
    );
    await insertExercise(
      slug: 'fixture-accessory-hinge',
      name: 'Fixture Accessory Hinge',
      primaryMuscle: 'Hamstrings',
      movementPattern: 'hinge',
    );
    await insertExercise(
      slug: 'fixture-isolation-shoulder',
      name: 'Fixture Isolation Shoulder',
      primaryMuscle: 'Shoulder',
      mechanics: 'isolation',
      cnsScore: 1,
      movementPatternRaw: isolationMovementPatternRaw,
    );
  }

  Future<int> createBaseDayProgram({int weeks = 1}) {
    final plan = SplitTemplates.generate(
      type: SplitType.custom,
      daysPerWeek: 1,
      customSlots: const ['Test Day'],
    );
    return ProgramsRepository(db).createProgramFromSplit(
      name: 'Time-budget fixture',
      weeks: weeks,
      plan: plan,
      startDate: DateTime(2026, 9, 7),
      buildMode: ProgramBuildMode.smart,
      trainingGoal: TrainingGoal.hypertrophy,
      experienceLevel: ExperienceLevel.intermediate,
    );
  }

  Future<List<ProgramDayExerciseData>> dayExercisesFor(int programId) async {
    final day = await (db.select(db.programDays).join([
      innerJoin(
        db.programWeeks,
        db.programWeeks.id.equalsExp(db.programDays.programWeekId),
      ),
    ])..where(db.programWeeks.programId.equals(programId))).getSingle();
    return (db.select(
      db.programDayExercises,
    )..where((t) => t.programDayId.equals(day.readTable(db.programDays).id))).get();
  }

  test(
    'a short workoutDurationMinutes trims accessory/isolation volume; '
    'main/supplemental slot counts are unaffected (D-05/D-07)',
    () async {
      await seedBaseDayCatalog();

      final longBudgetProgramId = await createBaseDayProgram();
      await SmartProgramPlanner(db).populate(
        longBudgetProgramId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 90,
        ),
      );
      final longRows = await dayExercisesFor(longBudgetProgramId);

      final shortBudgetProgramId = await createBaseDayProgram();
      await SmartProgramPlanner(db).populate(
        shortBudgetProgramId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 30,
        ),
      );
      final shortRows = await dayExercisesFor(shortBudgetProgramId);

      int accessoryIsolationSets(List<ProgramDayExerciseData> rows) => rows
          .where(
            (r) =>
                r.slotRole == SlotRole.accessory.id ||
                r.slotRole == SlotRole.isolation.id,
          )
          .fold(0, (sum, r) => sum + r.targetSets);
      int mainSupplementalCount(List<ProgramDayExerciseData> rows) => rows
          .where(
            (r) =>
                r.slotRole == SlotRole.main.id ||
                r.slotRole == SlotRole.supplemental.id,
          )
          .length;

      expect(
        accessoryIsolationSets(shortRows),
        lessThan(accessoryIsolationSets(longRows)),
        reason:
            'the 30-minute-budget day must trim less total accessory/'
            'isolation volume (fewer sets, or fewer rows) than the '
            '90-minute-budget day',
      );
      expect(
        mainSupplementalCount(shortRows),
        mainSupplementalCount(longRows),
        reason:
            'SlotRole.main/supplemental slots must never be trimmed by the '
            'time-budget pass',
      );
      expect(
        mainSupplementalCount(shortRows),
        2,
        reason: 'both the main and supplemental slot survive every trim',
      );
    },
  );

  test(
    'a warmup-eligible main lift trims more than an otherwise-identical '
    'warmup-ineligible main lift, proving warmup time reaches the trim '
    'decision (D-06/D-08/T-18-11)',
    () async {
      // Barbell earns both SlotRole.main eligibility (cnsScore>=5 + in
      // SlotRoleEligibility's max-effort modality set) AND a non-empty
      // WarmupResolver ramp (in WarmupResolver's eligible-modality set).
      final barbellProgramId = await () async {
        await seedBaseDayCatalog(mainModality: 'barbell');
        return createBaseDayProgram();
      }();
      await SmartProgramPlanner(db).populate(
        barbellProgramId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 52,
        ),
      );
      final barbellRows = await dayExercisesFor(barbellProgramId);

      // machine_plate still earns SlotRole.main eligibility (also in
      // SlotRoleEligibility's max-effort modality set) but is excluded from
      // WarmupResolver's narrower eligible-modality set {barbell, dumbbell,
      // kettlebell} — so its warmup ramp is empty despite being a legitimate
      // main lift.
      final db2 = await openTestDatabase();
      await db2
          .into(db2.gyms)
          .insert(
            GymsCompanion.insert(
              name: 'Isolated fixture gym 2',
              isDefault: const Value(true),
              allEquipment: const Value(false),
            ),
          );
      Future<int> insertExercise2({
        required String slug,
        required String name,
        required String primaryMuscle,
        String? movementPattern,
        String mechanics = 'compound',
        String modality = 'barbell',
        int cnsScore = 5,
      }) => db2
          .into(db2.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              slug: Value(slug),
              name: name,
              primaryMuscle: primaryMuscle,
              equipment: modality,
              mechanics: mechanics,
              force: 'push',
              plane: 'none',
              movementPattern: Value(movementPattern),
              modality: Value(modality),
              cnsScore: Value(cnsScore),
              programmingDifficulty: const Value('novice'),
              programmingCommonness: const Value('basic'),
              allowedTrainingStyles: const Value('["weightlifting"]'),
              technicalEligibility: const Value('automatic'),
              requiredEquipmentKeys: const Value('[]'),
            ),
          );
      await insertExercise2(
        slug: 'fixture-main-squat-2',
        name: 'Fixture Main Squat',
        primaryMuscle: 'Quads',
        movementPattern: 'squat',
        modality: 'machine_plate',
      );
      await insertExercise2(
        slug: 'fixture-supplemental-push-2',
        name: 'Fixture Supplemental Push',
        primaryMuscle: 'Chest',
        movementPattern: 'horizontal_push',
      );
      await insertExercise2(
        slug: 'fixture-accessory-pull-2',
        name: 'Fixture Accessory Pull',
        primaryMuscle: 'Back',
        movementPattern: 'horizontal_pull',
      );
      await insertExercise2(
        slug: 'fixture-accessory-hinge-2',
        name: 'Fixture Accessory Hinge',
        primaryMuscle: 'Hamstrings',
        movementPattern: 'hinge',
      );
      await insertExercise2(
        slug: 'fixture-isolation-shoulder-2',
        name: 'Fixture Isolation Shoulder',
        primaryMuscle: 'Shoulder',
        mechanics: 'isolation',
        cnsScore: 1,
      );
      final plan2 = SplitTemplates.generate(
        type: SplitType.custom,
        daysPerWeek: 1,
        customSlots: const ['Test Day'],
      );
      final machinePlateProgramId = await ProgramsRepository(
        db2,
      ).createProgramFromSplit(
        name: 'Time-budget fixture (warmup-ineligible main)',
        weeks: 1,
        plan: plan2,
        startDate: DateTime(2026, 9, 7),
        buildMode: ProgramBuildMode.smart,
        trainingGoal: TrainingGoal.hypertrophy,
        experienceLevel: ExperienceLevel.intermediate,
      );
      await SmartProgramPlanner(db2).populate(
        machinePlateProgramId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 52,
        ),
      );
      final day2 = await (db2.select(db2.programDays).join([
        innerJoin(
          db2.programWeeks,
          db2.programWeeks.id.equalsExp(db2.programDays.programWeekId),
        ),
      ])..where(db2.programWeeks.programId.equals(machinePlateProgramId))).getSingle();
      final machinePlateRows = await (db2.select(
        db2.programDayExercises,
      )..where(
        (t) => t.programDayId.equals(day2.readTable(db2.programDays).id),
      )).get();
      await db2.close();

      final barbellIsolationSets = barbellRows
          .firstWhere((r) => r.slotRole == SlotRole.isolation.id)
          .targetSets;
      final machinePlateIsolationSets = machinePlateRows
          .firstWhere((r) => r.slotRole == SlotRole.isolation.id)
          .targetSets;

      expect(
        barbellIsolationSets,
        lessThan(machinePlateIsolationSets),
        reason:
            'the barbell main lift carries real warmup time into the trim '
            'estimate and must trim more isolation volume than the '
            'otherwise-identical machine_plate main lift, whose warmup ramp '
            'is empty per WarmupResolver\'s narrower eligible-modality gate',
      );

      final barbellMainSets = barbellRows
          .firstWhere((r) => r.slotRole == SlotRole.main.id)
          .targetSets;
      final machinePlateMainSets = machinePlateRows
          .firstWhere((r) => r.slotRole == SlotRole.main.id)
          .targetSets;
      final barbellSupplementalSets = barbellRows
          .firstWhere((r) => r.slotRole == SlotRole.supplemental.id)
          .targetSets;
      final machinePlateSupplementalSets = machinePlateRows
          .firstWhere((r) => r.slotRole == SlotRole.supplemental.id)
          .targetSets;
      expect(barbellMainSets, machinePlateMainSets);
      expect(barbellSupplementalSets, machinePlateSupplementalSets);
    },
  );

  test(
    'a real unilateral flag from the exercise catalog doubles working-set '
    'time and reaches the trim decision, not an empty/false placeholder',
    () async {
      await seedBaseDayCatalog(
        isolationMovementPatternRaw: 'Lateral Raise (unilateral)',
      );
      final unilateralProgramId = await createBaseDayProgram();
      await SmartProgramPlanner(db).populate(
        unilateralProgramId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 53,
        ),
      );
      final unilateralRows = await dayExercisesFor(unilateralProgramId);

      final db2 = await openTestDatabase();
      await db2
          .into(db2.gyms)
          .insert(
            GymsCompanion.insert(
              name: 'Isolated fixture gym 3',
              isDefault: const Value(true),
              allEquipment: const Value(false),
            ),
          );
      final planner2 = SmartProgramPlanner(db2);
      Future<int> seed2() async {
        Future<int> insertExercise2({
          required String slug,
          required String name,
          required String primaryMuscle,
          String? movementPattern,
          String mechanics = 'compound',
          String modality = 'barbell',
          int cnsScore = 5,
        }) => db2
            .into(db2.exerciseCatalog)
            .insert(
              ExerciseCatalogCompanion.insert(
                slug: Value(slug),
                name: name,
                primaryMuscle: primaryMuscle,
                equipment: modality,
                mechanics: mechanics,
                force: 'push',
                plane: 'none',
                movementPattern: Value(movementPattern),
                modality: Value(modality),
                cnsScore: Value(cnsScore),
                programmingDifficulty: const Value('novice'),
                programmingCommonness: const Value('basic'),
                allowedTrainingStyles: const Value('["weightlifting"]'),
                technicalEligibility: const Value('automatic'),
                requiredEquipmentKeys: const Value('[]'),
              ),
            );
        await insertExercise2(
          slug: 'fixture-main-squat-3',
          name: 'Fixture Main Squat',
          primaryMuscle: 'Quads',
          movementPattern: 'squat',
        );
        await insertExercise2(
          slug: 'fixture-supplemental-push-3',
          name: 'Fixture Supplemental Push',
          primaryMuscle: 'Chest',
          movementPattern: 'horizontal_push',
        );
        await insertExercise2(
          slug: 'fixture-accessory-pull-3',
          name: 'Fixture Accessory Pull',
          primaryMuscle: 'Back',
          movementPattern: 'horizontal_pull',
        );
        await insertExercise2(
          slug: 'fixture-accessory-hinge-3',
          name: 'Fixture Accessory Hinge',
          primaryMuscle: 'Hamstrings',
          movementPattern: 'hinge',
        );
        await insertExercise2(
          slug: 'fixture-isolation-shoulder-3',
          name: 'Fixture Isolation Shoulder',
          primaryMuscle: 'Shoulder',
          mechanics: 'isolation',
          cnsScore: 1,
        );
        final plan2 = SplitTemplates.generate(
          type: SplitType.custom,
          daysPerWeek: 1,
          customSlots: const ['Test Day'],
        );
        return ProgramsRepository(db2).createProgramFromSplit(
          name: 'Time-budget fixture (bilateral isolation)',
          weeks: 1,
          plan: plan2,
          startDate: DateTime(2026, 9, 7),
          buildMode: ProgramBuildMode.smart,
          trainingGoal: TrainingGoal.hypertrophy,
          experienceLevel: ExperienceLevel.intermediate,
        );
      }

      final bilateralProgramId = await seed2();
      await planner2.populate(
        bilateralProgramId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 53,
        ),
      );
      final day2 = await (db2.select(db2.programDays).join([
        innerJoin(
          db2.programWeeks,
          db2.programWeeks.id.equalsExp(db2.programDays.programWeekId),
        ),
      ])..where(db2.programWeeks.programId.equals(bilateralProgramId))).getSingle();
      final bilateralRows = await (db2.select(
        db2.programDayExercises,
      )..where(
        (t) => t.programDayId.equals(day2.readTable(db2.programDays).id),
      )).get();
      await db2.close();

      final unilateralIsolationSets = unilateralRows
          .firstWhere((r) => r.slotRole == SlotRole.isolation.id)
          .targetSets;
      final bilateralIsolationSets = bilateralRows
          .firstWhere((r) => r.slotRole == SlotRole.isolation.id)
          .targetSets;

      expect(
        unilateralIsolationSets,
        lessThanOrEqualTo(bilateralIsolationSets),
        reason:
            'the unilateral isolation slot doubles its own working-set time '
            'per WorkoutDurationEstimator, so it must trim at least as much '
            'as the otherwise-identical bilateral slot',
      );
      expect(
        unilateralIsolationSets,
        lessThan(bilateralIsolationSets),
        reason:
            'a real unilateral flag (not an empty/false placeholder) must '
            'actually change the trim outcome at this budget',
      );
    },
  );

  test(
    'populate() persists allowTimeSavingSetTechniques onto the Programs row '
    '(PRES-04)',
    () async {
      await seedBaseDayCatalog();
      final programId = await createBaseDayProgram();
      await SmartProgramPlanner(db).populate(
        programId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          allowTimeSavingSetTechniques: true,
        ),
      );

      final program = await (db.select(
        db.programs,
      )..where((t) => t.id.equals(programId))).getSingle();
      expect(program.allowTimeSavingSetTechniques, isTrue);
    },
  );

  test(
    'a compressed short-session isolation slot writes a codec-decodable '
    'prescriptionCodecJson using SetType.myoReps (PRES-01)',
    () async {
      await seedBaseDayCatalog();
      final programId = await createBaseDayProgram();
      await SmartProgramPlanner(db).populate(
        programId,
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
          workoutDurationMinutes: 45,
          allowTimeSavingSetTechniques: true,
        ),
      );

      final rows = await dayExercisesFor(programId);
      final compressed = rows.firstWhere(
        (r) => r.slotRole == SlotRole.isolation.id,
      );
      expect(compressed.setType, SetType.myoReps.id);
      expect(compressed.prescriptionJson, isNull);
      expect(compressed.prescriptionCodecJson, isNotNull);

      final decoded = SlotPrescriptionCodec.decode(
        compressed.prescriptionCodecJson,
      );
      expect(decoded, isNotNull);
      expect(decoded!.segments.single.setType, SetType.myoReps);
    },
  );

  group('CrossFit/GPP segment wiring (CF-01/CF-02/CF-03)', () {
    Future<void> seedCrossfitCatalog() async {
      for (final slug in [
        'warmup',
        'skill',
        'strength',
        'metcon-a',
        'metcon-b',
        'metcon-c',
        'cooldown',
      ]) {
        await insertExercise(
          slug: 'fixture-crossfit-$slug',
          name: 'Fixture CrossFit $slug',
          primaryMuscle: 'Full body',
          allowedTrainingStylesJson: '["crossfit"]',
        );
      }
    }

    Future<void> seedConditioningFixture() => insertExercise(
      slug: 'fixture-conditioning',
      name: 'Fixture Conditioning',
      primaryMuscle: 'Full body',
      loggingMetric: 'time',
    );

    /// All `ProgramDayExercises` rows for [programId], across every week,
    /// paired with the owning week's `weekIndex` and ordered by
    /// (weekIndex, orderIndex) — the shape both the format-rotation and
    /// DE-guard tests need.
    Future<List<({int weekIndex, ProgramDayExerciseData row})>> allRowsFor(
      int programId,
    ) async {
      final joined =
          await (db.select(db.programDayExercises).join([
                innerJoin(
                  db.programDays,
                  db.programDays.id.equalsExp(
                    db.programDayExercises.programDayId,
                  ),
                ),
                innerJoin(
                  db.programWeeks,
                  db.programWeeks.id.equalsExp(db.programDays.programWeekId),
                ),
              ])
              ..where(db.programWeeks.programId.equals(programId))
              ..orderBy([
                OrderingTerm(expression: db.programWeeks.weekIndex),
                OrderingTerm(expression: db.programDayExercises.orderIndex),
              ]))
              .get();
      return [
        for (final row in joined)
          (
            weekIndex: row.readTable(db.programWeeks).weekIndex,
            row: row.readTable(db.programDayExercises),
          ),
      ];
    }

    Future<List<({int weekIndex, ProgramDayExerciseData row})>>
    rowsForDayLabel(int programId, String label) async {
      final all = await allRowsFor(programId);
      final dayIds = await (db.select(db.programDays)
            ..where((t) => t.slotLabel.equals(label)))
          .get();
      final dayIdSet = dayIds.map((d) => d.id).toSet();
      return all.where((r) => dayIdSet.contains(r.row.programDayId)).toList();
    }

    test(
      'a generated GPP-labeled day never produces trainingMethod == '
      "'dynamic_effort', for maxEffort AND linear periodization models "
      '(CF-03)',
      () async {
        await seedBaseDayCatalog();
        await seedConditioningFixture();

        Future<void> checkModel(PeriodizationModel model) async {
          final plan = SplitTemplates.generate(
            type: SplitType.fullBodyAbGpp,
            daysPerWeek: 3,
          );
          final programId = await ProgramsRepository(db).createProgramFromSplit(
            name: 'GPP DE-guard fixture (${model.id})',
            weeks: 1,
            plan: plan,
            startDate: DateTime(2026, 9, 7),
            periodizationModel: model.id,
            buildMode: ProgramBuildMode.smart,
            trainingGoal: TrainingGoal.strength,
            experienceLevel: ExperienceLevel.novice,
          );
          await SmartProgramPlanner(db).populate(
            programId,
            const SmartProgramConfiguration(
              goal: TrainingGoal.strength,
              experience: ExperienceLevel.novice,
              trainingStyle: TrainingStyle.fullBody2xGpp,
            ),
          );

          final gppRows = await rowsForDayLabel(programId, 'GPP');
          expect(
            gppRows,
            isNotEmpty,
            reason: 'the GPP day must produce at least one row (${model.id})',
          );
          expect(
            gppRows.any(
              (r) =>
                  r.row.trainingMethod ==
                  SlotTrainingMethod.dynamicEffort.id,
            ),
            isFalse,
            reason:
                'GPP day must never contain a dynamic_effort row '
                '(periodization: ${model.id})',
          );
        }

        await checkModel(PeriodizationModel.maxEffort);
        await checkModel(PeriodizationModel.linear);
      },
    );

    test(
      'a generated CrossFit day writes ProgramDayExercises.sessionSegment in '
      'warmup->skill->strength->metcon->cooldown order, with every metcon row '
      'sharing one non-null supersetGroup (CF-01)',
      () async {
        await seedCrossfitCatalog();
        final plan = SplitTemplates.generate(
          type: SplitType.crossfit,
          daysPerWeek: 1,
        );
        final programId = await ProgramsRepository(db).createProgramFromSplit(
          name: 'CrossFit segment-order fixture',
          weeks: 1,
          plan: plan,
          startDate: DateTime(2026, 9, 7),
          buildMode: ProgramBuildMode.smart,
          trainingGoal: TrainingGoal.athletic,
          experienceLevel: ExperienceLevel.novice,
        );
        await SmartProgramPlanner(db).populate(
          programId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.athletic,
            experience: ExperienceLevel.novice,
            trainingStyle: TrainingStyle.crossfit,
          ),
        );

        final rows = await rowsForDayLabel(programId, 'CrossFit');
        expect(
          rows.map((r) => r.row.sessionSegment).toList(),
          ['warmup', 'skill', 'strength', 'metcon', 'metcon', 'cooldown'],
          reason: 'novice movement ceiling is 2, so exactly 2 metcon rows',
        );
        final metconGroups = rows
            .where((r) => r.row.sessionSegment == 'metcon')
            .map((r) => r.row.supersetGroup)
            .toSet();
        expect(
          metconGroups.length,
          1,
          reason: 'all metcon rows must share one supersetGroup value',
        );
        expect(metconGroups.single, isNotNull);
      },
    );

    test(
      "a generated CrossFit program's metcon format rotates AMRAP -> EMOM -> "
      'For Time across weeks 1-3, matching variationSeed: week.weekIndex '
      '(CF-01)',
      () async {
        await seedCrossfitCatalog();
        final plan = SplitTemplates.generate(
          type: SplitType.crossfit,
          daysPerWeek: 1,
        );
        final programId = await ProgramsRepository(db).createProgramFromSplit(
          name: 'CrossFit format-rotation fixture',
          weeks: 3,
          plan: plan,
          startDate: DateTime(2026, 9, 7),
          buildMode: ProgramBuildMode.smart,
          trainingGoal: TrainingGoal.athletic,
          experienceLevel: ExperienceLevel.novice,
        );
        await SmartProgramPlanner(db).populate(
          programId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.athletic,
            experience: ExperienceLevel.novice,
            trainingStyle: TrainingStyle.crossfit,
          ),
        );

        final rows = await rowsForDayLabel(programId, 'CrossFit');
        const expectedFormats = [SetType.amrap, SetType.emom, SetType.forTime];
        for (var weekIndex = 0; weekIndex < 3; weekIndex++) {
          final metconRow = rows.firstWhere(
            (r) =>
                r.weekIndex == weekIndex && r.row.sessionSegment == 'metcon',
          );
          final decoded = SlotPrescriptionCodec.decode(
            metconRow.row.prescriptionCodecJson,
          );
          expect(
            decoded,
            isNotNull,
            reason: 'week $weekIndex metcon row must decode',
          );
          expect(
            decoded!.segments.single.setType,
            expectedFormats[weekIndex],
            reason: 'week $weekIndex must use ${expectedFormats[weekIndex]}',
          );
        }
      },
    );

    test(
      'a Full Body 2x + GPP program produces exactly 2 non-GPP strength days '
      'plus 1 GPP day, and no row has both a heavy slotRole and a '
      'sessionSegment tag (CF-03)',
      () async {
        await seedBaseDayCatalog();
        await seedConditioningFixture();

        final plan = SplitTemplates.generate(
          type: SplitType.fullBodyAbGpp,
          daysPerWeek: 3,
        );
        final programId = await ProgramsRepository(db).createProgramFromSplit(
          name: 'Full Body 2x + GPP shape fixture',
          weeks: 1,
          plan: plan,
          startDate: DateTime(2026, 9, 7),
          buildMode: ProgramBuildMode.smart,
          trainingGoal: TrainingGoal.strength,
          experienceLevel: ExperienceLevel.intermediate,
        );
        await SmartProgramPlanner(db).populate(
          programId,
          const SmartProgramConfiguration(
            goal: TrainingGoal.strength,
            experience: ExperienceLevel.intermediate,
            trainingStyle: TrainingStyle.fullBody2xGpp,
          ),
        );

        final days = await (db.select(db.programDays).join([
          innerJoin(
            db.programWeeks,
            db.programWeeks.id.equalsExp(db.programDays.programWeekId),
          ),
        ])..where(db.programWeeks.programId.equals(programId))).get();
        final labels = days
            .map((r) => r.readTable(db.programDays).slotLabel)
            .toList();
        expect(labels.where((l) => l == 'GPP').length, 1);
        expect(
          labels.where((l) => l == 'Full Body A' || l == 'Full Body B').length,
          2,
        );

        final all = await allRowsFor(programId);
        const heavyRoles = {'main', 'supplemental'};
        expect(
          all.any(
            (r) =>
                heavyRoles.contains(r.row.slotRole) &&
                r.row.sessionSegment != null,
          ),
          isFalse,
          reason:
              'a main/supplemental slot must never carry a CrossFit/GPP '
              'sessionSegment tag',
        );
      },
    );
  });
}
