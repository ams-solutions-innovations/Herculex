import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_tdee_actions.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/tdee_shift_calculator.dart';
import 'package:herculex/features/weekly_report/domain/tdee_target_proposal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

TdeeEstimateResult _est(
  int kcal, {
  TdeeMethod method = TdeeMethod.observed,
  TdeeConfidence confidence = TdeeConfidence.medium,
}) => TdeeEstimateResult(
  kcal: kcal,
  method: method,
  confidence: confidence,
  windowDays: 28,
  observedQualified: true,
  inputs: const {},
  estimatedAt: DateTime(2026, 10, 1),
);

void main() {
  group('TdeeShiftCalculator materiality', () {
    test('delta of exactly 100 at 2500 is not material (5% is 125)', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2600),
        before: _est(2500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 100);
    });

    test('2500 -> 2640 is material and carries the section fields', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2640, confidence: TdeeConfidence.high),
        before: _est(2500),
      )!;
      expect(s.oldKcal, 2500);
      expect(s.newKcal, 2640);
      expect(s.deltaKcal, 140);
      expect(s.material, isTrue);
      expect(s.confidence, 'high');
    });

    test('1500 -> 1610 is material (floor 100, 5% is 75)', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(1610),
        before: _est(1500),
      )!;
      expect(s.material, isTrue);
      expect(s.deltaKcal, 110);
    });

    test('1500 -> 1600 is not material: the boundary is strict', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(1600),
        before: _est(1500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 100);
    });

    test('a downward shift is signed and judged by magnitude', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2360),
        before: _est(2500),
      )!;
      expect(s.deltaKcal, -140);
      expect(s.material, isTrue);
    });

    test('a non-material shift still yields a section', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2510),
        before: _est(2500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 10);
    });
  });

  group('TdeeShiftCalculator no section', () {
    test('null without an earlier estimate', () {
      expect(
        TdeeShiftCalculator.compute(newest: _est(2600), before: null),
        isNull,
      );
    });

    test('null without a newest estimate', () {
      expect(
        TdeeShiftCalculator.compute(newest: null, before: _est(2600)),
        isNull,
      );
    });

    test('null when the newest estimate is a cold start', () {
      expect(
        TdeeShiftCalculator.compute(
          newest: _est(3000, method: TdeeMethod.coldStart),
          before: _est(2000),
        ),
        isNull,
      );
    });

    test('a cold-start earlier estimate is still a valid baseline', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2700),
        before: _est(2400, method: TdeeMethod.coldStart),
      );
      expect(s, isNotNull);
      expect(s!.material, isTrue);
    });
  });

  group('TdeeTargetProposalCalculator', () {
    const rule = TargetRule(
      kcal: 2400,
      proteinG: 180,
      carbsG: 250,
      fatG: 70,
      fiberG: 30,
      appliesTo: 'global',
    );

    TdeeTargetProposalResult run({
      TargetRule? r = rule,
      int oldKcal = 2500,
      int newKcal = 2640,
      int? floor,
      PhaseEligibility? eligibility,
    }) => TdeeTargetProposalCalculator.compute(
      rule: r,
      oldEstimateKcal: oldKcal,
      newEstimateKcal: newKcal,
      minCaloriesKcal: floor,
      eligibility: eligibility,
    );

    test('preserves the deliberate offset: +140 on 2400 -> 2540', () {
      final res = run();
      expect(res.status, TdeeProposalStatus.proposed);
      final p = res.proposal!;
      expect(p.kcal, 2540);
      expect(p.proteinG, 180);
      expect(p.fatG, 70);
      expect(p.carbsG, 298); // (2540 - 720 - 630) / 4 = 297.5 -> 298
      expect(p.appliesTo, 'global');
    });

    test('carries fiber and scope over from the rule', () {
      final p = run(
        r: const TargetRule(
          kcal: 2400,
          proteinG: 180,
          carbsG: 250,
          fatG: 70,
          fiberG: 30,
          appliesTo: 'training_day',
        ),
      ).proposal!;
      expect(p.fiberG, 30);
      expect(p.appliesTo, 'training_day');
    });

    test('a downward shift lowers the target: -140 -> 2260', () {
      final p = run(newKcal: 2360).proposal!;
      expect(p.kcal, 2260);
      expect(p.carbsG, round4(2260 - 720 - 630));
    });

    test('rounds to the nearest 10, halves up', () {
      expect(run(newKcal: 2643).proposal!.kcal, 2540);
      expect(run(newKcal: 2645).proposal!.kcal, 2550);
    });

    test('the minimum-calories floor wins over a lower proposal', () {
      final p = run(newKcal: 2360, floor: 2300).proposal!;
      expect(p.kcal, 2300);
    });

    test('a proposal clamped onto the current kcal is noChange', () {
      final res = run(
        r: const TargetRule(
          kcal: 2300,
          proteinG: 150,
          carbsG: 250,
          fatG: 70,
          appliesTo: 'global',
        ),
        newKcal: 2360,
        floor: 2300,
      );
      expect(res.status, TdeeProposalStatus.noChange);
      expect(res.proposal, isNull);
    });

    test('restricted eligibility without maingain blocks an increase', () {
      final res = run(
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain},
          reasons: {PhaseRestrictionReason.under18},
        ),
      );
      expect(res.status, TdeeProposalStatus.noChange);
      expect(res.proposal, isNull);
    });

    test('a maingain cap of 100 clamps +140 to +100', () {
      final res = run(
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain, DietPhase.maingain},
          maxMaingainDeltaKcal: 100,
        ),
      );
      expect(res.proposal!.kcal, 2500);
    });

    test('unrestricted and null eligibility never clamp an increase', () {
      expect(
        run(eligibility: const PhaseEligibility.unrestricted()).proposal!.kcal,
        2540,
      );
      expect(run().proposal!.kcal, 2540);
    });

    test('a decrease is never blocked by eligibility', () {
      final res = run(
        newKcal: 2360,
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain},
          maxMaingainDeltaKcal: 0,
        ),
      );
      expect(res.proposal!.kcal, 2260);
    });

    test('a zero shift is noChange', () {
      final res = run(newKcal: 2500);
      expect(res.status, TdeeProposalStatus.noChange);
    });

    test('no room left for carbs is belowMacroFloor', () {
      final res = run(
        r: const TargetRule(
          kcal: 1500,
          proteinG: 200,
          carbsG: 10,
          fatG: 80,
          appliesTo: 'global',
        ),
        newKcal: 2400,
        oldKcal: 2500,
      );
      // 1400 kcal < 200*4 + 80*9 = 1520
      expect(res.status, TdeeProposalStatus.belowMacroFloor);
      expect(res.proposal, isNull);
    });

    test('no saved rule is noSavedRule', () {
      final res = run(r: null);
      expect(res.status, TdeeProposalStatus.noSavedRule);
      expect(res.proposal, isNull);
    });

    test('a target outside the storable decision range is noChange', () {
      final res = run(
        r: const TargetRule(
          kcal: 5950,
          proteinG: 150,
          carbsG: 500,
          fatG: 100,
          appliesTo: 'global',
        ),
        oldKcal: 2500,
        newKcal: 2700,
      );
      expect(res.status, TdeeProposalStatus.noChange);
    });
  });

  group('TdeeDecisionActions', () {
    late AppDatabase db;
    late FakeClock clock;
    late NutritionRepository nutrition;
    late WeeklyReportRepository reports;
    late TdeeDecisionActions actions;
    late TdeeTargetProposalResult resolved;
    IsoWeek? dueWeek;
    final week = IsoWeek(2026, 40);

    const proposal = TdeeTargetProposal(
      kcal: 2540,
      proteinG: 180,
      carbsG: 298,
      fatG: 70,
      fiberG: 30,
      appliesTo: 'global',
    );

    Future<List<NutritionTargetData>> targets() =>
        db.select(db.nutritionTargets).get();

    Future<TdeeActionResult> update({
      IsoWeek? w,
      TdeeTargetProposal displayed = proposal,
    }) => actions.update(
      week: w ?? week,
      oldEstimateKcal: 2500,
      newEstimateKcal: 2640,
      displayed: displayed,
    );

    setUp(() async {
      db = await openTestDatabase();
      clock = FakeClock(DateTime(2026, 10, 1, 9));
      nutrition = NutritionRepository(db, OpenFoodFactsClient(), clock);
      reports = WeeklyReportRepository(db, clock);
      dueWeek = null;
      resolved = const TdeeTargetProposalResult(
        TdeeProposalStatus.proposed,
        proposal,
      );
      actions = TdeeDecisionActions(
        reports,
        nutrition,
        clock,
        () => dueWeek,
        (_, _) async => resolved,
        (_) async => 'Cut',
      );
      await nutrition.upsertTarget(
        label: 'Cut',
        appliesTo: 'global',
        kcal: 2400,
        proteinG: 180,
        carbsG: 250,
        fatG: 70,
      );
      await reports.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{}',
      );
    });

    tearDown(() => db.close());

    test('update writes the target and the decision together', () async {
      expect(await update(), TdeeActionResult.applied);
      final rows = await targets();
      expect(rows, hasLength(1));
      expect(rows.single.kcal, 2540);
      expect(rows.single.carbsG, 298);
      expect(rows.single.label, 'Cut');
      final record = await reports.forWeek(week);
      expect(record!.tdeeDecision, 'updated');
      expect(record.tdeeDecisionKcal, 2540);
    });

    test('a second update is refused and writes nothing', () async {
      await update();
      resolved = const TdeeTargetProposalResult(
        TdeeProposalStatus.proposed,
        TdeeTargetProposal(
          kcal: 2700,
          proteinG: 180,
          carbsG: 350,
          fatG: 70,
          appliesTo: 'global',
        ),
      );
      final r = await update(displayed: resolved.proposal!);
      expect(r, TdeeActionResult.alreadyDecided);
      expect((await targets()).single.kcal, 2540);
      expect((await reports.forWeek(week))!.tdeeDecisionKcal, 2540);
    });

    test('update after keep leaves targets alone', () async {
      await actions.keep(week: week, currentKcal: 2400);
      expect(await update(), TdeeActionResult.alreadyDecided);
      expect((await targets()).single.kcal, 2400);
    });

    test('a week without a report writes nothing', () async {
      dueWeek = IsoWeek(2026, 39);
      expect(
        await update(w: IsoWeek(2026, 39)),
        TdeeActionResult.alreadyDecided,
      );
      expect((await targets()).single.kcal, 2400);
    });

    test('a non-actionable week writes nothing (update and keep)', () async {
      await reports.insertSnapshot(
        week: IsoWeek(2026, 36),
        payloadVersion: 1,
        payloadJson: '{}',
      );
      expect(
        await update(w: IsoWeek(2026, 36)),
        TdeeActionResult.notActionable,
      );
      expect(
        await actions.keep(week: IsoWeek(2026, 36), currentKcal: 2400),
        TdeeActionResult.notActionable,
      );
      expect((await targets()).single.kcal, 2400);
      expect((await reports.forWeek(IsoWeek(2026, 36)))!.tdeeDecision, isNull);
    });

    test(
      'a changed proposal kcal or scope is stale, nothing written',
      () async {
        resolved = const TdeeTargetProposalResult(
          TdeeProposalStatus.proposed,
          TdeeTargetProposal(
            kcal: 2300,
            proteinG: 180,
            carbsG: 200,
            fatG: 70,
            appliesTo: 'global',
          ),
        );
        expect(await update(), TdeeActionResult.stale);
        resolved = const TdeeTargetProposalResult(
          TdeeProposalStatus.proposed,
          TdeeTargetProposal(
            kcal: 2540,
            proteinG: 180,
            carbsG: 298,
            fatG: 70,
            appliesTo: 'training',
          ),
        );
        expect(await update(), TdeeActionResult.stale);
        expect((await targets()).single.kcal, 2400);
        expect((await reports.forWeek(week))!.tdeeDecision, isNull);
      },
    );

    test('a non-proposed re-resolve is stale', () async {
      for (final status in [
        TdeeProposalStatus.noSavedRule,
        TdeeProposalStatus.noChange,
        TdeeProposalStatus.belowMacroFloor,
      ]) {
        resolved = TdeeTargetProposalResult(status);
        expect(await update(), TdeeActionResult.stale);
      }
      expect((await targets()).single.kcal, 2400);
    });

    test('the write uses the fresh macros, not the displayed ones', () async {
      resolved = const TdeeTargetProposalResult(
        TdeeProposalStatus.proposed,
        TdeeTargetProposal(
          kcal: 2540,
          proteinG: 190,
          carbsG: 280,
          fatG: 72,
          appliesTo: 'global',
        ),
      );
      expect(await update(), TdeeActionResult.applied);
      final row = (await targets()).single;
      expect(row.proteinG, 190);
      expect(row.carbsG, 280);
      expect(row.fatG, 72);
    });

    test('keep records kept and never touches targets', () async {
      final before = await targets();
      expect(
        await actions.keep(week: week, currentKcal: 2400),
        TdeeActionResult.applied,
      );
      final record = await reports.forWeek(week);
      expect(record!.tdeeDecision, 'kept');
      expect(record.tdeeDecisionKcal, 2400);
      final after = await targets();
      expect(after, hasLength(1));
      expect(after.single.kcal, before.single.kcal);
      expect(after.single.carbsG, before.single.carbsG);
    });

    test('keep with kcal outside 800..6000 is refused, no throw', () async {
      for (final kcal in const [799, 6001]) {
        expect(
          await actions.keep(week: week, currentKcal: kcal),
          TdeeActionResult.invalidInput,
        );
      }
      expect((await reports.forWeek(week))!.tdeeDecision, isNull);
    });

    test('an out-of-range proposal is refused before any write', () async {
      final r = await update(
        displayed: const TdeeTargetProposal(
          kcal: 9000,
          proteinG: 180,
          carbsG: 250,
          fatG: 70,
          appliesTo: 'global',
        ),
      );
      expect(r, TdeeActionResult.invalidInput);
      expect((await targets()).single.kcal, 2400);
    });
  });

  group('isActionableWeek', () {
    final now = DateTime(2026, 10, 1, 9); // ISO week 40

    test('the current week is actionable', () {
      expect(isActionableWeek(IsoWeek(2026, 40), now, null), isTrue);
    });

    test('the due week is actionable', () {
      expect(
        isActionableWeek(IsoWeek(2026, 39), now, IsoWeek(2026, 39)),
        isTrue,
      );
    });

    test('any other week is not', () {
      expect(
        isActionableWeek(IsoWeek(2026, 38), now, IsoWeek(2026, 39)),
        isFalse,
      );
      expect(isActionableWeek(IsoWeek(2026, 41), now, null), isFalse);
    });
  });

  group('tdeeTargetProposalProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    Future<void> build({int? floor}) async {
      SharedPreferences.setMockInitialValues({
        if (floor != null) 'min_targets_enabled': true,
        'min_targets_kcal': ?floor,
      });
      final prefs = await SharedPreferences.getInstance();
      db = await openTestDatabase();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 1, 9))),
          sharedPreferencesProvider.overrideWithValue(prefs),
          physiqueEditorEligibilityProvider.overrideWithValue(
            const PhaseEligibility.unrestricted(),
          ),
        ],
      );
    }

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> saveRule(int kcal) => container
        .read(nutritionRepositoryProvider)
        .upsertTarget(
          label: 'Plan',
          appliesTo: 'global',
          kcal: kcal,
          proteinG: 180,
          carbsG: 250,
          fatG: 70,
        );

    test('actions provider re-resolves against the current rule', () async {
      await build();
      await saveRule(2400);
      final week = IsoWeek(2026, 40);
      final reports = container.read(weeklyReportRepositoryProvider);
      await reports.insertSnapshot(
        week: week,
        payloadVersion: 1,
        payloadJson: '{}',
      );
      const displayed = TdeeTargetProposal(
        kcal: 2540,
        proteinG: 180,
        carbsG: 250,
        fatG: 70,
        appliesTo: 'global',
      );
      final actions = container.read(tdeeDecisionActionsProvider);
      // Prime the cache the way the card does, then change the rule.
      final sub = container.listen(
        tdeeTargetProposalProvider((2500, 2640)),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(tdeeTargetProposalProvider((2500, 2640)).future);
      await saveRule(2200);
      await pumpEventQueue();
      expect(
        await actions.update(
          week: week,
          oldEstimateKcal: 2500,
          newEstimateKcal: 2640,
          displayed: displayed,
        ),
        TdeeActionResult.stale,
      );
      expect((await reports.forWeek(week))!.tdeeDecision, isNull);
      // Back to a rule that yields the displayed kcal: applied.
      await saveRule(2400);
      await pumpEventQueue();
      expect(
        await actions.update(
          week: week,
          oldEstimateKcal: 2500,
          newEstimateKcal: 2640,
          displayed: displayed,
        ),
        TdeeActionResult.applied,
      );
      final rows = await db.select(db.nutritionTargets).get();
      expect(rows.single.kcal, 2540);
    });

    test('no saved rule -> noSavedRule', () async {
      await build();
      final res = await container.read(
        tdeeTargetProposalProvider((2500, 2640)).future,
      );
      expect(res.status, TdeeProposalStatus.noSavedRule);
    });

    test('saved rule -> delta-preserving proposal', () async {
      await build();
      await saveRule(2400);
      final res = await container.read(
        tdeeTargetProposalProvider((2500, 2640)).future,
      );
      expect(res.status, TdeeProposalStatus.proposed);
      expect(res.proposal!.kcal, 2540);
    });

    test('the minimum-calories floor from settings is applied', () async {
      await build(floor: 2300);
      await saveRule(2400);
      final res = await container.read(
        tdeeTargetProposalProvider((2500, 2360)).future,
      );
      expect(res.proposal!.kcal, 2300);
    });

    test('the saved label for the scope is found, with a fallback', () async {
      await build();
      await saveRule(2400);
      expect(
        await container.read(savedTargetLabelProvider('global').future),
        'Plan',
      );
      expect(
        await container.read(savedTargetLabelProvider('rest_day').future),
        'Target',
      );
    });
  });
}

int round4(int kcal) => (kcal / 4).round();
