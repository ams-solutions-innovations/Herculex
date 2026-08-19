import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/motion_sample.dart';
import 'package:herculex/features/reps/domain/set_segmenter.dart';

/// Segmentation is what replaces the per-set tap. A missed boundary silently
/// merges two sets into one over-count and a spurious one proposes a set that
/// never happened, so these tests are mostly about the boundaries rather than
/// about finding activity at all.
void main() {
  group('finding sets', () {
    test('three sets separated by rest are found as three windows', () {
      final trace = _workout(const [
        _Segment.rest(20),
        _Segment.work(30),
        _Segment.rest(90),
        _Segment.work(28),
        _Segment.rest(90),
        _Segment.work(25),
        _Segment.rest(20),
      ]);

      final windows = SetSegmenter.segment(trace);

      expect(windows, hasLength(3));
      for (final w in windows) {
        expect(w.durationMs, greaterThan(20000));
        expect(w.durationMs, lessThan(40000));
      }
    });

    test('window bounds bracket the work they came from', () {
      final trace = _workout(const [
        _Segment.rest(30),
        _Segment.work(30),
        _Segment.rest(60),
      ]);

      final windows = SetSegmenter.segment(trace);

      expect(windows, hasLength(1));
      // Work runs from 30 s to 60 s. Padding widens the window, and the
      // envelope's own width delays the crossing slightly, so allow slack —
      // but the window must not miss the middle of the set or run into the
      // following rest.
      expect(windows.single.startMs, lessThan(40000));
      expect(windows.single.endMs, greaterThan(55000));
      expect(windows.single.endMs, lessThan(75000));
    });

    test('a capture that ends mid-set still yields that set', () {
      // The common case, not an error: the user stops the workout on their
      // last rep.
      final trace = _workout(const [_Segment.rest(30), _Segment.work(25)]);

      expect(SetSegmenter.segment(trace), hasLength(1));
    });

    test('a long pause inside a set does not split it', () {
      // A grinding final rep can sit near-still at the sticking point for two
      // or three seconds. minRestMs has to exceed that.
      final trace = _workout(const [
        _Segment.rest(30),
        _Segment.work(15),
        _Segment.rest(3),
        _Segment.work(15),
        _Segment.rest(60),
      ]);

      expect(SetSegmenter.segment(trace), hasLength(1));
    });
  });

  group('rejecting non-sets', () {
    test('a workout with no work at all yields nothing', () {
      expect(SetSegmenter.segment(_workout(const [_Segment.rest(180)])), isEmpty);
    });

    test('a brief burst is not a set', () {
      // Racking a bar, or one rep to test the weight. minSustainedMs is what
      // rejects these.
      final trace = _workout(const [
        _Segment.rest(40),
        _Segment.work(2),
        _Segment.rest(40),
      ]);

      expect(SetSegmenter.segment(trace), isEmpty);
    });

    test('a window longer than maxSetMs is discarded', () {
      final trace = _workout(const [_Segment.rest(20), _Segment.work(400)]);

      expect(
        SetSegmenter.segment(
          trace,
          config: const SetSegmenterConfig(maxSetMs: 120000),
        ),
        isEmpty,
      );
    });

    test('a degenerate trace yields nothing rather than throwing', () {
      expect(
        SetSegmenter.segment(
          const MotionTrace(
            samples: [MotionSample(0, 0, 0, 0)],
            sensorType: MotionSensorType.linearAcceleration,
          ),
        ),
        isEmpty,
      );
    });
  });

  group('the app-state prior', () {
    test('windows outside every believed set are dropped', () {
      // The envelope found motion the app has no set for — walking back from
      // the water fountain, or re-racking. Without the prior this would be
      // proposed as a set.
      final windows = [
        const SetWindow(startMs: 10000, endMs: 40000, peakEnvelope: 5),
        const SetWindow(startMs: 200000, endMs: 230000, peakEnvelope: 5),
      ];

      final kept = SetSegmenter.constrainTo(windows, const [(5000, 50000)]);

      expect(kept, hasLength(1));
      expect(kept.single.startMs, 10000);
    });

    test('a window overlapping a believed set is kept even if it extends past it', () {
      final windows = [
        const SetWindow(startMs: 10000, endMs: 60000, peakEnvelope: 5),
      ];

      expect(
        SetSegmenter.constrainTo(windows, const [(40000, 45000)]),
        hasLength(1),
      );
    });

    test('no constraints means no filtering, not everything filtered', () {
      // The app may have no set/rest state at all — a freeform session. That
      // must degrade to envelope-only segmentation, not to zero sets.
      final windows = [
        const SetWindow(startMs: 10000, endMs: 40000, peakEnvelope: 5),
      ];

      expect(SetSegmenter.constrainTo(windows, const []), hasLength(1));
    });

    test('the prior and the envelope together find exactly the real sets', () {
      final trace = _workout(const [
        _Segment.rest(20),
        _Segment.work(30), // set 1
        _Segment.rest(60),
        _Segment.work(12), // walking about — sustained, but not a set
        _Segment.rest(60),
        _Segment.work(30), // set 2
        _Segment.rest(20),
      ]);

      final raw = SetSegmenter.segment(trace);
      expect(raw.length, greaterThanOrEqualTo(2));

      final constrained = SetSegmenter.constrainTo(raw, const [
        (15000, 55000),
        (160000, 200000),
      ]);

      expect(constrained, hasLength(2));
    });
  });
}

// ── synthetic workout builder ───────────────────────────────────────────────

class _Segment {
  const _Segment.rest(this.seconds) : working = false;
  const _Segment.work(this.seconds) : working = true;

  final int seconds;
  final bool working;
}

/// A continuous capture: rest is near-still, work is a ~2.5 s/rep oscillation
/// at a plausible gym amplitude.
MotionTrace _workout(List<_Segment> segments, {int hz = 50}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];
  const repPeriodMs = 2500;
  const workAmplitude = 3.0;
  var tMs = 0;

  for (final segment in segments) {
    final end = tMs + segment.seconds * 1000;
    final segmentStart = tMs;
    while (tMs < end) {
      final double value;
      if (segment.working) {
        final phase = 2 * pi * (tMs - segmentStart) / repPeriodMs;
        value = workAmplitude * sin(phase);
      } else {
        // Not identically zero: a real resting trace has a noise floor, and a
        // zero-variance baseline makes every threshold degenerate.
        value = 0.05 * sin(tMs * 0.013);
      }
      samples.add(MotionSample(tMs, 0, value, 0));
      tMs += stepMs;
    }
  }

  return MotionTrace(
    samples: samples,
    sensorType: MotionSensorType.linearAcceleration,
  );
}
