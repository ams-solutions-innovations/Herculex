import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/motion_sample.dart';
import 'package:herculex/features/reps/domain/rep_detector.dart';
import 'package:herculex/features/reps/domain/rep_movement.dart';

/// Characterisation tests for [RepDetector].
///
/// The detector is the most algorithmically dense file in the feature and had
/// no test of its own — it was only exercised indirectly through
/// `rep_capture_service_test.dart`. These tests pin the properties the
/// pipeline is *designed* to have, so the multi-channel refactor has a
/// regression net to land against:
///
///  * counting is invariant to delivery rate (the fixed 50 Hz resample grid),
///  * a closed trough-peak-trough cycle is what counts, not a bare peak,
///  * the absolute amplitude floor is what makes walking count exactly zero,
///  * the refractory window bounds cycle duration at both ends,
///  * `accelerometer` and `linear_acceleration` traces of the same motion
///    agree once gravity is detrended out.
///
/// Every trace here is **synthetic and deliberately so**: these are
/// determinism, invariance and edge-case checks, never accuracy measurements.
/// Accuracy is REP-06's recorded corpus and cannot be met with generated
/// signals — see the header of `tool/synthesize_motion_trace.dart`.
void main() {
  group('clean periodic trace', () {
    test('counts one rep per trough-peak-trough cycle', () {
      final result = RepDetector.detect(_repTrace(reps: 8));

      expect(result.repCount, 8);
      expect(result.cyclePeriodsMs, hasLength(8));
      expect(result.cycleAmplitudes, hasLength(8));
      expect(result.missedRepSuspected, isFalse);
    });

    test('reports high set confidence and per-rep confidence for every rep', () {
      final result = RepDetector.detect(_repTrace(reps: 8));

      expect(result.perRepConfidence, hasLength(result.repCount));
      expect(result.setConfidence, greaterThan(0.75));
      for (final c in result.perRepConfidence) {
        expect(c, inInclusiveRange(0.0, 1.0));
      }
    });

    test('recovers the nominal cycle period', () {
      final result = RepDetector.detect(_repTrace(reps: 6, periodMs: 2000));

      for (final p in result.cyclePeriodsMs) {
        expect(p, closeTo(2000, 120));
      }
    });
  });

  group('resample invariance', () {
    // The whole reason detect() resamples its own input rather than trusting
    // the caller: a 30 Hz watch batch and a 50 Hz one of the same set must
    // not produce different counts.
    test('30 Hz and 50 Hz traces of the same motion agree', () {
      final at30 = RepDetector.detect(_repTrace(reps: 8, hz: 30));
      final at50 = RepDetector.detect(_repTrace(reps: 8, hz: 50));

      expect(at30.repCount, at50.repCount);
      expect(at30.repCount, 8);
    });

    test('100 Hz agrees with 50 Hz', () {
      final at100 = RepDetector.detect(_repTrace(reps: 8, hz: 100));

      expect(at100.repCount, 8);
    });

    test('is deterministic — the same trace twice gives the same result', () {
      final a = RepDetector.detect(_repTrace(reps: 7));
      final b = RepDetector.detect(_repTrace(reps: 7));

      expect(a.repCount, b.repCount);
      expect(a.setConfidence, b.setConfidence);
      expect(a.cyclePeriodsMs, b.cyclePeriodsMs);
    });
  });

  group('false-positive resistance', () {
    test('a walking-like trace counts exactly zero', () {
      // Load-bearing. A purely relative amplitude gate is scale-free — in a
      // trace containing nothing but walking, walking *is* the running
      // median, so every step clears it. Only the absolute floor makes this
      // zero.
      final result = RepDetector.detect(_walkingTrace(seconds: 60));

      expect(result.repCount, 0);
    });

    test('rest-only noise counts zero', () {
      final result = RepDetector.detect(_restTrace(seconds: 45));

      expect(result.repCount, 0);
    });

    test('an oscillation below the absolute amplitude floor counts zero', () {
      // Excursion ~1.0 m/s², under the pull-up config's 2.5 m/s² floor.
      //
      // This pins today's behaviour, and it is exactly the limitation that
      // blocks wrist-sourced bench presses and biceps curls: a 3 s curl peaks
      // near A*w^2 = 0.25 * (2*pi/3)^2 ~= 1.1 m/s² at the wrist. The fix is
      // not to lower this number globally — it is what keeps walking at zero
      // — but to detect on a channel whose amplitude does not vanish with
      // cadence.
      final result = RepDetector.detect(_repTrace(reps: 8, amplitude: 0.5));

      expect(result.repCount, 0);
    });
  });

  group('refractory window', () {
    test('cycles faster than minPeriodMs are rejected', () {
      // 400 ms cycles against the pull-up config's 800 ms floor.
      final result = RepDetector.detect(
        _repTrace(reps: 12, periodMs: 400),
        config: const RepDetectorConfig.pullUp(),
      );

      expect(result.repCount, 0);
    });

    test('the dip config accepts a cadence the pull-up config rejects', () {
      // 700 ms sits between the dip floor (600 ms) and the pull-up floor
      // (800 ms) — the one case that proves per-movement configs are load
      // -bearing rather than decorative.
      final trace = _repTrace(reps: 10, periodMs: 700);

      final asDip = RepDetector.detect(
        trace,
        config: const RepDetectorConfig.dip(),
      );
      final asPullUp = RepDetector.detect(
        trace,
        config: const RepDetectorConfig.pullUp(),
      );

      expect(asDip.repCount, greaterThan(0));
      expect(asPullUp.repCount, 0);
    });

    test('cycles slower than maxPeriodMs are rejected', () {
      final result = RepDetector.detect(
        _repTrace(reps: 3, periodMs: 12000),
        config: const RepDetectorConfig.pullUp(),
      );

      expect(result.repCount, 0);
    });
  });

  group('missed reps', () {
    test('a hole in the sequence is flagged and penalises set confidence', () {
      final withGap = RepDetector.detect(_repTraceWithGap());
      final clean = RepDetector.detect(_repTrace(reps: 8));

      expect(withGap.missedRepSuspected, isTrue);
      expect(withGap.setConfidence, lessThan(clean.setConfidence));
    });
  });

  group('sensor types', () {
    test('an accelerometer trace agrees with a linear-acceleration one', () {
      // Same motion, one still sitting on the ~9.81 m/s² gravity pedestal.
      // The gravity detrend is what makes the two comparable; without it the
      // pedestal swamps every excursion.
      final linear = RepDetector.detect(_repTrace(reps: 8));
      final raw = RepDetector.detect(
        _repTrace(reps: 8, offset: 5.0 + 9.81, sensorType: MotionSensorType.accelerometer),
      );

      expect(raw.repCount, linear.repCount);
    });

    test('needsGravityRemoval keys on the trace, not the samples', () {
      expect(_repTrace(reps: 2).needsGravityRemoval, isFalse);
      expect(
        _repTrace(reps: 2, sensorType: MotionSensorType.accelerometer)
            .needsGravityRemoval,
        isTrue,
      );
    });
  });

  group('degenerate input', () {
    test('an empty trace returns the empty result', () {
      final result = RepDetector.detect(
        const MotionTrace(samples: [], sensorType: MotionSensorType.linearAcceleration),
      );

      expect(result.repCount, 0);
      expect(result.perRepConfidence, isEmpty);
      expect(result.setConfidence, 0);
    });

    test('a single sample returns the empty result', () {
      final result = RepDetector.detect(
        const MotionTrace(
          samples: [MotionSample(0, 0, 9.81, 0)],
          sensorType: MotionSensorType.linearAcceleration,
        ),
      );

      expect(result.repCount, 0);
    });

    test('non-advancing timestamps return the empty result', () {
      final result = RepDetector.detect(
        const MotionTrace(
          samples: [
            MotionSample(0, 0, 9.81, 0),
            MotionSample(0, 0, 9.81, 0),
            MotionSample(0, 0, 9.81, 0),
          ],
          sensorType: MotionSensorType.linearAcceleration,
        ),
      );

      expect(result.repCount, 0);
    });

    test('a perfectly constant trace returns the empty result', () {
      final result = RepDetector.detect(_restTrace(seconds: 10, noise: 0));

      expect(result.repCount, 0);
    });
  });

  group('config', () {
    test('forMovement maps each RepMovement to its own thresholds', () {
      final pullUp = RepDetectorConfig.forMovement(RepMovement.verticalPull);
      final dip = RepDetectorConfig.forMovement(RepMovement.bodyweightPush);

      expect(pullUp.minPeriodMs, 800);
      expect(pullUp.maxPeriodMs, 8000);
      expect(pullUp.minCycleAmplitude, 2.5);

      expect(dip.minPeriodMs, 600);
      expect(dip.maxPeriodMs, 6000);
      expect(dip.minCycleAmplitude, 2.0);
    });

    test('copyWith overrides only the named field', () {
      const base = RepDetectorConfig.pullUp();
      final tuned = base.copyWith(minCycleAmplitude: 1.0);

      expect(tuned.minCycleAmplitude, 1.0);
      expect(tuned.minPeriodMs, base.minPeriodMs);
      expect(tuned.maxPeriodMs, base.maxPeriodMs);
      expect(tuned.thresholdK, base.thresholdK);
    });

    test('every threshold has a default — no field is required', () {
      const config = RepDetectorConfig();

      expect(config.resampleHz, 50);
      expect(config.smoothingTaps.isOdd, isTrue, reason: 'must stay phase-neutral');
      expect(config.missedRepPenalty, lessThan(config.perRepConfidenceFloor));
    });
  });
}

