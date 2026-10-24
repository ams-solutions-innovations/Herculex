import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/lift_best_extractor.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_survey.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/profile/domain/profile.dart';

const _evaluator = StrengthTierEvaluator();
const _extractor = LiftBestExtractor();

LevelBand _tier(
  Map<StrengthLift, LiftBest> bests, {
  BiologicalSex sex = BiologicalSex.male,
}) => _evaluator.evaluate(bests: bests, sex: sex).tier;

LiftSetSample _bar(StrengthLift lift, double kg, int reps, {double? bw}) =>
    LiftSetSample(lift: lift, loadKg: kg, reps: reps, bodyweightKg: bw);

LiftSetSample _cal(StrengthLift lift, int reps, {bool assisted = false}) =>
    LiftSetSample(lift: lift, loadKg: 0, reps: reps, assisted: assisted);

void main() {
  group('StrengthTierEvaluator', () {
    test('140 kg bench and muscle-ups place a new user in Advanced', () {
      final bests = _extractor.extract(
        samples: const [],
        profileBodyweightKg: 80,
        survey: const StrengthSurvey(
          style: TrainingStyle.both,
          lifts: {
            StrengthLift.bench: SurveyLiftEntry(weightKg: 140, reps: 1),
            StrengthLift.muscleUp: SurveyLiftEntry(reps: 3),
          },
        ),
      );

      // 1.75× bench clears Elite on paper, but self-reported caps at Advanced.
      expect(_tier(bests), LevelBand.advanced);
    });

    test('a sub-100 kg squat keeps a long-time user out of the top bands', () {
      final bests = _extractor.extract(
        samples: [
          _bar(StrengthLift.squat, 95, 1, bw: 85),
          _bar(StrengthLift.bench, 90, 1, bw: 85),
          _bar(StrengthLift.deadlift, 140, 1, bw: 85),
        ],
        profileBodyweightKg: 85,
      );

      final assessment = _evaluator.evaluate(
        bests: bests,
        sex: BiologicalSex.male,
      );
      expect(assessment.tier, LevelBand.intermediate);
      final squat = assessment
          .requirementsFor(LevelBand.advanced)
          .firstWhere((r) => r.lift == StrengthLift.squat);
      expect(squat.met, isFalse);
      expect(squat.required, 1.75);
      expect(squat.current, closeTo(95 / 85, 0.001));
    });

    test('one strong lift alone is not enough for a band', () {
      final bests = _extractor.extract(
        samples: [_bar(StrengthLift.deadlift, 250, 1, bw: 80)],
        profileBodyweightKg: 80,
      );

      expect(_tier(bests), LevelBand.novice);
    });

    test('Elite needs two logged lifts; reported ones are flagged', () {
      final bests = _extractor.extract(
        samples: [_bar(StrengthLift.squat, 190, 1, bw: 80)],
        profileBodyweightKg: 80,
        survey: const StrengthSurvey(
          style: TrainingStyle.weights,
          lifts: {
            StrengthLift.deadlift: SurveyLiftEntry(weightKg: 220, reps: 1),
          },
        ),
      );
      final assessment = _evaluator.evaluate(
        bests: bests,
        sex: BiologicalSex.male,
      );

      expect(assessment.tier, LevelBand.advanced);
      final deadlift = assessment
          .requirementsFor(LevelBand.elite)
          .firstWhere((r) => r.lift == StrengthLift.deadlift);
      expect(deadlift.met, isFalse);
      expect(deadlift.needsLogging, isTrue);

      final logged = _extractor.extract(
        samples: [
          _bar(StrengthLift.squat, 190, 1, bw: 80),
          _bar(StrengthLift.deadlift, 220, 1, bw: 80),
        ],
        profileBodyweightKg: 80,
      );
      expect(_tier(logged), LevelBand.elite);
    });

    test('female standards use their own column', () {
      final bests = _extractor.extract(
        samples: [
          _bar(StrengthLift.squat, 60, 1, bw: 60),
          _bar(StrengthLift.bench, 40, 1, bw: 60),
        ],
        profileBodyweightKg: 60,
      );

      expect(_tier(bests), LevelBand.novice);
      expect(_tier(bests, sex: BiologicalSex.female), LevelBand.intermediate);
    });

    test('calisthenics counts strict reps and mixes with barbell lifts', () {
      final bests = _extractor.extract(
        samples: [
          _cal(StrengthLift.pullUp, 16),
          _bar(StrengthLift.overheadPress, 70, 1, bw: 80),
        ],
        profileBodyweightKg: 80,
      );

      expect(_tier(bests), LevelBand.advanced);
    });

    test('a single muscle-up also counts towards Intermediate', () {
      final bests = _extractor.extract(
        samples: [_cal(StrengthLift.muscleUp, 1), _cal(StrengthLift.dip, 15)],
        profileBodyweightKg: null,
      );

      expect(_tier(bests), LevelBand.intermediate);
    });
  });

  group('LiftBestExtractor', () {
    test('ignores assisted calisthenics sets', () {
      final bests = _extractor.extract(
        samples: [_cal(StrengthLift.pullUp, 20, assisted: true)],
        profileBodyweightKg: 80,
      );

      expect(bests, isEmpty);
    });

    test('without any bodyweight only calisthenics count', () {
      final bests = _extractor.extract(
        samples: [
          _bar(StrengthLift.squat, 200, 1),
          _cal(StrengthLift.pushUp, 40),
        ],
        profileBodyweightKg: null,
      );

      expect(bests.keys, [StrengthLift.pushUp]);
    });

    test('uses e1RM, prefers set bodyweight and keeps sources apart', () {
      final bests = _extractor.extract(
        samples: [
          _bar(StrengthLift.bench, 100, 5, bw: 100),
          _bar(StrengthLift.bench, 100, 1, bw: 100),
        ],
        profileBodyweightKg: 50,
        survey: const StrengthSurvey(
          style: TrainingStyle.weights,
          lifts: {StrengthLift.bench: SurveyLiftEntry(weightKg: 60, reps: 1)},
        ),
      );
      final bench = bests[StrengthLift.bench]!;

      // 100 × 5 → e1RM ≈ 114.9 kg, over the set's own 100 kg bodyweight.
      expect(bench.logged, closeTo(1.149, 0.01));
      expect(bench.reported, closeTo(60 / 50, 0.001));
      expect(bench.best, bench.reported);
    });

    test('maps catalogue slugs to benchmark lifts', () {
      expect(StrengthLift.forSlug('barbell-back-squat'), StrengthLift.squat);
      expect(StrengthLift.forSlug('chin-up-supinated'), StrengthLift.pullUp);
      expect(StrengthLift.forSlug('ring-muscle-up'), StrengthLift.muscleUp);
      expect(StrengthLift.forSlug('leg-press'), isNull);
    });
  });

  group('StrengthSurvey', () {
    test('round-trips through Profile JSON and tolerates its absence', () {
      const profile = Profile(
        goal: FitnessGoal.muscleGain,
        activityLevel: ActivityLevel.active,
        strengthSurvey: StrengthSurvey(
          style: TrainingStyle.calisthenics,
          lifts: {StrengthLift.pullUp: SurveyLiftEntry(reps: 12)},
        ),
      );

      final restored = Profile.decode(profile.encode());
      expect(restored.strengthSurvey?.style, TrainingStyle.calisthenics);
      expect(restored.strengthSurvey?.lifts[StrengthLift.pullUp]?.reps, 12);

      final legacy = Profile.fromJson({
        'goal': 'maintenance',
        'activityLevel': 'active',
      });
      expect(legacy.strengthSurvey, isNull);
    });
  });
}
