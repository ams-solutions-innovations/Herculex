import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/labs/application/labs_providers.dart';
import 'package:herculex/features/labs/domain/labs_engine.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:herculex/features/labs/presentation/labs_view.dart';

void main() {
  testWidgets('mobile dashboard and detailed chart render in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final family in ['Manrope', 'SpaceGrotesk']) {
      await (FontLoader(family)..addFont(
            rootBundle.load(
              'assets/fonts/${family == 'Manrope' ? 'Manrope' : 'SpaceGrotesk'}-Variable.ttf',
            ),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final period = LabsPeriod(DateTime(2026, 10), DateTime(2026, 10, 31));
    final rows = [
      for (var i = 0; i < 30; i++)
        LabsObservation(
          id: '$i',
          category: LabsCategory.sleep,
          metric: 'sleep_hours',
          at: DateTime(2026, 10, 1 + i),
          value: 6.5 + (i % 5) * .3,
          unit: 'h',
          source: 'fixture',
        ),
    ];
    final snapshot = LabsSnapshot(
      period: period,
      generatedAt: DateTime(2026, 10, 30),
      findings: LabsEngine.analyze(rows, period, {LabsCategory.sleep}),
      events: [
        {'at': '2026-10-10T12:00:00.000', 'title': 'Earlier training'},
      ],
    );
    final consent = LabsConsent(
      enabled: true,
      categories: {LabsCategory.sleep},
      since: DateTime(2026, 10),
    );
    for (final dark in [true, false]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            labsConsentProvider.overrideWithValue(consent),
            labsSnapshotProvider(30).overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: child!,
              ),
            ),
            home: const LabsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _save(
        tester,
        key,
        'outputs/labs-${dark ? 'dark' : 'light'}-qa.png',
      );
      await tester.ensureVisible(find.text('Sleep duration').first);
      await tester.tap(find.text('Sleep duration').first);
      await tester.pumpAndSettle();
      // The plain-language conclusion and chart lead; the statistics open
      // on demand.
      await tester.ensureVisible(find.text('Numbers & method'));
      await tester.tap(find.text('Numbers & method'));
      await tester.pumpAndSettle();
      expect(find.text('How to read this'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _save(
        tester,
        key,
        'outputs/labs-${dark ? 'dark' : 'light'}-chart-qa.png',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}

Future<void> _save(WidgetTester tester, GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
