import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/gamification/presentation/level_system_view.dart';
import 'package:herculex/features/gamification/presentation/training_level_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';

void main() {
  Future<void> pumpView(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.trainingLevel,
      routes: [
        GoRoute(
          path: AppRoutes.trainingLevel,
          builder: (_, _) => const TrainingLevelView(),
        ),
        GoRoute(
          path: AppRoutes.levelSystem,
          builder: (_, _) => const LevelSystemView(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          levelProgressProvider.overrideWith(
            (ref) => Stream.value(
              const LevelProgress(
                band: LevelBand.intermediate,
                xpInBand: 300,
                totalXp: 4200,
                completedWorkouts: 60,
              ),
            ),
          ),
          strengthAssessmentProvider.overrideWith(
            (ref) async => const StrengthAssessment(
              tier: LevelBand.intermediate,
              sex: BiologicalSex.male,
              bests: {
                StrengthLift.bench: LiftBest(
                  lift: StrengthLift.bench,
                  logged: 1.4,
                ),
                StrengthLift.squat: LiftBest(
                  lift: StrengthLift.squat,
                  logged: 1.3,
                ),
              },
            ),
          ),
          profileProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // HxScreenShell runs an ambient animation, so no pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('shows rank and strength blockers without XP numbers', (
    tester,
  ) async {
    await pumpView(tester);

    expect(find.text('Intermediate II'), findsOneWidget);
    expect(find.text('To reach Advanced'), findsOneWidget);
    expect(find.textContaining('Squat · 1.75× BW'), findsOneWidget);
    expect(find.text('Now 1.30× BW'), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
  });

  testWidgets('bottom button opens the explainer', (tester) async {
    await pumpView(tester);

    final button = find.text('How Herculex calculates levels');
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Band = strength'), findsOneWidget);
  });
}
