import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/profile/presentation/widgets/dream_physique_nutrition_direction_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'keeps the recommendation optional and lets the user choose another direction',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final summary = DreamPhysiqueAnalysisSummary(
        schemaVersion: 1,
        analyzedAt: DateTime.utc(2026, 9, 11),
        targetAestheticStyle: 'Athletic',
        timeframeRange: '12 months',
        estimatedMonths: 12,
        targetBfPercent: 14,
        currentEstimatedBf: 17,
        weightChangeKg: -2,
        currentPhotoCount: 0,
        targetPhotoCount: 0,
      );
      const profile = Profile(
        goal: FitnessGoal.muscleGain,
        activityLevel: ActivityLevel.active,
        weightKg: 80,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            profileProvider.overrideWith((ref) => Stream.value(profile)),
            dreamPhysiqueSummaryProvider.overrideWith(
              (ref) => Stream.value(summary),
            ),
            activePhysiqueGoalProvider.overrideWith(
              (ref) => Stream.value(null),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DreamPhysiqueNutritionDirectionCard()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Optional next nutrition phase'), findsOneWidget);
      expect(find.text('Recomp'), findsWidgets);
      expect(find.textContaining('not medical advice'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nutrition-direction-maingain')));
      await tester.pump();
      expect(find.text('Your next nutrition phase'), findsOneWidget);
      expect(find.textContaining('You chose Maingain'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dismiss-nutrition-direction')));
      await tester.pump();
      expect(
        find.byKey(const Key('dream-physique-nutrition-direction-card')),
        findsNothing,
      );
    },
  );

  group('Set targets deep link coercion', () {
    final summary = DreamPhysiqueAnalysisSummary(
      schemaVersion: 1,
      analyzedAt: DateTime.utc(2026, 9, 11),
      targetAestheticStyle: 'Athletic',
      timeframeRange: '12 months',
      estimatedMonths: 12,
      targetBfPercent: 14,
      currentEstimatedBf: 17,
      weightChangeKg: -2,
      currentPhotoCount: 0,
      targetPhotoCount: 0,
    );
    final goal = PhysiqueGoalData(
      id: 9,
      status: 'active',
      source: 'ai_analysis',
      targetAestheticStyle: 'Athletic',
      timeframeRange: '',
      startedAt: DateTime(2026, 9, 1),
    );
    const lowConfidence = PhaseEligibility(
      allowedPhases: {DietPhase.maintain, DietPhase.maingain, DietPhase.recomp},
      reasons: {PhaseRestrictionReason.lowConfidence},
    );

    Future<Object?> pressSetTargets(
      WidgetTester tester, {
      required int? age,
      PhysiqueGoalData? activeGoal,
      PhaseEligibility? roadmap,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Object? extra;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: SingleChildScrollView(
                child: DreamPhysiqueNutritionDirectionCard(),
              ),
            ),
          ),
          GoRoute(
            path: '/nutrition-targets',
            builder: (_, state) {
              extra = state.extra;
              return const Scaffold(body: Text('Targets'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileProvider.overrideWith(
              (ref) => Stream.value(
                Profile(
                  goal: FitnessGoal.muscleGain,
                  activityLevel: ActivityLevel.active,
                  weightKg: 80,
                  ageYears: age,
                ),
              ),
            ),
            dreamPhysiqueSummaryProvider.overrideWith(
              (ref) => Stream.value(summary),
            ),
            activePhysiqueGoalProvider.overrideWith(
              (ref) => Stream.value(activeGoal),
            ),
            if (roadmap != null)
              physiqueRoadmapEligibilityProvider(9).overrideWithValue(roadmap),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('nutrition-direction-cut')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('open-nutrition-targets')));
      await tester.pumpAndSettle();
      return extra;
    }

    testWidgets('low confidence never presets Cut', (tester) async {
      final extra = await pressSetTargets(
        tester,
        age: 30,
        activeGoal: goal,
        roadmap: lowConfidence,
      );
      expect(extra, isNot(DietPhase.cut));
      expect(extra, DietPhase.recomp);
    });

    testWidgets('an allowed phase is passed unchanged', (tester) async {
      final extra = await pressSetTargets(
        tester,
        age: 30,
        activeGoal: goal,
        roadmap: const PhaseEligibility.unrestricted(),
      );
      expect(extra, DietPhase.cut);
    });

    testWidgets('no goal falls back to the age-only eligibility', (
      tester,
    ) async {
      final extra = await pressSetTargets(tester, age: 16);
      expect(extra, DietPhase.recomp);
    });
  });
}