// ── synthetic trace builders ────────────────────────────────────────────────
//
// Deliberately simple and seedless: every builder here is a pure function of
// its arguments, so a failure is reproducible by reading the call site.

/// A periodic trace shaped like one rep per cycle.
///
/// The oscillation rides on [offset] so the vector magnitude stays strictly
/// positive and single-humped per cycle — a bare sine folds at its zero
/// crossings and would present as two peaks per rep.
MotionTrace _repTrace({
  required int reps,
  int periodMs = 2000,
  double amplitude = 3.5,
  double offset = 5.0,
  int hz = 50,
  int leadInMs = 4000,
  int tailMs = 3000,
  String sensorType = MotionSensorType.linearAcceleration,
}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];
  var tMs = 0;

  for (; tMs < leadInMs; tMs += stepMs) {
    samples.add(MotionSample(tMs, 0, offset, 0));
  }
  for (var r = 0; r < reps; r++) {
    final cycleStart = tMs;
    while (tMs - cycleStart < periodMs) {
      final phase = 2 * pi * (tMs - cycleStart) / periodMs;
      // Starts and ends at the trough, peaks at the midpoint: exactly one
      // closed trough-peak-trough cycle per rep.
      samples.add(MotionSample(tMs, 0, offset + amplitude * sin(phase - pi / 2), 0));
      tMs += stepMs;
    }
  }
  final tailEnd = tMs + tailMs;
  for (; tMs < tailEnd; tMs += stepMs) {
    samples.add(MotionSample(tMs, 0, offset, 0));
  }

  return MotionTrace(samples: samples, sensorType: sensorType);
}

