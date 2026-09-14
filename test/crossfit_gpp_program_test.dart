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
    expect(
      rows.every((row) => row.slotRole == SlotRole.conditioning.id),
      isTrue,
    );

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
