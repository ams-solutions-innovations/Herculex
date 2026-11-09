import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/program_guardrails.dart';
import 'package:herculex/features/programs/domain/program_set_structure.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/rotation_policy.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/domain/time_saving_policy.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    db = await openTestDatabase();
    await ExerciseImporter.runFromJson(
      db,
      File('assets/data/exercises.json').readAsStringSync(),
      movementsJson: File('assets/data/movements.json').readAsStringSync(),
      programmingMetadataJson: File(
        'assets/data/exercise_programming_metadata.json',
      ).readAsStringSync(),
    );
  });
  tearDown(() => db.close());

  Future<int> build({
    required SplitType split,
    required int days,
    int weeks = 4,
    PeriodizationModel model = PeriodizationModel.linear,
    TrainingGoal goal = TrainingGoal.hypertrophy,
    ExperienceLevel experience = ExperienceLevel.intermediate,
    TrainingStyle style = TrainingStyle.weightlifting,
    int? rotationWeeks,
    TrainingFocus focus = TrainingFocus.balanced,
    Map<String, SlotTrainingMethod> methods = const {},
    Map<String, String> priorities = const {},
    TimeSavingTechnique? technique,
  }) async {
    final programId = await ProgramsRepository(db).createProgramFromSplit(
      name: 'Fixture',
      weeks: weeks,
      plan: SplitTemplates.generate(
        type: split,
        daysPerWeek: days,
        distinctRepeatedDays: true,
      ),
      startDate: DateTime(2026, 9, 7),
      periodizationModel: model.id,
      buildMode: ProgramBuildMode.guided,
      trainingGoal: goal,
      experienceLevel: experience,
    );
    await SmartProgramPlanner(db).populate(
      programId,
      SmartProgramConfiguration(
        goal: goal,
        experience: experience,
        buildMode: ProgramBuildMode.guided,
        trainingStyle: style,
        waveOverrideWeeks: rotationWeeks,
        trainingFocus: focus,
        mainMethodByDayLabel: methods,
        musclePriorities: priorities,
        allowTimeSavingSetTechniques: technique != null,
        timeSavingTechnique: technique ?? TimeSavingTechnique.automatic,
      ),
    );
    return programId;
  }

  Future<List<ProgramDayData>> daysOf(int programId, int weekIndex) async {
    final week =
        await (db.select(db.programWeeks)..where(
              (t) =>
                  t.programId.equals(programId) & t.weekIndex.equals(weekIndex),
            ))
            .getSingle();
    return (db.select(db.programDays)
          ..where((t) => t.programWeekId.equals(week.id))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
  }

  Future<List<ProgramDayExerciseData>> rowsOf(int dayId) =>
      (db.select(db.programDayExercises)
            ..where((t) => t.programDayId.equals(dayId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();

  Future<ExerciseCatalogData> exerciseOf(int id) => (db.select(
    db.exerciseCatalog,
  )..where((t) => t.id.equals(id))).getSingle();

  group('A and B are different workouts', () {
    final splits = <(SplitType, int)>[
      (SplitType.upperLower, 4),
      (SplitType.ppl, 6),
      (SplitType.ppl, 5),
      (SplitType.fullBodyAb, 2),
      (SplitType.fullBody, 3),
      (SplitType.ab, 2),
      (SplitType.abc, 3),
    ];
    for (final (split, days) in splits) {
      for (final experience in ExperienceLevel.values) {
        for (final style in const [
          TrainingStyle.weightlifting,
          TrainingStyle.basic,
        ]) {
          test('${split.id} × $days, ${experience.id}, ${style.id}', () async {
            final programId = await build(
              split: split,
              days: days,
              experience: experience,
              style: style,
            );
            final byLabel = <String, List<int>>{};
            for (final day in await daysOf(programId, 0)) {
              final rows = await rowsOf(day.id);
              byLabel[day.slotLabel!] = [for (final r in rows) r.exerciseId];
            }
            expect(byLabel.length, greaterThanOrEqualTo(2));
            expect(ProgramGuardrails.validateDayDistinctness(byLabel), isEmpty);
          });
        }
      }
    }

    test('the Upper A and Upper B main lifts lead with different '
        'movements', () async {
      final programId = await build(split: SplitType.upperLower, days: 4);
      final days = await daysOf(programId, 0);
      expect(days.map((d) => d.slotLabel), [
        'Upper A',
        'Lower A',
        'Upper B',
        'Lower B',
      ]);
      final patterns = <String, String?>{};
      for (final day in days) {
        final main = (await rowsOf(day.id)).first;
        patterns[day.slotLabel!] = (await exerciseOf(
          main.exerciseId,
        )).movementPattern;
      }
      expect(patterns['Upper A'], 'horizontal_push');
      expect(patterns['Upper B'], 'vertical_push');
      expect(patterns['Lower A'], 'squat');
      expect(patterns['Lower B'], 'hinge');
    });

    test('Full Body A-B-A runs the same A twice, whatever its role', () async {
      final programId = await build(split: SplitType.fullBodyAb, days: 3);
      final days = await daysOf(programId, 0);
      expect(days.map((d) => d.slotLabel), [
        'Full Body A',
        'Full Body B',
        'Full Body A',
      ]);
      final first = await rowsOf(days[0].id);
      final third = await rowsOf(days[2].id);
      expect(third.map((r) => r.exerciseId), first.map((r) => r.exerciseId));
    });

    test('a Pull day keeps a pull when no main-eligible pull exists', () async {
      final programId = await build(split: SplitType.ppl, days: 6);
      final days = await daysOf(programId, 0);
      for (final day in days.where((d) => d.slotLabel!.startsWith('Pull'))) {
        final exercise = await exerciseOf(
          (await rowsOf(day.id)).first.exerciseId,
        );
        expect(
          exercise.movementPattern,
          anyOf('horizontal_pull', 'vertical_pull'),
          reason: '${day.slotLabel} led with ${exercise.name}',
        );
      }
    });

    test(
      'a rear-delt slot gets a rear-delt exercise, a row slot a row',
      () async {
        final programId = await build(split: SplitType.ppl, days: 3);
        final pull = (await daysOf(
          programId,
          0,
        )).firstWhere((d) => d.slotLabel == 'Pull');
        final names = [
          for (final row in await rowsOf(pull.id))
            (await exerciseOf(row.exerciseId)).name.toLowerCase(),
        ];
        expect(names.last, anyOf(contains('rear'), contains('reverse pec')));
        expect(
          names.first,
          isNot(anyOf(contains('rear'), contains('reverse pec'))),
        );
      },
    );

    test('the benchmark lift wins a heavy slot', () async {
      final programId = await build(split: SplitType.upperLower, days: 4);
      final days = await daysOf(programId, 0);
      final lowerA = days.firstWhere((d) => d.slotLabel == 'Lower A');
      final main = await exerciseOf((await rowsOf(lowerA.id)).first.exerciseId);
      expect(main.slug, 'barbell-back-squat');
    });
  });

  group('rotation is opt-in', () {
    Future<Set<int>> distinctPerSlot(int programId, String label) async {
      final slots = await (db.select(
        db.programExerciseSlots,
      )..where((t) => t.programId.equals(programId))).get();
      final changed = <int>{};
      for (final slot in slots.where((s) => s.daySlotLabel == label)) {
        final rows = await (db.select(
          db.rotationAssignments,
        )..where((t) => t.slotId.equals(slot.id))).get();
        if (rows.map((r) => r.exerciseId).toSet().length > 1) {
          changed.add(slot.id);
        }
      }
      return changed;
    }

    for (final model in [
      PeriodizationModel.none,
      PeriodizationModel.linear,
      PeriodizationModel.concurrent,
      PeriodizationModel.block,
    ]) {
      test('${model.id} keeps every exercise for the whole block', () async {
        final programId = await build(
          split: SplitType.upperLower,
          days: 4,
          weeks: 8,
          model: model,
        );
        expect(await distinctPerSlot(programId, 'Upper A'), isEmpty);
      });
    }

    test('a chosen cadence rotates assistance but not the main lift', () async {
      final programId = await build(
        split: SplitType.upperLower,
        days: 4,
        weeks: 8,
        rotationWeeks: 2,
      );
      expect(await distinctPerSlot(programId, 'Upper A'), isNotEmpty);
      final mainSlot =
          await (db.select(db.programExerciseSlots)..where(
                (t) =>
                    t.programId.equals(programId) &
                    t.daySlotLabel.equals('Upper A') &
                    t.role.equals(SlotRole.main.id),
              ))
              .get();
      for (final slot in mainSlot) {
        final rows = await (db.select(
          db.rotationAssignments,
        )..where((t) => t.slotId.equals(slot.id))).get();
        expect(rows.map((r) => r.exerciseId).toSet(), hasLength(1));
      }
    });

    test('RotationPolicy.forProgram: only Max Effort rotates by default', () {
      for (final role in SlotRole.values) {
        expect(
          RotationPolicy.forProgram(
            model: PeriodizationModel.block,
            role: role,
            blockPhase: 'accumulation',
          ).rotates,
          isFalse,
        );
        expect(
          RotationPolicy.forProgram(
            model: PeriodizationModel.maxEffort,
            role: role,
          ).rotates,
          isTrue,
        );
        expect(
          RotationPolicy.forProgram(
            model: PeriodizationModel.maxEffort,
            role: role,
            userRotationWeeks: 0,
          ).rotates,
          isFalse,
        );
      }
      expect(
        RotationPolicy.forProgram(
          model: PeriodizationModel.linear,
          role: SlotRole.accessory,
          userRotationWeeks: 3,
        ).everyWeeks,
        3,
      );
    });
  });

  group('intensity focus', () {
    /// A compound by the same definition the planner uses: flies are not.
    bool isCompound(ExerciseCatalogData e) =>
        e.mechanics == 'compound' &&
        !(e.cnsScore <= 3 &&
            RegExp(
              'rear|reverse pec|face pull',
            ).hasMatch(e.name.toLowerCase()));

    test('2 compound sets at RPE 9, 3 isolation sets, in every week', () async {
      final programId = await build(
        split: SplitType.upperLower,
        days: 4,
        weeks: 12,
        focus: TrainingFocus.intensity,
        priorities: const {'chest': 'high', 'quads': 'high'},
      );
      final resolver = PlannedSessionResolver(db);
      for (var w = 0; w < 12; w++) {
        final deload = Periodization.isPlannedDeload(
          model: PeriodizationModel.linear,
          totalWeeks: 12,
          weekIndex: w,
        );
        for (final day in await daysOf(programId, w)) {
          final plan = await resolver.resolveProgramDay(day.id);
          expect(plan.exercises, isNotEmpty);
          for (final item in plan.exercises) {
            final exercise = await exerciseOf(item.exerciseId);
            final working = item.sets.where((s) => !s.isWarmup).toList();
            final expected = isCompound(exercise) ? 2 : 3;
            if (deload) {
              expect(working.length, lessThan(expected));
            } else {
              expect(
                working,
                hasLength(expected),
                reason: 'week ${w + 1}, ${exercise.name}',
              );
            }
            if (isCompound(exercise)) {
              expect(working.first.rpeX10, 90);
            }
          }
        }
      }
    });

    test('compounds start from a warm-up ramp', () async {
      final programId = await build(
        split: SplitType.upperLower,
        days: 4,
        focus: TrainingFocus.intensity,
      );
      final day = (await daysOf(programId, 0)).first;
      final plan = await PlannedSessionResolver(db).resolveProgramDay(day.id);
      expect(plan.exercises.first.sets.first.isWarmup, isTrue);
    });

    test('a novice cannot receive it, whatever the builder sent', () async {
      final programId = await build(
        split: SplitType.upperLower,
        days: 4,
        experience: ExperienceLevel.novice,
        focus: TrainingFocus.intensity,
      );
      final rows = await rowsOf((await daysOf(programId, 0)).first.id);
      expect(
        rows.map((r) => r.trainingMethod),
        isNot(contains(SlotTrainingMethod.intensityFocus.id)),
      );
    });

    test('an explicit main-lift method is kept', () async {
      final programId = await build(
        split: SplitType.upperLower,
        days: 4,
        focus: TrainingFocus.intensity,
        methods: const {'Upper A': SlotTrainingMethod.topSetBackoff},
      );
      final upperA = (await daysOf(programId, 0)).first;
      final rows = await rowsOf(upperA.id);
      expect(rows.first.trainingMethod, SlotTrainingMethod.topSetBackoff.id);
      expect(rows[1].trainingMethod, SlotTrainingMethod.intensityFocus.id);
    });

    test('a rebuilt block keeps its rotation and focus', () async {
      final programId = await build(
        split: SplitType.upperLower,
        days: 4,
        rotationWeeks: 3,
        focus: TrainingFocus.intensity,
      );
      final choices = await ProgramsRepository(db).generationChoices(programId);
      expect(choices.rotationWeeks, 3);
      expect(choices.focus, TrainingFocus.intensity);
    });
  });

  group('program screens show what the workout runs', () {
    for (final (method, direction) in const [
      (SlotTrainingMethod.topSetBackoff, PyramidDirection.descending),
      (SlotTrainingMethod.reversePyramid, PyramidDirection.descending),
      (SlotTrainingMethod.pyramidUp, PyramidDirection.ascending),
      (SlotTrainingMethod.maxEffort, PyramidDirection.descending),
      (SlotTrainingMethod.straightSets, PyramidDirection.none),
    ]) {
      test('${method.id} summary matches the resolved workout', () async {
        final programId = await build(
          split: SplitType.upperLower,
          days: 4,
          goal: TrainingGoal.strength,
          methods: {'Upper A': method},
        );
        final day = (await daysOf(programId, 0)).first;
        final row = (await rowsOf(day.id)).first;
        final exercise = await exerciseOf(row.exerciseId);
        final week = await (db.select(
          db.programWeeks,
        )..where((t) => t.id.equals(day.programWeekId))).getSingle();
        final summary = ProgramSetStructure.describe(
          method: SlotTrainingMethod.fromId(row.trainingMethod),
          targets: SlotTargets(
            sets: row.targetSets,
            repsMin: row.targetRepsMin,
            repsMax: row.targetRepsMax,
            rir: row.targetRir,
            rpe: row.targetRpe,
          ),
          role: SlotRole.fromId(row.slotRole),
          model: PeriodizationModel.linear,
          week: WeekPrescription(
            weekIndex: week.weekIndex,
            intensityFactor: week.intensityFactor,
            volumeFactor: week.adjustmentFactor,
          ),
          mechanics: exercise.mechanics,
          modality: exercise.modality,
        );
        final plan = await PlannedSessionResolver(db).resolveProgramDay(day.id);
        final working = plan.exercises.first.sets.where((s) => !s.isWarmup);
        expect(summary.direction, direction);
        expect(
          summary.prescription.segments.fold<int>(0, (n, s) => n + s.sets),
          working.length,
        );
      });
    }
  });

  group('SplitTemplates A/B naming', () {
    test('repeats become A/B only when asked for', () {
      expect(SplitTemplates.slotsFor(SplitType.upperLower, daysPerWeek: 4), [
        'Upper',
        'Lower',
      ]);
      expect(
        SplitTemplates.slotsFor(
          SplitType.upperLower,
          daysPerWeek: 4,
          distinctRepeatedDays: true,
        ),
        ['Upper A', 'Lower A', 'Upper B', 'Lower B'],
      );
    });

    test('five PPL days use each label at most once', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 5,
        distinctRepeatedDays: true,
      );
      expect(plan.days.map((d) => d.label), [
        'Push A',
        'Pull A',
        'Legs A',
        'Push B',
        'Pull B',
      ]);
      expect(plan.slotSummary, hasLength(5));
    });

    test('a split that does not repeat keeps its plain names', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 3,
        distinctRepeatedDays: true,
      );
      expect(plan.days.map((d) => d.label), ['Push', 'Pull', 'Legs']);
    });
  });

  group('validateDayDistinctness', () {
    test('accepts different days and a small incidental overlap', () {
      expect(
        ProgramGuardrails.validateDayDistinctness({
          'A': [1, 2, 3, 4],
          'B': [5, 6, 7, 4],
        }),
        isEmpty,
      );
    });

    test('flags a shared main lift', () {
      expect(
        ProgramGuardrails.validateDayDistinctness({
          'A': [1, 2, 3],
          'B': [1, 5, 6],
        }).single.code,
        'day_same_main',
      );
    });

    test('flags days that are mostly the same', () {
      expect(
        ProgramGuardrails.validateDayDistinctness({
          'A': [1, 2, 3, 4],
          'B': [9, 2, 3, 4],
        }).single.code,
        'day_mostly_same',
      );
    });
  });

  group('how the user likes to train', () {
    Future<List<ProgramDayExerciseData>> isolationRows(int programId) async {
      final rows = <ProgramDayExerciseData>[];
      for (final day in await daysOf(programId, 0)) {
        rows.addAll(
          (await rowsOf(
            day.id,
          )).where((r) => r.slotRole == SlotRole.isolation.id),
        );
      }
      return rows;
    }

    test(
      'variety rotates assistance every three weeks and keeps the main',
      () async {
        final programId = await build(
          split: SplitType.upperLower,
          days: 4,
          weeks: 9,
          focus: TrainingFocus.variety,
        );
        final slots = await (db.select(
          db.programExerciseSlots,
        )..where((t) => t.programId.equals(programId))).get();
        expect(slots.every((s) => s.waveOverrideWeeks == 3), isTrue);
        var rotating = 0;
        for (final slot in slots) {
          final ids = {
            for (final a in await (db.select(
              db.rotationAssignments,
            )..where((t) => t.slotId.equals(slot.id))).get())
              a.exerciseId,
          };
          if (slot.role == SlotRole.main.id) {
            expect(ids, hasLength(1));
          } else if (ids.length > 1) {
            rotating++;
          }
        }
        expect(rotating, greaterThan(0));
      },
    );

    test('an explicit cadence beats the variety default', () {
      const configuration = SmartProgramConfiguration(
        goal: TrainingGoal.hypertrophy,
        experience: ExperienceLevel.intermediate,
        trainingFocus: TrainingFocus.variety,
        waveOverrideWeeks: 4,
      );
      expect(configuration.effectiveRotationWeeks, 4);
      expect(
        const SmartProgramConfiguration(
          goal: TrainingGoal.hypertrophy,
          experience: ExperienceLevel.intermediate,
        ).effectiveRotationWeeks,
        isNull,
      );
    });

    test(
      'intensity with myo-reps: hard compounds, myo-rep isolations',
      () async {
        final programId = await build(
          split: SplitType.upperLower,
          days: 4,
          focus: TrainingFocus.intensity,
          technique: TimeSavingTechnique.myoReps,
        );
        final isolations = await isolationRows(programId);
        expect(isolations, isNotEmpty);
        expect(
          isolations.where((r) => r.setType == 'myo_reps'),
          isNotEmpty,
          reason: 'the chosen technique reaches isolation work',
        );
        final compound = (await rowsOf(
          (await daysOf(programId, 0)).first.id,
        )).first;
        expect(compound.trainingMethod, SlotTrainingMethod.intensityFocus.id);
        expect(compound.targetSets, 2);
        expect(compound.setType, 'standard');
      },
    );

    test(
      'intensity without a technique keeps three plain isolation sets',
      () async {
        final programId = await build(
          split: SplitType.upperLower,
          days: 4,
          focus: TrainingFocus.intensity,
        );
        final isolations = await isolationRows(programId);
        expect(isolations, isNotEmpty);
        for (final row in isolations) {
          expect(row.targetSets, 3);
          expect(row.setType, 'standard');
        }
      },
    );

    test(
      'a novice gets straight sets whatever technique was asked for',
      () async {
        final programId = await build(
          split: SplitType.upperLower,
          days: 4,
          experience: ExperienceLevel.novice,
          focus: TrainingFocus.intensity,
          technique: TimeSavingTechnique.forcedReps,
        );
        for (final row in await isolationRows(programId)) {
          expect(row.setType, 'standard');
        }
      },
    );

    test(
      'forced reps are planned for an advanced lifter on stable isolation',
      () async {
        final programId = await build(
          split: SplitType.upperLower,
          days: 4,
          experience: ExperienceLevel.advanced,
          technique: TimeSavingTechnique.forcedReps,
        );
        final forced = (await isolationRows(
          programId,
        )).where((r) => r.setType == 'forced');
        expect(forced, isNotEmpty);
        for (final row in forced) {
          final exercise = await exerciseOf(row.exerciseId);
          expect(const {
            'cable',
            'machine_selectorized',
            'machine_plate',
            'machine_plate_loaded',
          }, contains(exercise.modality));
          expect(row.prescriptionWhy, contains('spotter'));
          expect(row.prescriptionWhy, contains('as you prefer'));
        }
      },
    );
  });
}
