import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/goal_target_provider.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

// 80 kg, no height or sex: no maintenance seed, so the planner uses its
// default 2500 kcal and a cut paces at exactly 0.5 kg/week.
const _profile = Profile(
  goal: FitnessGoal.weightLoss,
  activityLevel: ActivityLevel.active,
  ageYears: 30,
  weightKg: 80,
);

const _cut = RoadmapPhaseDraft(
  phase: DietPhase.cut,
  plannedWeeks: 12,
  targetWeightKg: 74,
  targetBfPercent: 12,
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
    // Providers are lazy: keep the ones under test alive and fed.
    container.listen(goalTargetProvider, (_, _) {});
    container.listen(profileProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle() => pumpEventQueue();

  Future<void> saveProfile([Profile profile = _profile]) async {
    await container
        .read(localProfileRepositoryProvider)
        .save(profile, syncToLog: false);
    await settle();
  }

  Future<int> startGoal({
    List<RoadmapPhaseDraft> roadmap = const [_cut, _hold, _build],
    bool accept = true,
  }) async {
    final id = await container
        .read(physiqueGoalRepositoryProvider)
        .startGoal(
          StartGoalInput(
            estimatedMonths: 12,
            targetBfPercent: 12,
            startWeightKg: 80,
            analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 30))],
            roadmap: roadmap,
          ),
        );
    if (accept) {
      await container
          .read(physiqueRoadmapRepositoryProvider)
          .replaceRoadmap(id, roadmap, accept: true);
    }
    await settle();
    return id;
  }

  Future<List<PhysiqueRoadmapPhaseData>> rows(int goalId) => container
      .read(physiqueRoadmapRepositoryProvider)
      .watchPhases(goalId)
      .first;

  group('goalTargetProvider', () {
    test('is empty with nothing set', () async {
      await settle();
      final t = container.read(goalTargetProvider);
      expect(t.source, GoalTargetSource.none);
      expect(t.targetKg, isNull);
    });

    test(
      'falls back to the typed profile weight, then the goals value',
      () async {
        await container.read(goalWeightProvider.notifier).set(72);
        await saveProfile();
        expect(container.read(goalTargetProvider).targetKg, 72);
        expect(
          container.read(goalTargetProvider).source,
          GoalTargetSource.manual,
        );

        await saveProfile(_profile.copyWith(targetWeightKg: 75));
        expect(container.read(goalTargetProvider).targetKg, 75);
      },
    );

    test(
      'follows the roadmap, not the typed weight, once one exists',
      () async {
        await saveProfile(_profile.copyWith(targetWeightKg: 70));
        final id = await startGoal();
        final t = container.read(goalTargetProvider);
        expect(t.source, GoalTargetSource.roadmap);
        expect(t.targetKg, 74);
        expect(t.dreamKg, 78.2);
        expect(t.phase, DietPhase.cut);
        expect(t.goalId, id);
      },
    );

    test('moves on when the next phase starts', () async {
      final id = await startGoal();
      final roadmap = container.read(physiqueRoadmapRepositoryProvider);
      await roadmap.advancePhase(id);
      await settle();
      expect(container.read(goalTargetProvider).phase, DietPhase.maintain);
      await roadmap.advancePhase(id);
      await settle();
      final t = container.read(goalTargetProvider);
      expect(t.phase, DietPhase.maingain);
      expect(t.targetKg, 78.2);
    });

    test(
      'a proposal that is not accepted yet already names its target',
      () async {
        await startGoal(accept: false);
        expect(container.read(goalTargetProvider).targetKg, 74);
      },
    );

    test('a phase without a weight takes its neighbour\'s', () async {
      await startGoal(
        roadmap: const [
          RoadmapPhaseDraft(phase: DietPhase.recomp, plannedWeeks: 8),
          _build,
        ],
      );
      expect(container.read(goalTargetProvider).targetKg, 78.2);
    });

    test('goes back to the typed weight when the goal is archived', () async {
      await saveProfile(_profile.copyWith(targetWeightKg: 70));
      final id = await startGoal();
      expect(container.read(goalTargetProvider).targetKg, 74);
      await container.read(physiqueGoalRepositoryProvider).archiveGoal(id);
      await settle();
      expect(container.read(goalTargetProvider).targetKg, 70);
    });
  });

  group('GoalTargetController', () {
    GoalTargetController controller() =>
        container.read(goalTargetControllerProvider);

    test('without a goal it stores the weight where it always did', () async {
      await saveProfile();
      final r = await controller().setTarget(76);
      await settle();
      expect((r as GoalTargetApplied).viaRoadmap, isFalse);
      expect(prefs.getDouble('goals_goal_kg'), 76);
      expect(container.read(goalTargetProvider).targetKg, 76);
      expect(
        container
            .read(localProfileRepositoryProvider)
            .currentProfile!
            .targetWeightKg,
        76,
      );
    });

    test('clearing removes the weight from both stores', () async {
      await saveProfile(_profile.copyWith(targetWeightKg: 76));
      await container.read(goalWeightProvider.notifier).set(76);
      await controller().clearManual();
      await settle();
      expect(prefs.getDouble('goals_goal_kg'), isNull);
      expect(container.read(goalTargetProvider).targetKg, isNull);
    });

    test('with a roadmap it moves the running phase and re-chains', () async {
      await saveProfile();
      final id = await startGoal();
      final r = await controller().setTarget(75);
      await settle();
      expect((r as GoalTargetApplied).viaRoadmap, isTrue);

      final phases = await rows(id);
      expect(phases[0].phaseType, 'cut');
      expect(phases[0].targetWeightKg, 75);
      expect(phases[0].plannedWeeks, 10);
      expect(phases[0].weeklyRateKg, closeTo(0.5, 1e-9));
      expect(phases[0].status, 'current');
      expect(phases[1].targetWeightKg, 75);
      expect(phases[2].targetWeightKg, greaterThan(75));
      expect(container.read(goalTargetProvider).targetKg, 75);
    });

    test(
      'the typed profile weight is left alone while a roadmap runs',
      () async {
        await saveProfile(_profile.copyWith(targetWeightKg: 70));
        await startGoal();
        await controller().setTarget(75);
        await settle();
        expect(
          container
              .read(localProfileRepositoryProvider)
              .currentProfile!
              .targetWeightKg,
          70,
        );
      },
    );

    test('the same weight again writes nothing', () async {
      await saveProfile();
      final id = await startGoal();
      final before = await rows(id);
      final r = await controller().setTarget(74);
      expect(r, isA<GoalTargetApplied>());
      final after = await rows(id);
      expect(after.map((e) => e.updatedAt), before.map((e) => e.updatedAt));
      expect(after.map((e) => e.id), before.map((e) => e.id));
    });

    test('keeps finished phases and the running phase\'s start', () async {
      await saveProfile();
      final id = await startGoal();
      final roadmap = container.read(physiqueRoadmapRepositoryProvider);
      await roadmap.advancePhase(id); // cut done, maintain current
      clock.advance(const Duration(days: 8));
      final startedAt = (await rows(id))[1].startedAt;

      // Maintain holds weight: a different weight needs a different phase.
      final held = await controller().setTarget(70);
      expect(held, isA<GoalTargetNeedsRoadmapChange>());
      expect(
        (held as GoalTargetNeedsRoadmapChange).message,
        contains('keeps your weight steady'),
      );
      final phases = await rows(id);
      expect(phases.map((p) => p.status), ['done', 'current', 'upcoming']);
      expect(phases[1].startedAt, startedAt);
    });

    test('refuses a weight on the wrong side of a cut', () async {
      await saveProfile();
      final id = await startGoal();
      final before = await rows(id);
      final r = await controller().setTarget(85);
      expect(r, isA<GoalTargetNeedsRoadmapChange>());
      expect((r as GoalTargetNeedsRoadmapChange).goalId, id);
      expect(r.message, contains('cut ends lower'));
      final after = await rows(id);
      expect(
        after.map((p) => p.targetWeightKg),
        before.map((p) => p.targetWeightKg),
      );
    });

    test('refuses a move that would take more than a year', () async {
      await saveProfile();
      await startGoal();
      final r = await controller().setTarget(40);
      expect(r, isA<GoalTargetNeedsRoadmapChange>());
      expect((r as GoalTargetNeedsRoadmapChange).message, contains('year'));
    });

    test('asks for a current weight first when there is none', () async {
      await startGoal();
      final r = await controller().setTarget(75);
      expect(r, isA<GoalTargetNeedsRoadmapChange>());
      expect(
        (r as GoalTargetNeedsRoadmapChange).message,
        contains('current weight'),
      );
    });
  });
}
