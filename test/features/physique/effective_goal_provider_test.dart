import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/effective_goal_provider.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

Profile _profile({FitnessGoal goal = FitnessGoal.maintenance, int age = 30}) =>
    Profile(
      goal: goal,
      activityLevel: ActivityLevel.active,
      ageYears: age,
      weightKg: 80,
      heightCm: 180,
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
  group('fitnessGoalForPhase', () {
    test('a phase stands for the direction it moves the weight', () {
      expect(fitnessGoalForPhase(DietPhase.cut), FitnessGoal.weightLoss);
      expect(fitnessGoalForPhase(DietPhase.bulk), FitnessGoal.muscleGain);
      expect(fitnessGoalForPhase(DietPhase.maingain), FitnessGoal.muscleGain);
      expect(fitnessGoalForPhase(DietPhase.maintain), FitnessGoal.maintenance);
      expect(fitnessGoalForPhase(DietPhase.recomp), FitnessGoal.maintenance);
    });
  });

  group('effectiveFitnessGoalProvider', () {
    late AppDatabase db;
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = await openTestDatabase();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 1, 9))),
        ],
      );
      container.listen(profileProvider, (_, _) {});
      container.listen(activePhysiqueGoalProvider, (_, _) {});
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> settle() => pumpEventQueue();

    Future<void> saveProfile(Profile profile) async {
      await container
          .read(localProfileRepositoryProvider)
          .save(profile, syncToLog: false);
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
      container.listen(physiqueRoadmapPhasesProvider(id), (_, _) {});
      container.listen(physiqueLatestAnalysisProvider(id), (_, _) {});
      await settle();
      return id;
    }

    FitnessGoal? effective() => container.read(effectiveFitnessGoalProvider);

    test('is the onboarding goal while there is no roadmap', () async {
      await saveProfile(_profile(goal: FitnessGoal.muscleGain));
      expect(effective(), FitnessGoal.muscleGain);
    });

    test('is null without a profile and without a roadmap', () async {
      await settle();
      expect(effective(), isNull);
    });

    test('follows the running phase of an accepted roadmap', () async {
      await saveProfile(_profile());
      await startGoal();
      expect(
        effective(),
        FitnessGoal.weightLoss,
        reason: 'the first phase is a cut',
      );
    });

    test('leaves the stored goal alone', () async {
      await saveProfile(_profile(goal: FitnessGoal.muscleGain));
      await startGoal();
      expect(effective(), FitnessGoal.weightLoss);
      expect(
        container.read(profileProvider).value!.goal,
        FitnessGoal.muscleGain,
      );
    });

    test('moves on with the roadmap', () async {
      await saveProfile(_profile(goal: FitnessGoal.weightLoss));
      final id = await startGoal();
      await container.read(physiqueRoadmapRepositoryProvider).advancePhase(id);
      await settle();
      expect(effective(), FitnessGoal.maintenance, reason: 'the hold phase');

      await container.read(physiqueRoadmapRepositoryProvider).advancePhase(id);
      await settle();
      expect(effective(), FitnessGoal.muscleGain, reason: 'the lean bulk');
    });

    test('a roadmap the member has not accepted changes nothing', () async {
      await saveProfile(_profile(goal: FitnessGoal.maintenance));
      await startGoal(accept: false);
      expect(effective(), FitnessGoal.maintenance);
    });

    test('an archived goal gives the stored goal back', () async {
      await saveProfile(_profile(goal: FitnessGoal.maintenance));
      final id = await startGoal();
      expect(effective(), FitnessGoal.weightLoss);
      await container.read(physiqueGoalRepositoryProvider).archiveGoal(id);
      await settle();
      expect(effective(), FitnessGoal.maintenance);
    });

    test('a member under 18 never reads as cutting', () async {
      await saveProfile(_profile(goal: FitnessGoal.weightLoss, age: 16));
      await startGoal();
      expect(
        effective(),
        FitnessGoal.maintenance,
        reason: 'recomp, no deficit',
      );
    });

    test(
      'baseline calories follow the phase, not the onboarding goal',
      () async {
        await saveProfile(_profile(goal: FitnessGoal.maintenance));
        final before = container.read(baselineTargetsProvider)!.kcal;
        await startGoal();
        final during = container.read(baselineTargetsProvider)!.kcal;
        expect(during, before - 500, reason: 'a cut baseline');
      },
    );
  });
}
