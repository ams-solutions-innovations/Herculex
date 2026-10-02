import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/roadmap_draft_editor.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/dream_physique_nutrition_recommendation.dart';
import 'package:herculex/features/profile/domain/profile.dart';

PhysiqueRoadmapInput _input({
  double weight = 80,
  double current = 22,
  double target = 14,
  double change = -7,
  int months = 8,
  int? age = 30,
  AssessmentConfidence confidence = AssessmentConfidence.medium,
}) => PhysiqueRoadmapInput(
  weightKg: weight,
  currentBfPercent: current,
  targetBfPercent: target,
  plannedWeightChangeKg: change,
  estimatedMonths: months,
  ageYears: age,
  confidence: confidence,
);

void main() {
  group('propose', () {
    test('adult cut roadmap', () {
      final p = PhysiqueRoadmapGenerator.propose(_input());
      final first = p.phases.first;
      expect(first.phase, DietPhase.cut);
      expect(first.weeklyRateKg, closeTo(0.5, 1e-9));
      expect(first.plannedWeeks, 14);
      expect(first.targetWeightKg, 73.0);
      expect(first.targetBfPercent, 14);
      expect(p.wasCoerced, isFalse);
      // 14w cut -> 2w maintain -> maingain for the remaining 19 weeks.
      expect(p.phases.map((e) => e.phase).toList(), [
        DietPhase.cut,
        DietPhase.maintain,
        DietPhase.maingain,
      ]);
      expect(p.phases[1].plannedWeeks, 2);
      expect(p.phases[2].plannedWeeks, 19);
      expect(p.phases[2].targetWeightKg, greaterThan(73.0));
    });

    test('minor and unknown age never get cut or bulk', () {
      for (final age in [17, null]) {
        final p = PhysiqueRoadmapGenerator.propose(_input(age: age));
        expect(
          p.phases.any(
            (e) => e.phase == DietPhase.cut || e.phase == DietPhase.bulk,
          ),
          isFalse,
        );
        expect(p.phases.first.phase, DietPhase.recomp);
        expect(p.wasCoerced, isTrue);
        expect(p.requestedDirection, DietPhase.cut);
      }
    });

    test('low confidence restricts to maintain/recomp', () {
      final p = PhysiqueRoadmapGenerator.propose(
        _input(confidence: AssessmentConfidence.low),
      );
      expect(p.eligibility.allowedPhases, {
        DietPhase.maintain,
        DietPhase.recomp,
      });
      expect(p.phases.first.phase, DietPhase.recomp);
    });

    test('a long bulk is followed by a 2-week maintain', () {
      final p = PhysiqueRoadmapGenerator.propose(
        _input(current: 13, target: 14, change: 12, months: 12),
      );
      expect(p.phases.first.phase, DietPhase.bulk);
      expect(p.phases.first.plannedWeeks, greaterThanOrEqualTo(16));
      expect(p.phases[1].phase, DietPhase.maintain);
      expect(p.phases[1].plannedWeeks, 2);
    });

    test('recomp, maingain and maintain sizing', () {
      final recomp = PhysiqueRoadmapGenerator.propose(
        _input(current: 17, target: 14, change: -2, months: 6),
      );
      expect(recomp.phases.first.phase, DietPhase.recomp);
      expect(recomp.phases.first.plannedWeeks, 26);

      final maingain = PhysiqueRoadmapGenerator.propose(
        _input(current: 13, target: 14, change: 4, months: 1),
      );
      expect(maingain.phases.first.phase, DietPhase.maingain);
      expect(maingain.phases.first.plannedWeeks, 8);
    });

    test('unusable data yields one maintain phase', () {
      final p = PhysiqueRoadmapGenerator.propose(_input(current: 0));
      expect(p.phases, hasLength(1));
      expect(p.phases.first.phase, DietPhase.maintain);
      expect(p.phases.first.plannedWeeks, 4);
      expect(p.requestedDirection, isNull);
    });

    test('invariants hold across a grid of inputs', () {
      for (final age in [16, null, 25]) {
        for (final conf in AssessmentConfidence.values) {
          for (final change in [-12.0, -2.0, 0.0, 4.0, 9.0]) {
            for (final months in [1, 6, 24]) {
              final p = PhysiqueRoadmapGenerator.propose(
                _input(
                  age: age,
                  confidence: conf,
                  change: change,
                  months: months,
                  current: change > 5 ? 13 : 20,
                ),
              );
              expect(p.phases, isNotEmpty);
              for (final d in p.phases) {
                expect(p.eligibility.allows(d.phase), isTrue);
                expect(d.plannedWeeks, inInclusiveRange(2, 52));
              }
            }
          }
        }
      }
    });

    test('first phase matches the legacy recommender', () {
      const profile = Profile(
        goal: FitnessGoal.muscleGain,
        activityLevel: ActivityLevel.active,
        weightKg: 80,
        heightCm: 180,
      );
      for (final f in const [
        (22.0, 14.0, -7.0),
        (13.0, 14.0, 7.0),
        (17.0, 14.0, -2.0),
        (13.0, 14.0, 4.0),
      ]) {
        final legacy = DreamPhysiqueNutritionRecommender.recommend(
          profile: profile,
          summary: DreamPhysiqueAnalysisSummary(
            schemaVersion: 1,
            analyzedAt: DateTime.utc(2026, 9, 11),
            targetAestheticStyle: 'Athletic',
            timeframeRange: '12 months',
            estimatedMonths: 12,
            targetBfPercent: f.$2,
            currentEstimatedBf: f.$1,
            weightChangeKg: f.$3,
            currentPhotoCount: 0,
            targetPhotoCount: 0,
          ),
        );
        final p = PhysiqueRoadmapGenerator.propose(
          _input(current: f.$1, target: f.$2, change: f.$3, months: 12),
        );
        expect(p.phases.first.phase, legacy?.direction.dietPhase);
      }
    });
  });

  group('RoadmapDraftEditor', () {
    const unrestricted = PhaseEligibility.unrestricted();
    final list = [
      const RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 10),
      const RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 2),
      const RoadmapPhaseDraft(phase: DietPhase.maingain, plannedWeeks: 8),
      const RoadmapPhaseDraft(phase: DietPhase.recomp, plannedWeeks: 8),
    ];

    test('reorder uses ReorderableListView semantics', () {
      final out = RoadmapDraftEditor.reorder(list, 0, 3);
      expect(out.map((e) => e.phase).toList(), [
        DietPhase.maintain,
        DietPhase.maingain,
        DietPhase.cut,
        DietPhase.recomp,
      ]);
      final up = RoadmapDraftEditor.reorder(list, 3, 0);
      expect(up.first.phase, DietPhase.recomp);
      expect(list.first.phase, DietPhase.cut, reason: 'input not mutated');
    });

    test('resize clamps to 2..52', () {
      expect(RoadmapDraftEditor.resize(list, 0, 1)[0].plannedWeeks, 2);
      expect(RoadmapDraftEditor.resize(list, 0, 99)[0].plannedWeeks, 52);
      expect(RoadmapDraftEditor.resize(list, 0, 20)[0].plannedWeeks, 20);
    });

    test('remove keeps at least one phase', () {
      final single = [list.first];
      expect(RoadmapDraftEditor.remove(single, 0), single);
      expect(RoadmapDraftEditor.remove(list, 1), hasLength(3));
    });

    test('add respects eligibility', () {
      const low = PhaseEligibility(
        allowedPhases: {DietPhase.maintain, DietPhase.recomp},
      );
      expect(RoadmapDraftEditor.add(list, DietPhase.cut, low), list);
      final added = RoadmapDraftEditor.add(list, DietPhase.recomp, low);
      expect(added, hasLength(5));
      expect(added.last.plannedWeeks, 8);
      expect(RoadmapDraftEditor.canAdd(unrestricted, DietPhase.bulk), isTrue);
      expect(RoadmapDraftEditor.canAdd(low, DietPhase.bulk), isFalse);
    });

    test('retarget chains weight and recomputes pace', () {
      final out = RoadmapDraftEditor.retarget(
        list,
        startWeightKg: 80,
        goalTargetBfPercent: 14,
        maintenanceKcal: 2500,
        eligibility: unrestricted,
      );
      expect(out.map((e) => e.phase), list.map((e) => e.phase));
      expect(out[0].weeklyRateKg, closeTo(0.5, 1e-9));
      expect(out[0].targetWeightKg, 75.0);
      expect(out[0].targetBfPercent, 14);
      expect(out[1].targetWeightKg, 75.0);
      expect(out[2].targetWeightKg, greaterThan(75.0));
      expect(out[2].tempoCapped, isTrue);
      expect(out[2].targetBfPercent, isNull);
    });
  });
}
