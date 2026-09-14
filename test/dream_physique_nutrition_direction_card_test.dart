import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
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
}