/// Four reps, a long pause, then four more — the shape that must set
/// [RepDetectionResult.missedRepSuspected].
MotionTrace _repTraceWithGap() {
  const periodMs = 2000;
  const stepMs = 20;
  const amplitude = 3.5;
  const offset = 5.0;
  final samples = <MotionSample>[];
  var tMs = 0;

  void rest(int durationMs) {
    final end = tMs + durationMs;
    for (; tMs < end; tMs += stepMs) {
      samples.add(MotionSample(tMs, 0, offset, 0));
    }
  }

  void cycles(int n) {
    for (var r = 0; r < n; r++) {
      final cycleStart = tMs;
      while (tMs - cycleStart < periodMs) {
        final phase = 2 * pi * (tMs - cycleStart) / periodMs;
        samples.add(MotionSample(tMs, 0, offset + amplitude * sin(phase - pi / 2), 0));
        tMs += stepMs;
      }
    }
  }

  rest(4000);
  cycles(4);
  rest(6000);
  cycles(4);
  rest(3000);

  return MotionTrace(samples: samples, sensorType: MotionSensorType.linearAcceleration);
}

/// ~1.1 Hz low-amplitude gait. Periodic, so a bare peak counter finds plenty
/// of "reps" in it — which is the point.
MotionTrace _walkingTrace({required int seconds, int hz = 50}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];
  const strideMs = 900;
  const amplitude = 1.2;
  const offset = 9.81;

  for (var tMs = 0; tMs < seconds * 1000; tMs += stepMs) {
    final phase = 2 * pi * tMs / strideMs;
    samples.add(
      MotionSample(
        tMs,
        amplitude * 0.4 * sin(phase * 0.5),
        offset + amplitude * sin(phase),
        amplitude * 0.3 * cos(phase),
      ),
    );
  }

  return MotionTrace(samples: samples, sensorType: MotionSensorType.accelerometer);
}

/// Still, with an optional small deterministic tremor.
MotionTrace _restTrace({required int seconds, double noise = 0.03, int hz = 50}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];

  for (var tMs = 0; tMs < seconds * 1000; tMs += stepMs) {
    // Deterministic, aperiodic-ish jitter — no RNG, so a failure reproduces.
    final n = noise * sin(tMs * 0.37) * cos(tMs * 0.11);
    samples.add(MotionSample(tMs, n, 5.0 + n, n));
  }

  return MotionTrace(samples: samples, sensorType: MotionSensorType.linearAcceleration);
}
