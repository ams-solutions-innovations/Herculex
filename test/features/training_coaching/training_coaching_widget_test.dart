import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/training_coaching/application/training_coaching_providers.dart';
import 'package:herculex/features/training_coaching/data/training_coaching_repository.dart';
import 'package:herculex/features/training_coaching/data/workout_behavior_repository.dart';
import 'package:herculex/features/training_coaching/domain/training_coaching.dart';
import 'package:herculex/features/training_coaching/presentation/widgets/training_coaching_panel.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';

final _now = DateTime(2026, 10, 28, 18);
final _observation = CoachingObservation({
  'version': 1,
  'session': 'source',
  'program': 'program',
  'day': '1|Lower',
  'at': _now.toIso8601String(),
  'known': true,
  'policy': 'unknown',
  'original': [
    {'row': 'row', 'exercise': 'slug:rdl', 'planned': 4},
  ],
  'actual': [
    {'row': 'row', 'exercise': 'slug:rdl', 'completed': 2},
  ],
});
final _signal = CoachingSignal(
  kind: CoachingKind.reduceSets,
  key: 'rdl-review',
  title: 'Review Romanian deadlift volume',
  detail:
      'In 3 of your last 4 comparable workouts, you completed 2 of 4 planned working sets. Review a smaller prescription without increasing effort.',
  evidence: ['1', '2', '3', '4'],
  source: _observation,
  exercise: {'exercise': 'slug:rdl', 'name': 'Romanian deadlift', 'planned': 4},
  targetSets: 2,
);
final _proposal = TrainingCoachingProposalData(
  id: 7,
  programId: 1,
  sourceSessionId: 1,
  kind: 'reduceSets',
  status: 'proposed',
  proposalKey: 'key',
  payloadJson: jsonEncode({'signal': _signal.toJson()}),
  createdAt: _now,
);
PlannedSessionSnapshot _plan(int sets) => PlannedSessionSnapshot(
  name: 'Lower body',
  exercises: [
    PlannedExerciseSnapshot(
      exerciseId: 1,
      orderIndex: 0,
      restSeconds: 120,
      slotRole: 'main',
      trainingMethod: 'straight_sets',
      why: 'Working prescription',
      allowsAdvancedTechniques: false,
      sets: [
        for (var i = 0; i < sets; i++)
          PlannedSetSnapshot(
            index: i + 1,
            repsMin: 8,
            repsMax: 12,
            isWarmup: false,
            setType: 'standard',
            intent: 'rir2',
            rir: 2,
          ),
      ],
    ),
  ],
);

class _FakeBehavior extends Fake implements WorkoutBehaviorRepository {
  ReportReason? saved;
  @override
  Future<void> saveReason(int sessionId, ReportReason reason) async {
    saved = reason;
  }

  @override
  Future<void> dismissReason(int sessionId) async {}
}

class _FakeCoaching extends Fake implements TrainingCoachingRepository {
  bool accepted = false;
  final fakeBehavior = _FakeBehavior();
  @override
  WorkoutBehaviorRepository get behavior => fakeBehavior;
  @override
  CoachingSignal signal(TrainingCoachingProposalData row) => _signal;
  @override
  Future<CoachingPreview> preview(
    int id, {
    int availableMinutes = 30,
    DateTime? extraAt,
  }) async => CoachingPreview(
    proposalId: id,
    signal: _signal,
    availableMinutes: availableMinutes,
    changes: [
      CoachingPlanChange(
        scheduleId: 9,
        date: DateTime(2026, 11, 2),
        before: _plan(4),
        after: _plan(2),
      ),
    ],
    fingerprint: 'reviewed',
    evidenceFingerprint: 'evidence',
    exerciseNames: {1: 'Romanian deadlift'},
  );
  @override
  Future<void> accept(CoachingPreview reviewed) async {
    accepted = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [360.0, 1200.0]) {
    testWidgets(
      'suggestion and explicit preview fit ${width.toInt()}px without overflow',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = _FakeCoaching(), boundary = GlobalKey();
        if (Platform.environment['HX_COACHING_PREVIEW'] == '1') {
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
          });
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              trainingCoachingRepositoryProvider.overrideWithValue(fake),
              trainingCoachingProvider(
                null,
              ).overrideWith((ref) => Stream.value([_proposal])),
            ],
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Manrope',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF00CED1),
                  brightness: Brightness.dark,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 360 ? 1.35 : 1),
                ),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const SizedBox(height: 24),
                          Text(
                            'Your training',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const TrainingCoachingPanel(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Review Romanian deadlift volume'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['HX_COACHING_PREVIEW'] == '1') {
          await tester.runAsync(() async {
            final pixels =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await pixels.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              'outputs/training-coaching-${width.toInt()}.png',
            ).writeAsBytesSync(data!.buffer.asUint8List());
            pixels.dispose();
          });
        }
        await tester.ensureVisible(find.text('Review suggestion'));
        await tester.tap(find.text('Review suggestion'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('4 → 2 working sets'),
          180,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('4 → 2 working sets'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Confirm this plan'),
          180,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Confirm this plan'), findsOneWidget);
        expect(fake.accepted, isFalse);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Confirm this plan'));
        await tester.tap(find.text('Confirm this plan'));
        await tester.pumpAndSettle();
        expect(fake.accepted, isTrue);
        expect(
          find.text('Your confirmed training plan has been saved.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('the optional reason check-in saves one answer and disappears', (
    tester,
  ) async {
    final fake = _FakeCoaching();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingCoachingRepositoryProvider.overrideWithValue(fake),
          trainingCoachingProvider(1).overrideWith((ref) => Stream.value([])),
          workoutBehaviorProvider(1).overrideWith(
            (ref) => Stream.value(
              WorkoutBehaviorSnapshotData(
                id: 1,
                sessionId: 1,
                snapshotJson: jsonEncode(_observation.data),
                capturedAt: _now,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrainingCoachingPanel(sessionId: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What changed your workout?'), findsOneWidget);
    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();
    expect(fake.fakeBehavior.saved, ReportReason.time);
    expect(find.text('What changed your workout?'), findsNothing);
  });
}
