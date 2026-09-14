import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/presentation/widgets/dream_physique_summary_card.dart';

void main() {
  testWidgets('shows the saved target and a clear new-analysis affordance', (
    tester,
  ) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dreamPhysiqueSummaryProvider.overrideWith(
            (ref) => Stream.value(summary),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DreamPhysiqueSummaryCard()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dream Physique saved'), findsOneWidget);
    expect(find.textContaining('Athletic classic physique'), findsOneWidget);
    expect(find.text('Estimated 15 months · target 12% BF'), findsOneWidget);
    expect(find.text('Tap to start a new analysis.'), findsOneWidget);
  });
}
