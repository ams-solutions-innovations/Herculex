import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/profile/presentation/widgets/activity_level_section.dart';

const _captionCalibrating =
    "Your starting estimate. We'll refine it automatically as you log.";
const _captionCalibrated =
    'Manual reset. Use this only if your routine changed a lot. '
    'It reseeds the estimate and keeps your history.';
const _dialogTitle = 'Reset activity level?';
const _dialogBody =
    "This becomes your new starting point. It won't erase your "
    'calibration history.';
const _snackOther =
    "Saved. We'll use this as the starting point at the next recalibration.";
const _snackMeasured = 'Saved. Your estimate stays measured from your logs.';

TdeeEstimateResult _row(TdeeMethod method, {bool qualified = false}) =>
    TdeeEstimateResult(
      kcal: 2500,
      method: method,
      confidence: TdeeConfidence.medium,
      windowDays: 28,
      observedQualified: qualified,
      inputs: const {},
      estimatedAt: DateTime(2026, 9, 1, 8),
    );

void main() {
  late List<ActivityLevel> calls;
  late ActivityLevel selected;

  Future<void> pump(
    WidgetTester tester, {
    required Stream<TdeeEstimateResult?> stream,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    calls = [];
    selected = ActivityLevel.lightlyActive;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [latestTdeeEstimateProvider.overrideWith((ref) => stream)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => ActivityLevelSection(
                  selected: selected,
                  onChanged: (a) {
                    calls.add(a);
                    setState(() => selected = a);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpRow(WidgetTester tester, TdeeEstimateResult? row) =>
      pump(tester, stream: Stream.value(row));

  Future<void> tapTile(WidgetTester tester, ActivityLevel level) async {
    await tester.tap(find.text(level.label));
    await tester.pumpAndSettle();
  }

  group('calibrated (classifier)', () {
    testWidgets('different tile shows the confirm dialog, no save yet', (
      tester,
    ) async {
      await pumpRow(tester, _row(TdeeMethod.classifier));
      await tapTile(tester, ActivityLevel.active);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_dialogTitle), findsOneWidget);
      expect(find.text(_dialogBody), findsOneWidget);
      expect(find.text('Keep Current Level'), findsOneWidget);
      expect(find.text('Reset Activity Level'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('Keep Current Level leaves everything unchanged', (
      tester,
    ) async {
      await pumpRow(tester, _row(TdeeMethod.classifier));
      await tapTile(tester, ActivityLevel.active);
      await tester.tap(find.text('Keep Current Level'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, isEmpty);
      expect(selected, ActivityLevel.lightlyActive);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Reset Activity Level saves once and shows the D-14 snackbar', (
      tester,
    ) async {
      await pumpRow(tester, _row(TdeeMethod.classifier));
      await tapTile(tester, ActivityLevel.active);
      await tester.tap(find.text('Reset Activity Level'));
      await tester.pumpAndSettle();

      expect(calls, [ActivityLevel.active]);
      expect(selected, ActivityLevel.active);
      expect(find.text(_snackOther), findsOneWidget);
      expect(find.text(_snackMeasured), findsNothing);
    });

    testWidgets('scrim dismissal behaves like Keep Current Level', (
      tester,
    ) async {
      await pumpRow(tester, _row(TdeeMethod.classifier));
      await tapTile(tester, ActivityLevel.active);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, isEmpty);
      expect(selected, ActivityLevel.lightlyActive);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('shows the calibrated caption', (tester) async {
      await pumpRow(tester, _row(TdeeMethod.classifier));
      expect(find.text(_captionCalibrated), findsOneWidget);
      expect(find.text(_captionCalibrating), findsNothing);
    });
  });

  group('measured (observed, qualified)', () {
    testWidgets('reset shows the D-15 snackbar', (tester) async {
      await pumpRow(tester, _row(TdeeMethod.observed, qualified: true));
      await tapTile(tester, ActivityLevel.veryActive);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Reset Activity Level'));
      await tester.pumpAndSettle();

      expect(calls, [ActivityLevel.veryActive]);
      expect(find.text(_snackMeasured), findsOneWidget);
      expect(find.text(_snackOther), findsNothing);
    });

    testWidgets('shows the calibrated caption', (tester) async {
      await pumpRow(tester, _row(TdeeMethod.observed, qualified: true));
      expect(find.text(_captionCalibrated), findsOneWidget);
    });
  });

  group('aging (observed, held)', () {
    testWidgets('dialog appears and snackbar is the D-14 text', (tester) async {
      await pumpRow(tester, _row(TdeeMethod.observed));
      await tapTile(tester, ActivityLevel.active);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Reset Activity Level'));
      await tester.pumpAndSettle();

      expect(calls, [ActivityLevel.active]);
      expect(find.text(_snackOther), findsOneWidget);
      expect(find.text(_snackMeasured), findsNothing);
    });
  });

  group('calibrating', () {
    Future<void> expectSavesImmediately(WidgetTester tester) async {
      await tapTile(tester, ActivityLevel.active);
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, [ActivityLevel.active]);
      expect(selected, ActivityLevel.active);
      expect(find.text(_snackOther), findsOneWidget);
    }

    testWidgets('coldStart row saves with no dialog', (tester) async {
      await pumpRow(tester, _row(TdeeMethod.coldStart));
      expect(find.text(_captionCalibrating), findsOneWidget);
      await expectSavesImmediately(tester);
    });

    testWidgets('null emission saves with no dialog', (tester) async {
      await pumpRow(tester, null);
      expect(find.text(_captionCalibrating), findsOneWidget);
      await expectSavesImmediately(tester);
    });

    testWidgets('loading (never emits) is treated as calibrating', (
      tester,
    ) async {
      final controller = StreamController<TdeeEstimateResult?>();
      addTearDown(controller.close);
      await pump(tester, stream: controller.stream);
      expect(find.text(_captionCalibrating), findsOneWidget);
      await expectSavesImmediately(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('tapping the selected tile', () {
    final rows = <String, TdeeEstimateResult?>{
      'null': null,
      'coldStart': _row(TdeeMethod.coldStart),
      'classifier': _row(TdeeMethod.classifier),
      'observed': _row(TdeeMethod.observed, qualified: true),
    };
    for (final entry in rows.entries) {
      testWidgets('does nothing when ${entry.key}', (tester) async {
        await pumpRow(tester, entry.value);
        await tapTile(tester, ActivityLevel.lightlyActive);

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(calls, isEmpty);
      });
    }
  });
}
