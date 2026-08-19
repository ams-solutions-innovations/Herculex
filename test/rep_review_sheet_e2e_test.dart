import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/reps/data/rep_capture_service.dart';
import 'package:herculex/features/reps/data/rep_tracking_repository.dart';
import 'package:herculex/features/reps/domain/motion_sample.dart';
import 'package:herculex/features/reps/domain/rep_suggestion.dart';
import 'package:herculex/features/reps/presentation/rep_review_sheet.dart';
import 'package:herculex/features/reps/presentation/rep_tracking_providers.dart';

import 'support/rep_profiles.dart';
import 'support/test_database.dart';

/// The REP-06 clause that lands outside 10-02: driving one recorded fixture
/// trace end to end (capture -> detection -> review sheet) and proving the
/// tracker never auto-completes a set.
///
/// **There is no recorded fixture corpus yet.** 10-02 Task 5 (recording real
/// pull-up/dip traces on a watch and a pocketed phone) is still a pending
/// human checkpoint per the phase's own risk register — `test/fixtures/motion/`
/// and the `accuracyFixtures` list this plan's original wording names do not
/// exist in this repository. `test/rep_capture_service_test.dart` (10-03b)
/// hit the exact same gap and substituted a deterministic synthetic trace
/// scoped to its own test file; this file follows the same precedent for
/// both the wrist and the phone/armband sub-case, and should be replaced
/// with a real recorded fixture the moment 10-02 Task 5 closes.
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
      'provisionalCount': ?provisionalCount,
    });

Future<RepSuggestion> _captureWrist(
  RepCaptureService service,
  String captureId, {
  int reps = 8,
  int provisionalCount = 8,
  String exerciseSlug = 'pull-up',
}) async {
  final trace = _syntheticPullUpTrace(reps: reps);
  final batches = _batchSamples(trace);
  final future = service.suggestions.first;
  service.handleCaptureStart(
    _captureStartJson(captureId: captureId, exerciseSlug: exerciseSlug),
  );
  for (final b in batches) {
    service.handleSamples(_samplesJson(captureId, b));
  }
  service.handleCaptureEnd(
    _captureEndJson(
      captureId: captureId,
      batchCount: batches.length,
      provisionalCount: provisionalCount,
    ),
  );
  return future;
}

void main() {
  loadRepProfilesForTest();
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late RepTrackingRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = RepTrackingRepository(db);
    await repo.grantConsent(version: 1);
    await repo.setExerciseEnabled('pull-up', true);
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [repTrackingRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('wrist fixture — capture to detection to sheet', () {
    testWidgets(
      'the sheet is pre-filled with the fixture count; dismissing calls '
      'onConfirm zero times and writes zero observations; saving after an '
      'edit calls onConfirm once with the edit and writes exactly one '
      'observation',
      (tester) async {
        final service = RepCaptureService();
        addTearDown(service.dispose);
        final suggestion =
            await _captureWrist(service, 'pullup_wrist_clean_8reps');
        expect(suggestion.proposedReps, 8);
        expect(suggestion.state, isNot(TrackerState.manual));

        // ── Dismissal case ──────────────────────────────────────────────
        var confirmCalls = 0;
        await tester.pumpWidget(
          wrap(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RepReviewSheet.show(
                  context,
                  suggestion: suggestion,
                  sessionId: 1,
                  setEntryId: 1,
                  onConfirm: (reps, rpeX10) async {
                    confirmCalls++;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Pre-fill assertion.
        expect(find.widgetWithText(TextField, '8'), findsOneWidget);

        // Dismiss via the barrier tap, not Save.
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        expect(confirmCalls, 0);
        final rowsAfterDismiss = await db.select(db.repSetObservations).get();
        expect(rowsAfterDismiss, isEmpty);

        // ── Save case, with an edited value ─────────────────────────────
        int? savedReps;
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final field = find.widgetWithText(TextField, '8');
        await tester.enterText(field, '6');
        await tester.pump();

        // Rebuild the button's onConfirm with one that records what it saw
        // and actually completes, by re-showing with a fresh callback —
        // simplest is to just tap Save on the currently-open sheet, whose
        // onConfirm above only incremented confirmCalls. Re-open with a
        // capturing callback instead.
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        confirmCalls = 0;
        await tester.pumpWidget(
          wrap(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RepReviewSheet.show(
                  context,
                  suggestion: suggestion,
                  sessionId: 1,
                  setEntryId: 1,
                  onConfirm: (reps, rpeX10) async {
                    confirmCalls++;
                    savedReps = reps;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, '8'), '6');
        await tester.tap(find.text('Save set'));
        await tester.pumpAndSettle();

        expect(confirmCalls, 1);
        expect(savedReps, 6);

        final rowsAfterSave = await db.select(db.repSetObservations).get();
        expect(rowsAfterSave, hasLength(1));
        expect(rowsAfterSave.single.detectedReps, 8);
        expect(rowsAfterSave.single.confirmedReps, 6);
        expect(rowsAfterSave.single.source, 'wrist');
      },
    );
  });

  group('phone/armband fixture — placement surfaces through the UI', () {
    testWidgets(
      'the "how this was measured" expander reports placement: armband',
      (tester) async {
        await repo.updateSensorPreferences(
          source: 'phone',
          placement: 'armband',
        );
        final service = RepCaptureService();
        addTearDown(service.dispose);
        final trace = _syntheticPullUpTrace(reps: 8);
        final motionTrace = MotionTrace(
          samples: trace,
          sensorType: MotionSensorType.linearAcceleration,
        );
        final suggestion = service.buildPhoneSuggestion(
          captureId: 'pullup_phone_armband_8reps',
          exerciseSlug: 'pull-up',
          trace: motionTrace,
          placement: 'armband',
          stoppedReason: 'user',
        );
        expect(suggestion.proposedReps, 8);
        expect(suggestion.placement, 'armband');
        expect(suggestion.source, 'phone');

        await tester.pumpWidget(
          wrap(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RepReviewSheet.show(
                  context,
                  suggestion: suggestion,
                  sessionId: 1,
                  setEntryId: 1,
                  onConfirm: (reps, rpeX10) async {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('How this was measured'));
        await tester.pumpAndSettle();

        expect(find.text('armband'), findsOneWidget);
      },
    );
  });
}
