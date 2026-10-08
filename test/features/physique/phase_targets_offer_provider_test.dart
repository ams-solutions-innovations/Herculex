import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/phase_targets_offer_provider.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

// 80 kg, no height or sex: no maintenance seed, so the planner uses its
// default 2500 kcal.
Profile _profile({int age = 30}) => Profile(
  goal: FitnessGoal.weightLoss,
  activityLevel: ActivityLevel.active,
  ageYears: age,
  weightKg: 80,
);

const _cut = RoadmapPhaseDraft(
  phase: DietPhase.cut,
  plannedWeeks: 12,
  targetWeightKg: 74,
  weeklyRateKg: 0.5,
);
const _hold = RoadmapPhaseDraft(
  phase: DietPhase.maintain,
  plannedWeeks: 2,
  targetWeightKg: 74,
  weeklyRateKg: 0,
);
const _build = RoadmapPhaseDraft(
  phase: DietPhase.maingain,
  plannedWeeks: 38,
  targetWeightKg: 78.2,
  weeklyRateKg: 0.11,
);

void main() {
  group('nearestPace', () {
    test('picks the preset closest to the roadmap rate', () {
      expect(nearestPace(DietPhase.cut, 0.5).weeklyKg, 0.5);
      expect(nearestPace(DietPhase.cut, 0.6).weeklyKg, 0.5);
      expect(nearestPace(DietPhase.cut, 0.7).weeklyKg, 0.75);
      expect(nearestPace(DietPhase.maingain, 0.11).weeklyKg, 0.15);
      expect(nearestPace(DietPhase.bulk, 0.25).kcalDelta, 250);
    });

    test('no rate means the standard preset; single-preset phases keep it', () {
      expect(nearestPace(DietPhase.cut, null).kcalDelta, -500);
      expect(nearestPace(DietPhase.maintain, 0.3).kcalDelta, 0);
      expect(nearestPace(DietPhase.recomp, null).kcalDelta, 0);
    });
  });

  group('phaseTargetsOfferProvider', () {
    late AppDatabase db;
    late FakeClock clock;
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = await openTestDatabase();
      clock = FakeClock(DateTime(2026, 10, 1, 9));
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
        ],
      );
      container.listen(profileProvider, (_, _) {});
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> settle() => pumpEventQueue();

    Future<void> saveProfile([Profile? profile]) async {
      await container
          .read(localProfileRepositoryProvider)
          .save(profile ?? _profile(), syncToLog: false);
      await settle();
    }

    Future<int> startGoal({bool accept = true}) async {
      const roadmap = [_cut, _hold, _build];
      final id = await container
          .read(physiqueGoalRepositoryProvider)
          .startGoal(
            StartGoalInput(
              estimatedMonths: 12,
              targetBfPercent: 12,
              startWeightKg: 80,
              analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 1))],
              roadmap: roadmap,
            ),
          );
      if (accept) {
        await container
            .read(physiqueRoadmapRepositoryProvider)
            .replaceRoadmap(id, roadmap, accept: true);
      }
      // The provider reads these streams; keep them subscribed.
      container.listen(physiqueGoalProvider(id), (_, _) {});
      container.listen(physiqueRoadmapPhasesProvider(id), (_, _) {});
      container.listen(physiqueLatestAnalysisProvider(id), (_, _) {});
      await settle();
      return id;
    }

    PhaseTargetsOffer? offer(int id) =>
        container.read(phaseTargetsOfferProvider(id));

    Future<void> setPlan(DietPhase phase) => container
        .read(activeDietPlanProvider.notifier)
        .setPlan(phase: phase, weeklyRateKg: 0, kcalDelta: 0, paceLabel: 'x');

    test('offers the running phase when no plan was ever set', () async {
      await saveProfile();
      final id = await startGoal();
      final o = offer(id)!;
      expect(o.phase, DietPhase.cut);
      expect(o.pace.weeklyKg, 0.5);
      expect(o.targets.kcal, 2000);
      expect(o.targets.proteinG, 176);
      expect(o.currentPlan, isNull, reason: 'the default cut is not a choice');
    });

    test('names the phase the calories are set for', () async {
      await saveProfile();
      final id = await startGoal();
      await setPlan(DietPhase.maintain);
      expect(offer(id)!.currentPlan, DietPhase.maintain);
      expect(offer(id)!.phase, DietPhase.cut);
    });

    test('nothing to offer once the plan matches the phase', () async {
      await saveProfile();
      final id = await startGoal();
      await setPlan(DietPhase.cut);
      expect(offer(id), isNull);
    });

    test(
      'Not now hides this phase only; the next one is offered again',
      () async {
        await saveProfile();
        final id = await startGoal();
        await container
            .read(phaseTargetsOfferDismissalsProvider.notifier)
            .dismiss(id, DietPhase.cut);
        expect(offer(id), isNull);
        expect(prefs.getStringList('physique_targets_offer_dismissed'), [
          '$id:cut',
        ]);

        await container
            .read(physiqueRoadmapRepositoryProvider)
            .advancePhase(id);
        await settle();
        expect(offer(id)!.phase, DietPhase.maintain);
      },
    );

    test('nothing before the roadmap is accepted', () async {
      await saveProfile();
      final id = await startGoal(accept: false);
      expect(offer(id), isNull);
    });

    test('nothing for an archived goal', () async {
      await saveProfile();
      final id = await startGoal();
      await container.read(physiqueGoalRepositoryProvider).archiveGoal(id);
      await settle();
      expect(offer(id), isNull);
    });

    test(
      'a member under 18 is offered the phase the guardrails allow',
      () async {
        await saveProfile(_profile(age: 16));
        final id = await startGoal();
        final o = offer(id)!;
        expect(o.phase, DietPhase.recomp);
        expect(o.targets.kcal, 2500, reason: 'no deficit');
      },
    );
  });
}
