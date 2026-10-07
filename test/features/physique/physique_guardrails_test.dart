import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';

void main() {
  const safe = {DietPhase.maintain, DietPhase.recomp, DietPhase.maingain};

  group('ageEligibility', () {
    test('17 is restricted with maingain cap', () {
      final e = PhysiqueGuardrails.ageEligibility(17);
      expect(e.allowedPhases, safe);
      expect(e.maxMaingainDeltaKcal, 150);
      expect(e.reasons, {PhaseRestrictionReason.under18});
    });

    test('null age is restricted like a minor', () {
      final e = PhysiqueGuardrails.ageEligibility(null);
      expect(e.allowedPhases, safe);
      expect(e.maxMaingainDeltaKcal, 150);
      expect(e.reasons, {PhaseRestrictionReason.ageMissing});
    });

    test('18 and 40 are unrestricted', () {
      for (final age in [18, 40]) {
        final e = PhysiqueGuardrails.ageEligibility(age);
        expect(e.allowedPhases, DietPhase.values.toSet());
        expect(e.maxMaingainDeltaKcal, isNull);
        expect(e.reasons, isEmpty);
        expect(e.isRestricted, isFalse);
      }
    });
  });

  group('confidence', () {
    test('label handling', () {
      expect(
        PhysiqueGuardrails.isLowConfidence(
          confidence: AssessmentConfidence.low,
        ),
        isTrue,
      );
      for (final c in [
        AssessmentConfidence.medium,
        AssessmentConfidence.high,
        AssessmentConfidence.unknown,
      ]) {
        expect(PhysiqueGuardrails.isLowConfidence(confidence: c), isFalse);
      }
    });

    test('band width', () {
      expect(
        PhysiqueGuardrails.isLowConfidence(bfRangeMin: 14, bfRangeMax: 20.5),
        isTrue,
      );
      expect(
        PhysiqueGuardrails.isLowConfidence(bfRangeMin: 14, bfRangeMax: 20),
        isFalse,
      );
      expect(PhysiqueGuardrails.isLowConfidence(), isFalse);
    });

    test('confidenceEligibility(low) is maintain/recomp only', () {
      final e = PhysiqueGuardrails.confidenceEligibility(
        confidence: AssessmentConfidence.low,
      );
      expect(e.allowedPhases, {DietPhase.maintain, DietPhase.recomp});
      expect(e.reasons, {PhaseRestrictionReason.lowConfidence});
    });

    test('fromWire', () {
      expect(AssessmentConfidence.fromWire('low'), AssessmentConfidence.low);
      expect(
        AssessmentConfidence.fromWire('bogus'),
        AssessmentConfidence.unknown,
      );
      expect(AssessmentConfidence.fromWire(null), AssessmentConfidence.unknown);
      expect(AssessmentConfidence.high.wireValue, 'high');
    });
  });

  test('evaluate intersects age and confidence', () {
    final e = PhysiqueGuardrails.evaluate(
      ageYears: 17,
      confidence: AssessmentConfidence.low,
    );
    expect(e.allowedPhases, {DietPhase.maintain, DietPhase.recomp});
    expect(e.reasons, {
      PhaseRestrictionReason.under18,
      PhaseRestrictionReason.lowConfidence,
    });
    expect(e.maxMaingainDeltaKcal, 150);
  });

  group('PhaseEligibility', () {
    final minor = PhysiqueGuardrails.ageEligibility(17);

    test('clampDelta', () {
      expect(minor.clampDelta(DietPhase.cut, -500), 0);
      expect(minor.clampDelta(DietPhase.bulk, 400), 0);
      expect(minor.clampDelta(DietPhase.maingain, 250), 150);
      expect(minor.clampDelta(DietPhase.maingain, 75), 75);
      expect(minor.clampDelta(DietPhase.maintain, 0), 0);
      const open = PhaseEligibility.unrestricted();
      expect(open.clampDelta(DietPhase.cut, -500), -500);
    });

    test('coerce', () {
      expect(minor.coerce(DietPhase.cut), DietPhase.recomp);
      expect(minor.coerce(DietPhase.bulk), DietPhase.maingain);
      expect(minor.coerce(DietPhase.recomp), DietPhase.recomp);
      const low = PhaseEligibility(
        allowedPhases: {DietPhase.maintain, DietPhase.recomp},
      );
      expect(low.coerce(DietPhase.bulk), DietPhase.recomp);
      expect(low.coerce(DietPhase.maingain), DietPhase.recomp);
      const onlyMaintain = PhaseEligibility(
        allowedPhases: {DietPhase.maintain},
      );
      expect(onlyMaintain.coerce(DietPhase.cut), DietPhase.maintain);
    });
  });

  group('DietPhaseCalculator.apply with eligibility', () {
    test('cut is neutralised for a minor', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2500,
        calorieDeltaOverride: -500,
        eligibility: PhysiqueGuardrails.ageEligibility(17),
      );
      expect(t.deltaKcal, 0);
      expect(t.kcal, 2500);
    });

    test('maingain is capped for a minor', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.maingain,
        baselineKcal: 2500,
        calorieDeltaOverride: 250,
        eligibility: PhysiqueGuardrails.ageEligibility(17),
      );
      expect(t.deltaKcal, 150);
    });
  });
}
