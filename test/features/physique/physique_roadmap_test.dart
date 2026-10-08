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
  double? fat,
  double? lean,
}) => PhysiqueRoadmapInput(
  weightKg: weight,
  currentBfPercent: current,
  targetBfPercent: target,
  plannedWeightChangeKg: change,
  estimatedMonths: months,
  ageYears: age,
  confidence: confidence,
  fatLossKg: fat,
  leanGainKg: lean,
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
                expect(
                  d.targetWeightKg,
                  isNotNull,
                  reason: 'every phase names the weight it ends at',
                );
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

  group('full horizon', () {
    // The reported case: a 12-month goal that used to yield one 5-week cut.
    PhysiqueRoadmapProposal twelveMonths({double? lean = 3.5}) =>
        PhysiqueRoadmapGenerator.propose(
          _input(
            current: 20,
            target: 12,
            change: -2.5,
            months: 12,
            fat: 6,
            lean: lean,
          ),
        );

    test('a cut sized from gross fat loss covers all 12 months', () {
      final p = twelveMonths();
      expect(p.phases.map((e) => e.phase).toList(), [
        DietPhase.cut,
        DietPhase.maintain,
        DietPhase.maingain,
      ]);
      expect(p.phases.first.plannedWeeks, 12);
      expect(p.phases.first.targetWeightKg, 74.0);
      expect(p.totalWeeks, p.horizonWeeks);
      expect(p.horizonWeeks, 52);
      expect(p.extendedBeyondEstimate, isFalse);
      expect(p.finalWeightKg, greaterThan(74.0));
      for (final d in p.phases) {
        expect(d.targetWeightKg, isNotNull);
      }
    });

    test('without fat loss the net change is still used (old behaviour)', () {
      final p = PhysiqueRoadmapGenerator.propose(
        _input(current: 20, target: 12, change: -2.5, months: 12),
      );
      expect(p.phases.first.plannedWeeks, 5);
      // The short cut no longer ends the roadmap: it is followed by a
      // maintain and a build phase that fill the year.
      expect(p.phases.map((e) => e.phase).toList(), [
        DietPhase.cut,
        DietPhase.maintain,
        DietPhase.maingain,
      ]);
      expect(p.totalWeeks, p.horizonWeeks);
    });

    test('a lean gain too big for maingain pace becomes a bulk', () {
      final p = twelveMonths(lean: 9);
      expect(p.phases.map((e) => e.phase).toList(), [
        DietPhase.cut,
        DietPhase.maintain,
        DietPhase.bulk,
        DietPhase.maintain,
      ]);
      expect(p.phases[2].targetWeightKg, 83.0);
      expect(p.totalWeeks, p.horizonWeeks);
    });

    test('a bulk-first goal keeps going after the bulk', () {
      final p = PhysiqueRoadmapGenerator.propose(
        _input(current: 13, target: 14, change: 6, months: 12),
      );
      expect(p.phases.map((e) => e.phase).toList(), [
        DietPhase.bulk,
        DietPhase.maintain,
        DietPhase.maingain,
      ]);
      expect(p.totalWeeks, p.horizonWeeks);
    });

    test('recomp and maintain phases name the weight they hold', () {
      final recomp = PhysiqueRoadmapGenerator.propose(
        _input(current: 17, target: 14, change: -2, months: 12),
      );
      expect(recomp.phases.first.phase, DietPhase.recomp);
      expect(recomp.phases.first.plannedWeeks, 52);
      expect(recomp.phases.first.targetWeightKg, 80.0);
    });

    test('a goal that needs more time than the estimate says is flagged', () {
      final p = PhysiqueRoadmapGenerator.propose(
        _input(current: 30, target: 12, change: -16, months: 3, fat: 16),
      );
      expect(p.phases.first.plannedWeeks, 32);
      expect(p.totalWeeks, greaterThan(p.horizonWeeks));
      expect(p.extendedBeyondEstimate, isTrue);
    });

    test('minors still get nothing but recomp', () {
      final p = PhysiqueRoadmapGenerator.propose(
        _input(
          current: 20,
          target: 12,
          change: -2.5,
          months: 12,
          fat: 6,
          lean: 3.5,
          age: 16,
        ),
      );
      for (final d in p.phases) {
        expect(d.phase == DietPhase.cut || d.phase == DietPhase.bulk, isFalse);
      }
    });

    test('re-targeting a proposal changes nothing (editor and generator '
        'agree)', () {
      for (final lean in <double?>[null, 0, 3.5, 9]) {
        for (final fat in <double?>[null, 3.7, 6, 14]) {
          for (final (cur, tgt, chg) in const [
            (22.0, 14.0, -7.0),
            (20.0, 12.0, -2.5),
            (13.0, 14.0, 7.0),
            (13.0, 14.0, 4.0),
            (17.0, 14.0, -2.0),
          ]) {
            for (final months in [3, 12, 24]) {
              final p = PhysiqueRoadmapGenerator.propose(
                _input(
                  current: cur,
                  target: tgt,
                  change: chg,
                  months: months,
                  fat: fat,
                  lean: lean,
                ),
              );
              final again = RoadmapDraftEditor.retarget(
                p.phases,
                startWeightKg: 80,
                goalTargetBfPercent: tgt,
                maintenanceKcal: 2500,
                eligibility: p.eligibility,
              );
              expect(
                again,
                p.phases,
                reason: 'fat=$fat lean=$lean $cur>$tgt $chg ${months}m',
              );
            }
          }
        }
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

    test('retarget keeps a slower recorded pace but never a faster one', () {
      final out = RoadmapDraftEditor.retarget(
        const [
          RoadmapPhaseDraft(
            phase: DietPhase.cut,
            plannedWeeks: 10,
            weeklyRateKg: 0.3,
          ),
          RoadmapPhaseDraft(
            phase: DietPhase.cut,
            plannedWeeks: 10,
            weeklyRateKg: 2.0,
          ),
        ],
        startWeightKg: 80,
        goalTargetBfPercent: 12,
        maintenanceKcal: 2500,
        eligibility: unrestricted,
      );
      expect(out[0].weeklyRateKg, closeTo(0.3, 1e-9));
      expect(out[0].targetWeightKg, 77.0);
      expect(out[1].weeklyRateKg, lessThan(1.0));
    });

    test('retarget only moves the first phase for the weeks still ahead', () {
      final out = RoadmapDraftEditor.retarget(
        const [RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 14)],
        startWeightKg: 77,
        goalTargetBfPercent: 12,
        maintenanceKcal: 2500,
        eligibility: unrestricted,
        firstPhaseElapsedWeeks: 6,
      );
      // 8 weeks left at 0.5 kg/week.
      expect(out.single.targetWeightKg, 73.0);
      expect(out.single.plannedWeeks, 14);
    });

    test('add carries the previous end weight', () {
      final withTarget = [
        const RoadmapPhaseDraft(
          phase: DietPhase.cut,
          plannedWeeks: 10,
          targetWeightKg: 75,
        ),
      ];
      final added = RoadmapDraftEditor.add(
        withTarget,
        DietPhase.maintain,
        unrestricted,
      );
      expect(added.last.targetWeightKg, 75);
    });

    group('pinPhaseEnd', () {
      final cutThenHold = [
        const RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 14),
        const RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 2),
        const RoadmapPhaseDraft(phase: DietPhase.maingain, plannedWeeks: 20),
      ];

      List<RoadmapPhaseDraft>? pin(
        double end, {
        int index = 0,
        double from = 80,
        int elapsed = 0,
      }) => RoadmapDraftEditor.pinPhaseEnd(
        cutThenHold,
        index,
        fromWeightKg: from,
        endWeightKg: end,
        goalTargetBfPercent: 12,
        maintenanceKcal: 2500,
        eligibility: unrestricted,
        elapsedWeeks: elapsed,
      );

      test('lands the phase on the typed weight and re-chains the rest', () {
        final out = pin(74.3)!;
        expect(out[0].targetWeightKg, 74.3);
        // 5.7 kg at 0.5 kg/week -> 12 weeks at 0.475 kg/week.
        expect(out[0].plannedWeeks, 12);
        expect(out[0].weeklyRateKg, closeTo(0.475, 1e-9));
        expect(out[1].targetWeightKg, 74.3);
        expect(out[2].targetWeightKg, greaterThan(74.3));
      });

      test('survives a re-save from the same weight', () {
        final out = pin(74.3)!;
        final again = RoadmapDraftEditor.retarget(
          out,
          startWeightKg: 80,
          goalTargetBfPercent: 12,
          maintenanceKcal: 2500,
          eligibility: unrestricted,
        );
        expect(again.map((e) => e.targetWeightKg), [
          74.3,
          74.3,
          out[2].targetWeightKg,
        ]);
      });

      test('counts time already spent in the phase', () {
        final out = pin(74.0, from: 77, elapsed: 6)!;
        // 3 kg left = 6 weeks, plus the 6 already behind.
        expect(out[0].plannedWeeks, 12);
        final again = RoadmapDraftEditor.retarget(
          out,
          startWeightKg: 77,
          goalTargetBfPercent: 12,
          maintenanceKcal: 2500,
          eligibility: unrestricted,
          firstPhaseElapsedWeeks: 6,
        );
        expect(again[0].targetWeightKg, 74.0);
      });

      test('refuses what needs a different phase', () {
        expect(pin(85), isNull, reason: 'cut cannot end above the start');
        expect(pin(50), isNull, reason: 'would need more than 52 weeks');
        expect(pin(75, index: 1), isNull, reason: 'maintain holds weight');
      });
    });
  });
}
