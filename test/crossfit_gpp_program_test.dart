import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  Future<List<ProgramDayExerciseData>> exercisesFor(int programId) async {
    final rows = await (db.select(db.programDayExercises).join([
      innerJoin(
        db.programDays,
        db.programDays.id.equalsExp(db.programDayExercises.programDayId),
      ),
      innerJoin(
        db.programWeeks,
        db.programWeeks.id.equalsExp(db.programDays.programWeekId),
      ),
    ])..where(db.programWeeks.programId.equals(programId))).get();
    return rows.map((row) => row.readTable(db.programDayExercises)).toList();
  }

  Future<int> createAndPopulate({
    required SplitPlan plan,
    required SmartProgramConfiguration configuration,
  }) async {
    final id = await ProgramsRepository(db).createProgramFromSplit(
      name: 'GPP test',
      weeks: 2,
      plan: plan,
      startDate: DateTime(2026, 9, 7),
      buildMode: ProgramBuildMode.smart,
      trainingGoal: configuration.goal,
      experienceLevel: configuration.experience,
    );
    await SmartProgramPlanner(db).populate(id, configuration);
    return id;
  }

  test('Full Body A/B + GPP split exposes the optional standalone GPP day', () {
    final plan = SplitTemplates.generate(
      type: SplitType.fullBodyAbGpp,
      daysPerWeek: 3,
    );

    expect(plan.trainingDays.map((day) => day.label), [
      'Full Body A',
      'Full Body B',
      'GPP',
    ]);
    expect(
      SplitTemplates.generate(
        type: SplitType.fullBodyAbGpp,
        daysPerWeek: 2,
      ).trainingDays.map((day) => day.label),
      ['Full Body A', 'Full Body B'],
    );
  });

  test(
    'GPP finish is selected, optional, and never added to normal Full Body',
    () async {
      final normalId = await createAndPopulate(
        plan: SplitTemplates.generate(
          type: SplitType.fullBodyAb,
          daysPerWeek: 2,
        ),
        configuration: const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.novice,
        ),
      );
      expect(
        (await exercisesFor(normalId)).map((row) => row.slotRole),
        isNot(contains(SlotRole.conditioning.id)),
      );

      final optedInId = await createAndPopulate(
        plan: SplitTemplates.generate(
          type: SplitType.fullBodyAb,
          daysPerWeek: 2,
        ),
        configuration: const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.novice,
          trainingStyle: TrainingStyle.fullBody2xGpp,
        ),
      );
      final optedIn = await exercisesFor(optedInId);
      expect(
        optedIn.where((row) => row.slotRole == SlotRole.conditioning.id),
        hasLength(4),
        reason: 'One GPP finish is generated for each Full Body A/B day/week.',
      );

      final optedOutId = await createAndPopulate(
        plan: SplitTemplates.generate(
          type: SplitType.fullBodyAb,
          daysPerWeek: 2,
        ),
        configuration: const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.novice,
          trainingStyle: TrainingStyle.fullBody2xGpp,
          includeGppConditioning: false,
        ),
      );
      expect(
        (await exercisesFor(optedOutId)).map((row) => row.slotRole),
        isNot(contains(SlotRole.conditioning.id)),
      );
    },
  );

  test('novice CrossFit plan remains conditioning-first and curated', () async {
    final programId = await createAndPopulate(
      plan: SplitTemplates.generate(type: SplitType.crossfit, daysPerWeek: 2),
      configuration: const SmartProgramConfiguration(
        goal: TrainingGoal.athletic,
        experience: ExperienceLevel.novice,
        trainingStyle: TrainingStyle.crossfit,
      ),
    );

    final rows = await exercisesFor(programId);
    expect(rows, isNotEmpty);
    // 21-06: CrossFit now routes through CrossfitProgramPlanner's ordered
    // warmup/skill/strength/metcon/cooldown blueprint instead of the bare
    // 2-slot SlotRole.conditioning stub this test originally guarded.
    // "Conditioning-first" now means every segment-tagged slot is
    // categorically forced to a non-heavy, non-Dynamic-Effort method
    // (T-21-01), not that every row literally uses SlotRole.conditioning.
    expect(
      rows.every(
        (row) =>
            row.slotRole == SlotRole.accessory.id ||
            row.slotRole == SlotRole.supplemental.id,
      ),
      isTrue,
      reason: 'CrossFit segment slots are accessory/supplemental only',
    );
    expect(
      rows.every(
        (row) => row.trainingMethod != SlotTrainingMethod.dynamicEffort.id,
      ),
      isTrue,
      reason: 'CrossFit segment slots must never be Dynamic Effort',
    );
    // Warmup/skill/strength/cooldown are structural placeholders with no
    // curated content pool this phase (D-03/D-04) — the real catalog may
    // legitimately leave some of them empty (no safe candidate), rather than
    // forcing an unsafe/uncurated exercise. Metcon (novice ceiling >= 1) is
    // the one segment guaranteed to materialize from the 17 crossfit-tagged
    // exercises Phase 16 curated.
    final segments = rows.map((row) => row.sessionSegment).toSet();
    expect(
      segments,
      everyElement(
        anyOf(['warmup', 'skill', 'strength', 'metcon', 'cooldown']),
      ),
    );
    expect(segments, contains('metcon'));

    final selectedIds = rows.map((row) => row.exerciseId).toSet();
    final selected = await (db.select(
      db.exerciseCatalog,
    )..where((exercise) => exercise.id.isIn(selectedIds))).get();
    expect(selected, isNotEmpty);
    expect(
      selected.every((exercise) => exercise.programmingDifficulty == 'novice'),
      isTrue,
    );
    expect(
      selected.every(
        (exercise) => exercise.technicalEligibility == 'automatic',
      ),
      isTrue,
    );
    expect(
      selected.every(
        (exercise) => exercise.allowedTrainingStyles!.contains('crossfit'),
      ),
      isTrue,
    );
  });
}
