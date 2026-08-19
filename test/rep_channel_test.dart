import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/channel_extractor.dart';
import 'package:herculex/features/reps/domain/channel_selector.dart';
import 'package:herculex/features/reps/domain/motion_sample.dart';
import 'package:herculex/features/reps/domain/rep_detector.dart';
import 'package:herculex/features/reps/domain/rep_tracking_eligibility.dart';
import 'package:herculex/features/reps/domain/rep_tracking_profile.dart';

import 'support/rep_profiles.dart';

/// The multi-channel pipeline: extraction, selection, and the end-to-end
/// property the whole widening exists for — that a slow wrist-sensed rep is
/// countable at all.
void main() {
  setUpAll(loadRepProfilesForTest);

  group('extraction', () {
    test('a linear-acceleration trace offers only the dynamic channel', () {
      // Gravity was removed by the platform's sensor fusion and cannot be
      // recovered, so there is no tilt to measure.
      final channels = ChannelExtractor.extract(
        _wristTrace(reps: 6, gravity: false, gyro: false),
      );

      expect(channels.map((c) => c.channel), [RepChannel.dyn]);
    });

    test('a full trace offers all three channels', () {
      final channels = ChannelExtractor.extract(_wristTrace(reps: 6));

      expect(
        channels.map((c) => c.channel).toSet(),
        {RepChannel.tilt, RepChannel.dyn, RepChannel.rot},
      );
    });

    test('angular channels are flagged as such, the dynamic one is not', () {
      // This flag is what stops a tilt amplitude in degrees being compared
      // against a floor in m/s².
      final channels = ChannelExtractor.extract(_wristTrace(reps: 6));
      final byChannel = {for (final c in channels) c.channel: c};

      expect(byChannel[RepChannel.tilt]!.isAngular, isTrue);
      expect(byChannel[RepChannel.rot]!.isAngular, isTrue);
      expect(byChannel[RepChannel.dyn]!.isAngular, isFalse);
    });

    test('every channel has one value per sample', () {
      final trace = _wristTrace(reps: 5);
      for (final channel in ChannelExtractor.extract(trace)) {
        expect(channel.values, hasLength(trace.samples.length),
            reason: channel.channel.id);
      }
    });

    test('tilt is measured against the set median, not against world down', () {
      // The same motion performed with the watch rotated onto the inside of
      // the wrist must produce the same tilt curve — the channel measures how
      // much the device turned during the set, not how it was worn.
      final upright = ChannelExtractor.extract(_wristTrace(reps: 6))
          .firstWhere((c) => c.channel == RepChannel.tilt);
      final flipped = ChannelExtractor.extract(_wristTrace(reps: 6, flipped: true))
          .firstWhere((c) => c.channel == RepChannel.tilt);

      for (var i = 0; i < upright.values.length; i++) {
        expect(flipped.values[i], closeTo(upright.values[i], 1.0));
      }
    });

    test('a trace too short to derive anything from yields no channels', () {
      expect(
        ChannelExtractor.extract(
          const MotionTrace(
            samples: [MotionSample(0, 0, 9.81, 0)],
            sensorType: MotionSensorType.accelerometer,
          ),
        ),
        isEmpty,
      );
    });
  });

  group('selection', () {
    test('picks the channel that actually repeats', () {
      final channels = ChannelExtractor.extract(_wristTrace(reps: 8, periodMs: 3000));

      final winner = ChannelSelector.select(
        channels,
        sampleRateHz: 50,
        minPeriodMs: 900,
        maxPeriodMs: 9000,
      );

      expect(winner, isNotNull);
      expect(winner!.periodicity, greaterThan(0.25));
      expect(winner.dominantPeriodMs, closeTo(3000, 400));
    });

    test('returns null when nothing repeats, rather than the least bad option', () {
      // The honest output for an unmeasurable set is "manual, with a reason",
      // never a count derived from whichever noise floor scored highest.
      final winner = ChannelSelector.select(
        ChannelExtractor.extract(_stillTrace(seconds: 30)),
        sampleRateHz: 50,
        minPeriodMs: 900,
        maxPeriodMs: 9000,
      );

      expect(winner, isNull);
    });

    test('selection is scale-free; the amplitude gate is what rejects a tremor', () {
      // Deliberate division of labour, and worth pinning because it looks
      // like a bug from the outside: the selector z-normalises, so a tiny but
      // perfectly periodic tremor scores *high* on periodicity and gets
      // selected. It is the detector's absolute amplitude floor, not the
      // selector, that then counts zero reps.
      //
      // Putting an amplitude test in the selector too would mean two places
      // deciding what is big enough to be a rep, which is one more than can
      // stay consistent.
      final tremor = _tremorTrace(seconds: 40, periodMs: 2500, degrees: 0.4);

      final winner = ChannelSelector.select(
        ChannelExtractor.extract(tremor),
        sampleRateHz: 50,
        minPeriodMs: 900,
        maxPeriodMs: 9000,
      );
      expect(winner, isNotNull, reason: 'a tremor does repeat');

      final (result, _) =
          RepDetector.detectForProfile(tremor, profileFor('dumbbell-curl')!);
      expect(result.repCount, 0, reason: 'but it is nowhere near rep-sized');
    });

    test('a profile filters candidates and cannot conjure one', () {
      final channels = ChannelExtractor.extract(_wristTrace(reps: 6));
      final pullUp = profileFor('pull-up')!;

      // pull-up lists dyn only, so the tilt and rot the trace carries are
      // dropped rather than considered.
      final allowed = ChannelSelector.allowedBy(pullUp, channels);
      expect(allowed.map((c) => c.channel), [RepChannel.dyn]);

      // And a channel the profile lists but the trace lacks stays absent.
      final bench = profileFor('barbell-bench-press')!;
      final dynOnly = ChannelExtractor.extract(
        _wristTrace(reps: 6, gravity: false, gyro: false),
      );
      expect(
        ChannelSelector.allowedBy(bench, dynOnly).map((c) => c.channel),
        [RepChannel.dyn],
      );
    });

    test('a constant signal is skipped, not scored', () {
      final scored = ChannelSelector.score(
        [
          const ExtractedChannel(
            channel: RepChannel.tilt,
            values: [1, 1, 1, 1, 1, 1, 1, 1],
            isAngular: true,
          ),
        ],
        sampleRateHz: 50,
        minPeriodMs: 100,
        maxPeriodMs: 200,
      );

      expect(scored, isEmpty);
    });
  });

  group('the slow-rep property', () {
    test('a 3 s biceps curl counts, where the dynamic channel alone counts zero', () {
      // This is the whole reason the tilt channel exists.
      //
      // A deliberately slow curl moves the wrist through a large arc but
      // accelerates it barely at all: peak linear acceleration is around
      // A*w^2 = 0.25 * (2*pi/3)^2 ~= 1.1 m/s², under any floor that also keeps
      // walking from counting as reps. The forearm still rotates through 70°
      // regardless of tempo, and that is what gets counted.
      final trace = _wristTrace(
        reps: 8,
        periodMs: 3000,
        tiltDegrees: 70,
        linearAmplitude: 1.1,
      );
      final curl = profileFor('dumbbell-curl')!;

      final (result, channel) = RepDetector.detectForProfile(trace, curl);

      expect(result.repCount, 8);
      expect(channel, RepChannel.tilt, reason: 'the dynamic channel is too weak here');

      // And the proof that this is not just a looser threshold. Counting the
      // same set on the dynamic channel needs a floor low enough to see a
      // 1.1 m/s² peak — but walking peaks near 1.2 m/s², so any such floor
      // also counts a walk to the water fountain as a set. At the only
      // dynamic floor that provably keeps walking at zero (2.5 m/s², pinned
      // by rep_detector_test.dart) this trace counts nothing.
      //
      // There is no single dynamic threshold that both counts slow curls and
      // rejects walking. That is why the channel had to change, not the
      // number.
      final dynOnly = ChannelExtractor.extract(trace.resampled())
          .firstWhere((c) => c.channel == RepChannel.dyn);
      final dynResult = RepDetector.detectOnChannel(
        dynOnly.values,
        config: const RepDetectorConfig.pullUp(),
      );
      expect(dynResult.repCount, 0);
    });

    test('a bench press at a normal tempo counts', () {
      final (result, channel) = RepDetector.detectForProfile(
        _wristTrace(reps: 6, periodMs: 2500, tiltDegrees: 40, linearAmplitude: 2.0),
        profileFor('barbell-bench-press')!,
      );

      expect(result.repCount, 6);
      expect(channel, isNotNull);
    });

    test('walking still counts zero on every channel', () {
      // Widening the pipeline must not have widened what counts as a rep. A
      // pocketed phone during a walk to the water fountain carries a strong,
      // clean ~1.1 Hz signal in all three channels.
      for (final slug in ['pull-up', 'dumbbell-curl', 'barbell-bench-press']) {
        final (result, _) = RepDetector.detectForProfile(
          _walkingTrace(seconds: 60),
          profileFor(slug)!,
        );
        expect(result.repCount, 0, reason: slug);
      }
    });

    test('an unsupported exercise detects nothing even given a perfect trace', () {
      final profile = RepTrackingProfile.fromJson({
        'slug': 'seated-leg-curl',
        'tier': 'unsupported',
        'site': null,
        'family': null,
        'channels': <String>[],
        'reason': 'femur fixed',
      });

      final (result, channel) = RepDetector.detectForProfile(
        _wristTrace(reps: 8),
        profile,
      );

      expect(result.repCount, 0);
      expect(channel, isNull);
    });
  });

  group('backward compatibility', () {
    test('a three-axis fixture CSV still parses, with null extra axes', () {
      final trace = MotionTrace.fromCsv(
        't_ms,x,y,z\n0,1.0,2.0,3.0\n20,1.1,2.1,3.1\n',
        sensorType: MotionSensorType.linearAcceleration,
      );

      expect(trace.samples, hasLength(2));
      expect(trace.samples.first.x, 1.0);
      expect(trace.samples.first.gx, isNull);
      expect(trace.samples.first.rx, isNull);
      expect(trace.hasGravity, isFalse);
      expect(trace.hasGyro, isFalse);
    });

    test('a three-axis trace round-trips through CSV byte-identically', () {
      // An existing fixture must not show up as a diff after a re-save.
      const csv = 't_ms,x,y,z\n0,1.000000,2.000000,3.000000\n'
          '20,1.100000,2.100000,3.100000\n';
      final trace = MotionTrace.fromCsv(
        csv,
        sensorType: MotionSensorType.linearAcceleration,
      );

      expect(trace.toCsv(), csv);
    });

    test('the wide CSV layout round-trips', () {
      final trace = _wristTrace(reps: 2);
      final reparsed = MotionTrace.fromCsv(
        trace.toCsv(),
        sensorType: trace.sensorType,
      );

      expect(reparsed.samples.length, trace.samples.length);
      expect(reparsed.hasGravity, isTrue);
      expect(reparsed.hasGyro, isTrue);
      expect(reparsed.samples.first.gx, closeTo(trace.samples.first.gx!, 1e-5));
      expect(reparsed.samples.last.rz, closeTo(trace.samples.last.rz!, 1e-5));
    });

    test('resampling carries the extra axes and never invents them', () {
      final resampled = _wristTrace(reps: 3, hz: 30).resampled(hz: 50);

      expect(resampled.hasGravity, isTrue);
      expect(resampled.hasGyro, isTrue);

      // A trace with no gravity must not acquire one.
      final narrow = _wristTrace(reps: 3, hz: 30, gravity: false, gyro: false)
          .resampled(hz: 50);
      expect(narrow.hasGravity, isFalse);
      expect(narrow.samples.every((s) => s.gx == null), isTrue);
    });

    test('the real profiles asset drives every family without throwing', () {
      // A smoke pass over the whole catalogue: no family's threshold
      // combination may crash the pipeline.
      final trace = _wristTrace(reps: 6);
      final seen = <String>{};

      for (final profile in RepProfileRegistry.instance.all) {
        if (!profile.isTrackable || !seen.add(profile.family!.id)) continue;
        expect(
          () => RepDetector.detectForProfile(trace, profile),
          returnsNormally,
          reason: profile.slug,
        );
      }

      expect(seen, isNotEmpty);
    });
  });
}

