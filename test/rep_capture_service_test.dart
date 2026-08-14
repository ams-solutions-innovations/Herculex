import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/reps/data/phone_motion_source.dart';
import 'package:herculex/features/reps/data/rep_capture_service.dart';
import 'package:herculex/features/reps/data/rep_tracking_repository.dart';
import 'package:herculex/features/reps/domain/motion_sample.dart';
import 'package:herculex/features/reps/domain/rep_detector.dart';
import 'package:herculex/features/reps/domain/rep_suggestion.dart';

import 'support/test_database.dart';

/// Deterministic synthetic trace generator, scoped to this test file (there
/// is no recorded-fixture corpus yet — 10-02 Task 5 is a pending human
/// checkpoint). Offsetting `y` above the oscillation amplitude keeps the
/// magnitude signal strictly positive and single-humped per rep, so it
/// doesn't fold at zero-crossings the way a bare sine would.
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
      // Starts and ends at the trough (offset - amplitude), peaks at the
      // midpoint — one full trough-peak-trough cycle per rep.
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

/// Splits [samples] into ~1 s batches (matching the watch's real batching
/// cadence) and returns the wire-shaped `/herculex/reps/samples` payload
/// maps, in order, with a monotonic `seq`.
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

/// Delivers a full intact capture (start, every batch in order, end) for
/// [captureId] and returns the emitted [RepSuggestion].
Future<RepSuggestion> _deliverIntactCapture(
  RepCaptureService service,
  String captureId,
  List<Map<String, dynamic>> batches, {
  int? provisionalCount,
}) async {
  final future = service.suggestions.first;
  service.handleCaptureStart(_captureStartJson(captureId: captureId));
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

const List<ConfidenceBand> _bandRank = [
  ConfidenceBand.low,
  ConfidenceBand.medium,
  ConfidenceBand.high,
];

void main() {
  final trace = _syntheticPullUpTrace();
  final batches = _batchSamples(trace);
  late final int detectedCount;

  setUpAll(() {
    final result = RepDetector.detect(
      MotionTrace(samples: trace, sensorType: MotionSensorType.linearAcceleration),
      config: const RepDetectorConfig.pullUp(),
    );
    detectedCount = result.repCount;
  });

  group('assembly', () {
    test('the synthetic fixture is detected as exactly 8 reps', () {
      expect(detectedCount, 8);
    });

    test('in-order batches reconstruct the trace exactly and detect 8 reps',
        () async {
      final service = RepCaptureService();
      addTearDown(service.dispose);

      final suggestion =
          await _deliverIntactCapture(service, 'cap-1', batches, provisionalCount: 8);

      expect(suggestion.proposedReps, detectedCount);
      expect(suggestion.sampleCount, trace.length);
      expect(suggestion.missedBatches, 0);
      expect(suggestion.coverageRatio, closeTo(1.0, 1e-9));
    });

    test('a dropped seq raises missedBatches, lowers coverageRatio and lowers '
        'the band relative to the intact delivery', () async {
      final intactService = RepCaptureService();
      addTearDown(intactService.dispose);
      final intact = await _deliverIntactCapture(intactService, 'cap-intact', batches);

      final gappedService = RepCaptureService();
      addTearDown(gappedService.dispose);
      final dropIndex = batches.length ~/ 2;
      final gappedBatches = [
        for (var i = 0; i < batches.length; i++)
          if (i != dropIndex) batches[i],
      ];

      final future = gappedService.suggestions.first;
      gappedService.handleCaptureStart(_captureStartJson(captureId: 'cap-gap'));
      for (final b in gappedBatches) {
        gappedService.handleSamples(_samplesJson('cap-gap', b));
      }
      gappedService.handleCaptureEnd(
        _captureEndJson(captureId: 'cap-gap', batchCount: batches.length),
      );
      final gapped = await future;

      expect(gapped.missedBatches, 1);
      expect(gapped.coverageRatio, lessThan(1.0));
      expect(
        _bandRank.indexOf(gapped.confidenceBand),
        lessThan(_bandRank.indexOf(intact.confidenceBand)),
      );
    });
  });

  group('discard (REP-04)', () {
    test('rawBufferSampleCount is 0 after a successful detection', () async {
      final service = RepCaptureService();
      addTearDown(service.dispose);

      await _deliverIntactCapture(service, 'cap-discard-ok', batches);

      expect(service.rawBufferSampleCount('cap-discard-ok'), 0);
    });

    test('rawBufferSampleCount is 0 after detection throws', () async {
      final service = RepCaptureService(
        detect: (trace, {config = const RepDetectorConfig.pullUp()}) =>
            throw StateError('synthetic detector failure'),
      );
      addTearDown(service.dispose);

      const captureId = 'cap-discard-throw';
      service.handleCaptureStart(_captureStartJson(captureId: captureId));
      for (final b in batches) {
        service.handleSamples(_samplesJson(captureId, b));
      }

      expect(
        () => service.handleCaptureEnd(
          _captureEndJson(captureId: captureId, batchCount: batches.length),
        ),
        throwsStateError,
      );
      expect(service.rawBufferSampleCount(captureId), 0);
    });
  });

  group('nothing-captured vs zero reps', () {
    test('capture end with zero batches yields manual with a reason and no '
        'zero-rep suggestion', () async {
      final service = RepCaptureService();
      addTearDown(service.dispose);

      final suggestions = <RepSuggestion>[];
      final sub = service.suggestions.listen(suggestions.add);
      addTearDown(sub.cancel);

      // capture_start emits `tracking` first; the manual transition this
      // case cares about is the one from capture_end.
      final stateFuture = service.stateStream.skip(1).first;
      service.handleCaptureStart(_captureStartJson(captureId: 'cap-empty'));
      service.handleCaptureEnd(
        _captureEndJson(captureId: 'cap-empty', batchCount: 0, provisionalCount: 5),
      );
      final state = await stateFuture;

      expect(state, TrackerState.manual);
      expect(service.stateReason, isNotNull);
      expect(suggestions, isEmpty);
    });

    test('capture end for an id that never started also yields manual, never '
        'the provisional count', () async {
      final service = RepCaptureService();
      addTearDown(service.dispose);

      final suggestions = <RepSuggestion>[];
      final sub = service.suggestions.listen(suggestions.add);
      addTearDown(sub.cancel);

      final stateFuture = service.stateStream.first;
      service.handleCaptureEnd(
        _captureEndJson(captureId: 'cap-unknown', batchCount: 3, provisionalCount: 6),
      );
      final state = await stateFuture;

      expect(state, TrackerState.manual);
      expect(suggestions, isEmpty);
    });
  });

  group('provisional divergence (B5 rule)', () {
    test('proposedReps == 8 regardless of provisionalCount (2, 8, 14)',
        () async {
      for (final provisional in [2, 8, 14]) {
        final service = RepCaptureService();
        addTearDown(service.dispose);
        final suggestion = await _deliverIntactCapture(
          service,
          'cap-div-$provisional',
          batches,
          provisionalCount: provisional,
        );
        expect(suggestion.proposedReps, 8);
      }
    });

    test('agreement (8) leaves the band unlowered', () async {
      final service = RepCaptureService();
      addTearDown(service.dispose);
      final suggestion = await _deliverIntactCapture(
        service,
        'cap-div-agree',
        batches,
        provisionalCount: 8,
      );

      expect(suggestion.provisionalDisagrees, isFalse);
      expect(suggestion.confidenceBand, RepSuggestion.bandFor(suggestion.setConfidence));
    });

    test('a >1 divergence (14 vs 8) lowers the band by exactly one step',
        () async {
      final service = RepCaptureService();
      addTearDown(service.dispose);
      final suggestion = await _deliverIntactCapture(
        service,
        'cap-div-14',
        batches,
        provisionalCount: 14,
      );

      expect(suggestion.provisionalDisagrees, isTrue);
      expect(
        suggestion.confidenceBand,
        RepSuggestion.bandFor(suggestion.setConfidence).lowerByOne(),
      );
    });

    test('a divergence of exactly 1 (9 vs 8) does not lower the band',
        () async {
      final service = RepCaptureService();
      addTearDown(service.dispose);
      final suggestion = await _deliverIntactCapture(
        service,
        'cap-div-9',
        batches,
        provisionalCount: 9,
      );

      expect(suggestion.provisionalDisagrees, isFalse);
      expect(suggestion.confidenceBand, RepSuggestion.bandFor(suggestion.setConfidence));
    });
  });

  group('phone source gates', () {
    late AppDatabase db;
    late RepTrackingRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = RepTrackingRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> setPlacement(String? placement) async {
      final existing = await repo.settings();
      if (existing == null) {
        await db.into(db.repTrackingSettings).insert(
              RepTrackingSettingsCompanion.insert(
                phonePlacement: Value(placement),
              ),
            );
      } else {
        await (db.update(db.repTrackingSettings)
              ..where((t) => t.id.equals(existing.id)))
            .write(RepTrackingSettingsCompanion(phonePlacement: Value(placement)));
      }
    }

    test('a null phonePlacement returns the typed refusal and creates no '
        'subscription', () async {
      var streamCalls = 0;
      final source = PhoneMotionSource(
        repository: repo,
        clock: () => 0,
        batteryLevel: () async => 100,
        linearAccelerationStream: () {
          streamCalls++;
          return const Stream<MotionSample>.empty();
        },
      );
      addTearDown(source.dispose);

      final stateFuture = source.stateStream.first;
      final refusal = await source.start();

      expect(refusal, PhoneMotionStartRefusal.noPlacement);
      expect(await stateFuture, TrackerState.manual);
      expect(source.isCapturing, isFalse);
      expect(streamCalls, 0);
    });

    test('battery below 15% returns the typed refusal and creates no '
        'subscription', () async {
      await setPlacement('pocket_front');
      var streamCalls = 0;
      final source = PhoneMotionSource(
        repository: repo,
        clock: () => 0,
        batteryLevel: () async => 14,
        linearAccelerationStream: () {
          streamCalls++;
          return const Stream<MotionSample>.empty();
        },
      );
      addTearDown(source.dispose);

      final stateFuture = source.stateStream.first;
      final refusal = await source.start();

      expect(refusal, PhoneMotionStartRefusal.lowBattery);
      expect(await stateFuture, TrackerState.manual);
      expect(source.isCapturing, isFalse);
      expect(streamCalls, 0);
    });

    test('the clock past 5 minutes cancels the subscription, keeps collected '
        'samples and reports stoppedReason == cap', () async {
      await setPlacement('pocket_front');
      var nowMs = 0;
      final controller = StreamController<MotionSample>();
      addTearDown(controller.close);

      final source = PhoneMotionSource(
        repository: repo,
        clock: () => nowMs,
        batteryLevel: () async => 100,
        linearAccelerationStream: () => controller.stream,
      );
      addTearDown(source.dispose);

      final refusal = await source.start();
      expect(refusal, isNull);
      expect(source.isCapturing, isTrue);

      controller.add(const MotionSample(0, 0, 1, 0));
      await Future<void>.delayed(Duration.zero);
      expect(source.isCapturing, isTrue);

      nowMs = const Duration(minutes: 5).inMilliseconds + 1;
      controller.add(const MotionSample(0, 0, 1, 0));
      await Future<void>.delayed(Duration.zero);

      expect(source.isCapturing, isFalse);
    });

    test('the cap firing reports the collected trace via captureEnded with '
        'stoppedReason == cap, and a later stop() is a no-op', () async {
      await setPlacement('armband');
      var nowMs = 0;
      final controller = StreamController<MotionSample>();
      addTearDown(controller.close);

      final source = PhoneMotionSource(
        repository: repo,
        clock: () => nowMs,
        batteryLevel: () async => 100,
        linearAccelerationStream: () => controller.stream,
      );
      addTearDown(source.dispose);

      final endedFuture = source.captureEnded.first;
      await source.start();

      controller.add(const MotionSample(0, 0.5, 1, 0.2));
      await Future<void>.delayed(Duration.zero);
      nowMs = const Duration(minutes: 5).inMilliseconds + 1;
      controller.add(const MotionSample(0, 0.5, 1, 0.2));

      final result = await endedFuture;
      expect(result.stoppedReason, 'cap');
      expect(result.trace.samples, isNotEmpty);
      expect(source.isCapturing, isFalse);
      expect(source.stop(), isNull);
    });
  });
}
