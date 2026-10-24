import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/labs/application/labs_providers.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:herculex/features/labs/presentation/labs_view.dart';

void main() {
  testWidgets(
    'opt-in screen uses existing theme and exposes granular consent',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const LabsView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set up my Labs'), findsOneWidget);
      await tester.tap(find.text('Set up my Labs'));
      await tester.pumpAndSettle();
      expect(find.text('Your Labs, your choice'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(9));
      expect(find.text('Include older records'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'enabled empty state is accessible in light theme with large text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final consent = LabsConsent(
        enabled: true,
        categories: {LabsCategory.sleep},
        since: DateTime(2026, 10, 16),
      );
      final snapshot = LabsSnapshot(
        period: LabsPeriod(DateTime(2026, 10), DateTime(2026, 11)),
        generatedAt: DateTime(2026, 10, 16),
        findings: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            labsConsentProvider.overrideWithValue(consent),
            labsSnapshotProvider(30).overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const LabsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What we found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
