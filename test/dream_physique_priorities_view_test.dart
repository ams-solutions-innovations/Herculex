import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/presentation/dream_physique_priorities_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders empty state when no active profile exists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          dreamPhysiqueSummaryProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MaterialApp(
          home: DreamPhysiquePrioritiesView(
            initialProfile: DreamPhysiqueProgrammingProfile(
              schemaVersion: 1,
              overallConfidence: 0.0,
              musclePriorities: [],
              uncertainties: [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dream Physique Priorities'), findsOneWidget);
    expect(find.text('No Dream Physique Priorities Set'), findsOneWidget);
    expect(find.text('Set Dream Physique Goal'), findsOneWidget);
  });

  testWidgets('renders profile and summary with long text without overflow', (
    tester,
  ) async {
    // Narrow phone viewport to test overflow resistance
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final summary = DreamPhysiqueAnalysisSummary(
      schemaVersion: 1,
      analyzedAt: DateTime.now(),
      targetAestheticStyle:
          'Heroic, dense superhero build with full pectorals and massive shoulders',
      timeframeRange: '16-24 weeks',
      currentEstimatedBf: 15.0,
      targetBfPercent: 12.0,
      weightChangeKg: 5.5,
      estimatedMonths: 5,
      currentPhotoCount: 2,
      targetPhotoCount: 2,
    );

    const profile = DreamPhysiqueProgrammingProfile(
      schemaVersion: 1,
      overallConfidence: 0.85,
      musclePriorities: [
        ProgrammingMusclePriority(
          muscleId: 'chest',
          priority: ProgrammingPriorityLevel.high,
          confidence: 0.90,
          rationale:
              'The dream physique features prominent, dense pectoral development compared to the baseline.',
          uncertainties: [],
        ),
        ProgrammingMusclePriority(
          muscleId: 'side_delts',
          priority: ProgrammingPriorityLevel.high,
          confidence: 0.86,
          rationale:
              'Creating the wide silhouette shown in the target image requires significantly greater lateral deltoid mass.',
          uncertainties: [],
        ),
      ],
      uncertainties: ['Photo angle might hide lower lat width'],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          dreamPhysiqueSummaryProvider.overrideWith(
            (ref) => Stream.value(summary),
          ),
        ],
        child: const MaterialApp(
          home: DreamPhysiquePrioritiesView(initialProfile: profile),
        ),
      ),
    );
    await tester.pump();

    // Ensure no overflow errors occurred
    expect(tester.takeException(), isNull);

    expect(find.text('Dream Physique Priorities'), findsOneWidget);
    expect(find.text('Prioritized Muscles'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('Side delts'), findsOneWidget);
    expect(find.text('AI confidence 85%'), findsOneWidget);
    expect(find.text('16-24 weeks'), findsOneWidget);
    expect(find.text('Set new goal'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
}