// ── synthetic trace builders ────────────────────────────────────────────────

/// A wrist-worn trace of a cyclic lift.
///
/// The three channels are driven independently so a test can make one strong
/// and another weak — which is exactly the situation a slow rep creates in
/// reality, and the situation the selector exists to resolve.
///
/// [tiltDegrees] is the peak forearm rotation; [linearAmplitude] the peak
/// linear acceleration in m/s². A real slow curl has a large first and a tiny
/// second.
MotionTrace _wristTrace({
  required int reps,
  int periodMs = 2500,
  double tiltDegrees = 60,
  double linearAmplitude = 3.0,
  int hz = 50,
  int leadInMs = 4000,
  int tailMs = 3000,
  bool gravity = true,
  bool gyro = true,
  bool flipped = false,
}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];
  const g = 9.81;
  final sign = flipped ? -1.0 : 1.0;
  var tMs = 0;

  MotionSample at(double phaseOrNull) {
    // phaseOrNull < 0 means "at rest": no rotation, no acceleration.
    final resting = phaseOrNull < 0;
    final angleRad =
        resting ? 0.0 : tiltDegrees * (pi / 180) * (1 - cos(phaseOrNull)) / 2;
    final accel = resting ? 0.0 : linearAmplitude * sin(phaseOrNull - pi / 2);

    // Gravity swings through `angleRad` in the device's x/y plane.
    final gxv = sign * g * sin(angleRad);
    final gyv = sign * g * cos(angleRad);

    // Angular velocity is the derivative of the angle; a scaled sine is close
    // enough for a synthetic trace and keeps the channel honestly periodic.
    final omega = resting
        ? 0.0
        : tiltDegrees * (pi / 180) * pi * sin(phaseOrNull) / (periodMs / 1000);

    return MotionSample(
      tMs,
      0,
      accel,
      0,
      gx: gravity ? gxv : null,
      gy: gravity ? gyv : null,
      gz: gravity ? 0.0 : null,
      rx: gyro ? 0.0 : null,
      ry: gyro ? 0.0 : null,
      rz: gyro ? sign * omega : null,
    );
  }

  for (; tMs < leadInMs; tMs += stepMs) {
    samples.add(at(-1));
  }
  for (var r = 0; r < reps; r++) {
    final cycleStart = tMs;
    while (tMs - cycleStart < periodMs) {
      samples.add(at(2 * pi * (tMs - cycleStart) / periodMs));
      tMs += stepMs;
    }
  }
  final tailEnd = tMs + tailMs;
  for (; tMs < tailEnd; tMs += stepMs) {
    samples.add(at(-1));
  }

  return MotionTrace(
    samples: samples,
    sensorType: MotionSensorType.linearAcceleration,
  );
}

