import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/presentation/widgets/dream_physique_summary_card.dart';

PhysiqueGoalData _goal() => PhysiqueGoalData(
  id: 3,
  status: 'active',
  source: 'ai_analysis',
  targetAestheticStyle: 'Athletic',
  timeframeRange: '',
  targetBfPercent: 12,
  startedAt: DateTime(2026, 9, 1),
);

void main() {
  final summary = DreamPhysiqueAnalysisSummary(
    schemaVersion: 1,
    analyzedAt: DateTime.utc(2026, 9, 11),
    targetAestheticStyle: 'Athletic classic physique',
    timeframeRange: '12–18 months',
    estimatedMonths: 15,
    targetBfPercent: 12,
    currentEstimatedBf: 19,
    weightChangeKg: -4.5,
    currentPhotoCount: 2,
    targetPhotoCount: 1,
  );

  Widget app({
    DreamPhysiqueAnalysisSummary? withSummary,
    PhysiqueGoalData? goal,
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: DreamPhysiqueSummaryCard()),
        ),
        GoRoute(
          path: '/dream-physique',
          builder: (_, _) => const Scaffold(body: Text('Analysis route')),
        ),
        GoRoute(
          path: '/dream-physique/progress',
          builder: (_, _) => const Scaffold(body: Text('Progress route')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        dreamPhysiqueSummaryProvider.overrideWith(
          (ref) => Stream.value(withSummary),
        ),
        activePhysiqueGoalProvider.overrideWith((ref) => Stream.value(goal)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('shows only the name, estimated time and body fat', (
    tester,
  ) async {
    await tester.pumpWidget(app(withSummary: summary));
    await tester.pump();

    expect(find.text('Dream Physique'), findsOneWidget);
    expect(find.text('Estimated 15 months · target 12% BF'), findsOneWidget);
    expect(find.textContaining('Athletic classic physique'), findsNothing);
    expect(find.text('New analysis'), findsNothing);
    expect(find.text('View progress'), findsNothing);
  });

  testWidgets('without a goal the card opens the analysis screen', (
    tester,
  ) async {
    await tester.pumpWidget(app(withSummary: summary));
    await tester.pump();

    await tester.tap(find.byKey(const Key('dream-physique-summary-card')));
    await tester.pumpAndSettle();
    expect(find.text('Analysis route'), findsOneWidget);
  });

  testWidgets('with a goal the body opens the progress route', (tester) async {
    await tester.pumpWidget(app(withSummary: summary, goal: _goal()));
    await tester.pump();

    expect(find.text('New analysis'), findsNothing);

    await tester.tap(find.byKey(const Key('dream-physique-summary-card')));
    await tester.pumpAndSettle();
    expect(find.text('Progress route'), findsOneWidget);
  });

  testWidgets('a photos-only goal with no analysis shows imported photos', (
    tester,
  ) async {
    await tester.pumpWidget(app(goal: _goal()));
    await tester.pump();

    expect(find.text('Dream Physique'), findsOneWidget);
  });
}
