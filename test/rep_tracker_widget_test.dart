import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/reps/data/phone_motion_source.dart';
import 'package:herculex/features/reps/data/rep_capture_service.dart';
import 'package:herculex/features/reps/data/rep_tracking_repository.dart';
import 'package:herculex/features/reps/domain/motion_sample.dart';
import 'package:herculex/features/reps/domain/rep_movement.dart';
import 'package:herculex/features/reps/domain/rep_suggestion.dart';
import 'package:herculex/features/reps/presentation/rep_review_sheet.dart';
import 'package:herculex/features/reps/presentation/rep_tracker_panel.dart';
import 'package:herculex/features/reps/presentation/rep_tracking_providers.dart';

import 'support/test_database.dart';

/// Deterministic synthetic trace generator, scoped to this test file (there
/// is no recorded-fixture corpus yet — 10-02 Task 5's fixture recording is
/// still a pending human checkpoint; see `test/rep_capture_service_test.dart`
/// for the same precedent).
List<MotionSample> _syntheticPullUpTrace({
  int reps = 8,
  int periodMs = 2000,
  double amplitude = 3.5,
  double offset = 5.0,
  int hz = 50,
  int leadInMs = 3000,
  int tailMs = 2000,
}) {
  final stepMs = 1000 ~/ hz;
  final samples = <MotionSample>[];
  var tMs = 0;

  for (; tMs < leadInMs; tMs += stepMs) {
    samples.add(MotionSample(tMs, 0, offset, 0));
  }
  for (var r = 0; r < reps; r++) {
    final cycleStart = tMs;
    while (tMs - cycleStart < periodMs) {
      final phase = 2 * pi * (tMs - cycleStart) / periodMs;
      final y = offset + amplitude * sin(phase - pi / 2);
      samples.add(MotionSample(tMs, 0, y, 0));
      tMs += stepMs;
    }
  }
  final tailEnd = tMs + tailMs;
  for (; tMs < tailEnd; tMs += stepMs) {
    samples.add(MotionSample(tMs, 0, offset, 0));
  }
  return samples;
}

List<Map<String, dynamic>> _batchSamples(
  List<MotionSample> samples, {
  int perBatch = 50,
}) {
  final batches = <Map<String, dynamic>>[];
  for (var i = 0; i < samples.length; i += perBatch) {
    final end = min(i + perBatch, samples.length);
    batches.add({
      'seq': i ~/ perBatch,
      'samples': [
        for (final s in samples.sublist(i, end))
          {'tMs': s.tMs, 'x': s.x, 'y': s.y, 'z': s.z},
      ],
    });
  }
  return batches;
}

String _captureStartJson({
  required String captureId,
  String exerciseSlug = 'pull-up',
  String sensorType = 'linear_acceleration',
}) =>
    jsonEncode({
      'captureId': captureId,
      'exerciseSlug': exerciseSlug,
      'sensorType': sensorType,
      'startedAtMs': 0,
    });

String _samplesJson(
  String captureId,
  Map<String, dynamic> batch, {
  String sensorType = 'linear_acceleration',
}) =>
    jsonEncode({
      'captureId': captureId,
      'seq': batch['seq'],
      'sensorType': sensorType,
      'samples': batch['samples'],
    });

