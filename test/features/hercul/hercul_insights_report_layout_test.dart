import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/hercul/application/hercul_providers.dart';
import 'package:herculex/features/hercul/domain/hercul_assessment.dart';
import 'package:herculex/features/hercul/domain/hercul_context.dart';
import 'package:herculex/features/hercul/domain/hercul_rule.dart';
import 'package:herculex/features/hercul/presentation/views/hercul_insights_report_view.dart';
import 'package:herculex/features/labs/application/labs_providers.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';

// Regression: on a phone-width screen the factor card header squeezed
// "Creatine Intake" into a few characters per line, because the long value
// label ("4/7 days (Loading / Saturating)") shared the title's row.
void main() {
  testWidgets('factor titles stay on one line at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final herculContext = HerculContext(
      scalars: {
        HerculSignals.creatineDays7d: 4,
        HerculSignals.creatineTakenYesterday: 1,
        HerculSignals.creatineLoadingPhase: 1,
      },
      now: DateTime(2026, 10, 16, 9),
    );
    final report = HerculInsightsReport.build(
      context: herculContext,
      messages: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          labsConsentProvider.overrideWithValue(const LabsConsent()),
          profileProvider.overrideWith((ref) => Stream.value(null)),
          herculInsightsReportProvider.overrideWith((ref) async => report),
          herculRulesProvider.overrideWith((ref) async => const <HerculRule>[]),
          herculContextProvider.overrideWith((ref) async => herculContext),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const HerculInsightsReportView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Creatine Intake'), findsNothing);
    await tester.tap(find.byKey(const Key('hercul-insights-details')));
    await tester.pumpAndSettle();
    final title = find.text('Creatine Intake');
    expect(title, findsOneWidget);
    expect(find.text('4/7 days (Loading / Saturating)'), findsOneWidget);

    // The test font is far wider than the real one, so the title may wrap
    // once; what must not happen is the title getting a sliver of the row.
    final card = find.ancestor(of: title, matching: find.byType(Row)).first;
    expect(
      tester.getSize(title).width,
      greaterThan(tester.getSize(card).width * 0.5),
    );
    expect(tester.takeException(), isNull);
  });
}
