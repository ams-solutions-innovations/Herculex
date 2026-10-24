import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workout_report/application/workout_report_providers.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workout_report/presentation/report_context_sheet.dart';
import 'package:herculex/features/workout_report/presentation/workout_report_card.dart';

const report = WorkoutReport(
  completedSets: 21,
  plannedSets: 21,
  originalSets: 24,
  minutes: 62,
  muscleChanges: {'Triceps': -3},
  changes: ['Triceps: three optional sets removed'],
  findings: [
    ReportFinding(
      ruleId: 'PLAN-COMPLETE',
      title: 'Adjusted workout completed',
      detail:
          'All 21 working sets in the adjusted plan were completed. Your priority lifts stayed in place.',
      nextStep:
          'Review your next comparable session before restoring optional sets.',
      support: ReportSupport.recorded,
      tone: ReportTone.positive,
    ),
    ReportFinding(
      ruleId: 'PERFORMANCE-DOWN',
      title: 'Fewer repetitions this time',
      exerciseName: 'Bench press',
      detail: '8 versus 10 repetitions at comparable load and recorded effort.',
      nextStep:
          'One lower result is not a plateau. Recheck your next comparable session.',
      support: ReportSupport.recorded,
    ),
    ReportFinding(
      ruleId: 'CONTEXT-SLEEP',
      title: 'Shorter sleep is relevant context',
      detail:
          '5.8 hours were recorded before training. Sleep may have contributed; it does not prove the cause.',
      nextStep:
          'Protect the next night and compare your next equivalent exposure.',
      support: ReportSupport.possible,
    ),
  ],
);
void main() {
  testWidgets('report fits a narrow phone and opens detail without overflow', (
    tester,
  ) async {
    if (Platform.environment['HX_REPORT_PREVIEW'] == '1') {
      await tester.runAsync(() async {
        final font = FontLoader('Manrope')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/Manrope-Variable.ttf').readAsBytesSync(),
              ),
            ),
          );
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                ).readAsBytesSync(),
              ),
            ),
          );
        await icons.load();
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutReportProvider(1).overrideWith((ref) => Stream.value(report)),
        ],
        child: MaterialApp(
          theme: ThemeData(
            fontFamily: 'Manrope',
            brightness: Brightness.dark,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00CED1),
              brightness: Brightness.dark,
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      'Workout complete',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Upper body · 14 October'),
                    const SizedBox(height: 24),
                    const WorkoutReportCard(sessionId: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Training report'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (Platform.environment['HX_REPORT_PREVIEW'] == '1') {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final pixels = await boundary.toImage();
        final data = await pixels.toByteData(format: ui.ImageByteFormat.png);
        final out = File(
          '${Directory.systemTemp.path}/herculex-workout-report-preview.png',
        );
        out.writeAsBytesSync(data!.buffer.asUint8List());
        pixels.dispose();
      });
    }
    await tester.ensureVisible(find.text('View report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View report'));
    await tester.pumpAndSettle();
    expect(find.text('Your training report'), findsOneWidget);
    expect(find.text('Next time'), findsOneWidget);
    // The collapsed comparison sits below the fold of a phone-height sheet.
    await tester.drag(find.text('Your training report'), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan vs. what you did'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.text('Plan vs. what you did'),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Direct / primary muscle work'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('optional context distinguishes unknown from no', (tester) async {
    ReportContext? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showReportContextSheet(
                  context,
                  const ReportContext(),
                );
              },
              child: const Text('Context'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No').first);
    await tester.ensureVisible(find.text('Update report'));
    await tester.tap(find.text('Update report'));
    await tester.pumpAndSettle();
    expect(saved!.ateBefore, isFalse);
    expect(saved!.stressed, isNull);
    expect(saved!.pain, isNull);
  });
}