String _captureEndJson({
  required String captureId,
  required int batchCount,
  String stoppedReason = 'user',
  int? provisionalCount,
}) =>
    jsonEncode({
      'captureId': captureId,
      'endedAtMs': 999999,
      'batchCount': batchCount,
      'stoppedReason': stoppedReason,
      if (provisionalCount != null) 'provisionalCount': provisionalCount,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late RepTrackingRepository repo;
  late RepCaptureService captureService;
  late PhoneMotionSource phoneSource;

  Future<void> grantAndEnable(String slug) async {
    await repo.grantConsent(version: 1);
    await repo.setExerciseEnabled(slug, true);
  }

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        repTrackingRepositoryProvider.overrideWithValue(repo),
        repCaptureServiceProvider.overrideWithValue(captureService),
        phoneMotionSourceProvider.overrideWithValue(phoneSource),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  setUp(() async {
    db = await openTestDatabase();
    repo = RepTrackingRepository(db);
    captureService = RepCaptureService();
    phoneSource = PhoneMotionSource(
      repository: repo,
      clock: () => 0,
      batteryLevel: () async => 100,
      linearAccelerationStream: () => const Stream<MotionSample>.empty(),
    );
  });

  tearDown(() async {
    captureService.dispose();
    phoneSource.dispose();
    await db.close();
  });

  group('RepTrackerPanel', () {
    testWidgets('disabled (no consent) renders nothing', (tester) async {
      await tester.pumpWidget(
        wrap(
          RepTrackerPanel(
            exerciseSlug: 'pull-up',
            sessionId: 1,
            setEntryId: 1,
            onSuggestion: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RepTrackerPanel), findsOneWidget);
      final size = tester.getSize(find.byType(RepTrackerPanel));
      expect(size, Size.zero);
      expect(find.text('Start tracking'), findsNothing);
    });

    testWidgets('ready renders a start control and no count', (tester) async {
      await grantAndEnable('pull-up');

      await tester.pumpWidget(
        wrap(
          RepTrackerPanel(
            exerciseSlug: 'pull-up',
            sessionId: 1,
            setEntryId: 1,
            onSuggestion: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start tracking'), findsOneWidget);
      expect(find.textContaining('reps proposed'), findsNothing);
      expect(find.textContaining('Tracking'), findsNothing);
    });

    testWidgets('countOnly renders a count and no RPE suggestion',
        (tester) async {
      await grantAndEnable('pull-up');
      final trace = _syntheticPullUpTrace();
      // Drop one batch and disagree with the provisional count by >1 — two
      // independent band-lowering causes take a clean set from high to low
      // (10-03b's "each cause exactly one lowerByOne() step").
      final batches = _batchSamples(trace);
      final gapped = [
        for (var i = 0; i < batches.length; i++) if (i != 1) batches[i],
      ];

      RepSuggestion? received;
      await tester.pumpWidget(
        wrap(
          RepTrackerPanel(
            exerciseSlug: 'pull-up',
            sessionId: 1,
            setEntryId: 1,
            onSuggestion: (s) => received = s,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start tracking'));
      await tester.pump();

      captureService.handleCaptureStart(
        _captureStartJson(captureId: 'cap-widget-countonly'),
      );
      for (final b in gapped) {
        captureService.handleSamples(_samplesJson('cap-widget-countonly', b));
      }
      captureService.handleCaptureEnd(
        _captureEndJson(
          captureId: 'cap-widget-countonly',
          batchCount: batches.length,
          provisionalCount: 40,
        ),
      );
      await tester.pumpAndSettle();

      expect(received, isNotNull);
      expect(received!.state, TrackerState.countOnly);
      expect(find.text('8 reps proposed — no RPE suggestion'), findsOneWidget);
      expect(
        find.text('low confidence — reps proposed, no RPE suggestion'),
        findsOneWidget,
      );
    });

    testWidgets('manual renders the manual-entry path and the stateReason',
        (tester) async {
      await grantAndEnable('pull-up');

      await tester.pumpWidget(
        wrap(
          RepTrackerPanel(
            exerciseSlug: 'pull-up',
            sessionId: 1,
            setEntryId: 1,
            onSuggestion: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start tracking'));
      await tester.pump();

      // A capture_end for a captureId this service never saw a start for
      // degrades straight to manual with a stated reason (never a zero-rep
      // suggestion, never the provisional count).
      captureService.handleCaptureEnd(
        _captureEndJson(captureId: 'cap-widget-unknown', batchCount: 3),
      );
      await tester.pumpAndSettle();

      expect(find.text('Log this set manually'), findsOneWidget);
      expect(
        find.text('watch was not connected — count not verified'),
        findsOneWidget,
      );
    });

    testWidgets('consent revoked mid-session makes the panel disappear on '
        'the next build', (tester) async {
      await grantAndEnable('pull-up');

      await tester.pumpWidget(
        wrap(
          RepTrackerPanel(
            exerciseSlug: 'pull-up',
            sessionId: 1,
            setEntryId: 1,
            onSuggestion: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start tracking'), findsOneWidget);

      await repo.revokeConsent();
      // Force the FutureProvider to re-fetch rather than serve its cached
      // value, mirroring what a real revoke (via a different provider
      // container write) would trigger.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RepTrackerPanel)),
      );
      container.invalidate(repTrackingSettingsProvider);
      container.invalidate(repTrackingEnabledForProvider('pull-up'));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(RepTrackerPanel));
      expect(size, Size.zero);
      expect(find.text('Start tracking'), findsNothing);
    });
  });

  group('RepReviewSheet', () {
    RepSuggestion suggestion({int proposedReps = 8}) => RepSuggestion(
          captureId: 'cap-review',
          exerciseSlug: 'pull-up',
          movement: RepMovement.pullUp,
          source: 'wrist',
          placement: null,
          sensorType: MotionSensorType.linearAcceleration,
          proposedReps: proposedReps,
          provisionalCount: proposedReps,
          provisionalDisagrees: false,
          setConfidence: 0.9,
          confidenceBand: ConfidenceBand.high,
          missedRepSuspected: false,
          missedBatches: 0,
          sampleCount: 500,
          coverageRatio: 1.0,
          featuresJson: null,
          state: TrackerState.tracking,
          stateReason: null,
        );

    testWidgets('the rep field is editable, pre-filled, and the edited '
        'value — not proposedReps — reaches onConfirm', (tester) async {
      int? confirmedReps;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => RepReviewSheet.show(
                context,
                suggestion: suggestion(proposedReps: 8),
                sessionId: 1,
                onConfirm: (reps, rpeX10) async {
                  confirmedReps = reps;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, '8');
      expect(field, findsOneWidget);

      await tester.enterText(field, '5');
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();

      expect(confirmedReps, 5);
    });
  });
}