/// ~1.1 Hz gait, carried in all three channels.
MotionTrace _walkingTrace({required int seconds, int hz = 50}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];
  const strideMs = 900;
  const g = 9.81;

  for (var tMs = 0; tMs < seconds * 1000; tMs += stepMs) {
    final phase = 2 * pi * tMs / strideMs;
    // A gentle arm swing: ~8 deg of tilt, well under any rep's arc.
    final angleRad = 8 * (pi / 180) * sin(phase);
    samples.add(
      MotionSample(
        tMs,
        0.48 * sin(phase * 0.5),
        1.2 * sin(phase),
        0.36 * cos(phase),
        gx: g * sin(angleRad),
        gy: g * cos(angleRad),
        gz: 0,
        rx: 0,
        ry: 0,
        rz: 8 * (pi / 180) * 2 * pi * cos(phase) / (strideMs / 1000),
      ),
    );
  }

  return MotionTrace(
    samples: samples,
    sensorType: MotionSensorType.linearAcceleration,
  );
}

/// Completely still, with aperiodic sensor noise.
///
/// Seeded, so a failure reproduces. It has to be genuinely aperiodic: a
/// product of two sinusoids is a *sum* of sinusoids and autocorrelates
/// perfectly well, which is not what "nothing repeats" means.
MotionTrace _stillTrace({required int seconds, int hz = 50}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];
  final rnd = Random(1337);
  const g = 9.81;

  for (var tMs = 0; tMs < seconds * 1000; tMs += stepMs) {
    double n() => (rnd.nextDouble() - 0.5) * 0.04;
    samples.add(
      MotionSample(tMs, n(), n(), n(),
          gx: n(), gy: g + n(), gz: n(), rx: n(), ry: n(), rz: n()),
    );
  }

  return MotionTrace(
    samples: samples,
    sensorType: MotionSensorType.linearAcceleration,
  );
}

/// A perfectly periodic but far-too-small oscillation — a hand tremor, a
/// breathing sway, a conversation during rest.
MotionTrace _tremorTrace({
  required int seconds,
  required int periodMs,
  required double degrees,
  int hz = 50,
}) {
  final stepMs = (1000 / hz).round();
  final samples = <MotionSample>[];
  const g = 9.81;

  for (var tMs = 0; tMs < seconds * 1000; tMs += stepMs) {
    final phase = 2 * pi * tMs / periodMs;
    final angleRad = degrees * (pi / 180) * sin(phase);
    samples.add(
      MotionSample(
        tMs,
        0,
        0.02 * sin(phase),
        0,
        gx: g * sin(angleRad),
        gy: g * cos(angleRad),
        gz: 0,
        rx: 0,
        ry: 0,
        rz: degrees * (pi / 180) * 2 * pi * cos(phase) / (periodMs / 1000),
      ),
    );
  }

  return MotionTrace(
    samples: samples,
    sensorType: MotionSensorType.linearAcceleration,
  );
}
