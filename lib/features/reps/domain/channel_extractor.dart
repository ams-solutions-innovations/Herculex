import 'dart:math';

import 'motion_sample.dart';
import 'rep_tracking_profile.dart';

/// One derived, per-sample signal the detector can count cycles on, together
/// with the units its amplitudes are in.
class ExtractedChannel {
  const ExtractedChannel({
    required this.channel,
    required this.values,
    required this.isAngular,
  });

  final RepChannel channel;

  /// One value per sample of the trace it was extracted from.
  final List<double> values;

  /// True when [values] are in degrees, false when they are in m/s².
  ///
  /// Carried explicitly rather than inferred from [channel] because it decides
  /// which amplitude floor from the exercise's profile applies. Comparing a
  /// tilt amplitude in degrees against a m/s² floor is precisely the mistake
  /// that made a slow curl count as zero reps.
  final bool isAngular;
}

/// Turns a raw [MotionTrace] into the derived channels the detector counts on.
///
/// ## Why more than one channel
///
/// The original pipeline counted cycles on the magnitude of linear
/// acceleration and nothing else. For a pull-up that is the right signal: the
/// body translates fast enough that peak acceleration is several m/s². For
/// most gym work it is the wrong one, because linear acceleration amplitude
/// scales with the **square** of cadence — halve the tempo and the signal
/// drops fourfold. A deliberately slow biceps curl produces about
/// `A*w^2 = 0.25 * (2*pi/3)^2 ~= 1.1 m/s²` at the wrist, under any floor that
/// also keeps walking from counting as reps.
///
/// The orientation of the device does not have that problem. The forearm
/// still rotates through 60°+ whether the rep takes one second or six, so
/// [RepChannel.tilt] carries a full-amplitude cycle at any tempo. It is blind
/// to exactly one thing — rotation about the gravity axis, which leaves the
/// gravity direction unchanged — and that is what [RepChannel.rot] is for.
///
/// All three are extracted where the data allows; picking between them is
/// `channel_selector.dart`'s job, not this file's.
///
/// Pure and synchronous, like the detector: no I/O, no plugins, no Flutter.
class ChannelExtractor {
  const ChannelExtractor._();

  /// Extracts every channel [trace] carries the inputs for, in the order
  /// given by [preferred] where possible.
  ///
  /// Returns an empty list for a trace too short to derive anything from.
  /// A channel whose inputs are missing is simply absent — never a list of
  /// zeros, which would present to the selector as a real, perfectly flat
  /// signal and outrank a noisy but genuine one.
  static List<ExtractedChannel> extract(
    MotionTrace trace, {
    List<RepChannel> preferred = const [
      RepChannel.tilt,
      RepChannel.dyn,
      RepChannel.rot,
    ],
  }) {
    if (trace.samples.length < 3) return const [];

    final out = <ExtractedChannel>[];
    for (final channel in preferred) {
      final extracted = switch (channel) {
        RepChannel.tilt => _tilt(trace),
        RepChannel.dyn => _dyn(trace),
        RepChannel.rot => _rot(trace),
      };
      if (extracted != null) out.add(extracted);
    }
    return out;
  }

  /// Angle, in degrees, between each sample's gravity direction and the
  /// trace's median gravity direction.
  ///
  /// Referenced against the set's own median rather than against world "down"
  /// so the channel measures *how much the device turned during this set*,
  /// not how the user happened to be standing. A watch worn on the inside of
  /// the wrist and one worn on the outside produce the same curve.
  ///
  /// Falls back to low-passing the raw accelerometer when no `TYPE_GRAVITY`
  /// stream is present: at rest the accelerometer *is* the gravity vector, and
  /// a 0.5 Hz cutoff keeps that while rejecting the rep's own acceleration.
  /// It is a worse estimate under heavy movement, which is why the sensor type
  /// is recorded and calibration keys on it.
  static ExtractedChannel? _tilt(MotionTrace trace) {
    final n = trace.samples.length;
    List<List<double>>? vectors;

    if (trace.hasGravity) {
      vectors = [
        for (final s in trace.samples) [s.gx!, s.gy!, s.gz!],
      ];
    } else if (trace.sensorType == MotionSensorType.accelerometer) {
      // Only the raw accelerometer still contains gravity. A
      // linear_acceleration trace has had it removed by the platform's sensor
      // fusion and cannot get it back, so there is no tilt channel to offer.
      final hz = trace.meanHz;
      if (hz <= 0) return null;
      final window = max(3, (hz / 0.5).round());
      vectors = [
        _lowPass([for (final s in trace.samples) s.x], window),
        _lowPass([for (final s in trace.samples) s.y], window),
        _lowPass([for (final s in trace.samples) s.z], window),
      ];
      vectors = [
        for (var i = 0; i < n; i++)
          [vectors[0][i], vectors[1][i], vectors[2][i]],
      ];
    } else {
      return null;
    }

    final reference = _medianDirection(vectors);
    if (reference == null) return null;

    final degrees = <double>[];
    for (final v in vectors) {
      final norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
      if (norm <= 0) {
        degrees.add(0);
        continue;
      }
      final cosine =
          ((v[0] * reference[0] + v[1] * reference[1] + v[2] * reference[2]) /
                  norm)
              .clamp(-1.0, 1.0);
      degrees.add(acos(cosine) * 180 / pi);
    }

    return ExtractedChannel(
      channel: RepChannel.tilt,
      values: degrees,
      isAngular: true,
    );
  }

  /// Linear-acceleration magnitude, in m/s².
  ///
  /// This is the original pipeline's signal, unchanged in meaning: vector
  /// magnitude, with a gravity detrend first when the trace still sits on the
  /// ~9.81 m/s² pedestal.
  static ExtractedChannel? _dyn(MotionTrace trace) {
    var values = trace.magnitudes();
    if (trace.needsGravityRemoval) {
      final hz = trace.meanHz;
      if (hz <= 0) return null;
      final window = max(3, (hz * 2).round()); // ~2 s, as before
      values = [
        for (var i = 0; i < values.length; i++)
          values[i] - _lowPass(values, window)[i],
      ];
    }
    return ExtractedChannel(
      channel: RepChannel.dyn,
      values: values,
      isAngular: false,
    );
  }

  /// Angular-velocity magnitude converted to degrees per second.
  ///
  /// Reported in degrees rather than radians so it shares an amplitude floor
  /// with [RepChannel.tilt] — both are "how much did the device turn" measures
  /// and a profile carries one angular floor, not two.
  static ExtractedChannel? _rot(MotionTrace trace) {
    if (!trace.hasGyro) return null;
    const radToDeg = 180 / pi;
    return ExtractedChannel(
      channel: RepChannel.rot,
      values: [
        for (final s in trace.samples)
          sqrt(s.rx! * s.rx! + s.ry! * s.ry! + s.rz! * s.rz!) * radToDeg,
      ],
      isAngular: true,
    );
  }

  // ── primitives ────────────────────────────────────────────────────────────

  /// Centred moving average, edge-clamped so the output length matches the
  /// input. Centred rather than trailing so it introduces no phase shift —
  /// a lagged reference would smear the very peaks the detector times.
  static List<double> _lowPass(List<double> v, int window) {
    if (window <= 1 || v.length < 2) return List.of(v);
    final half = window ~/ 2;
    final prefix = List<double>.filled(v.length + 1, 0);
    for (var i = 0; i < v.length; i++) {
      prefix[i + 1] = prefix[i] + v[i];
    }
    return [
      for (var i = 0; i < v.length; i++)
        () {
          final lo = max(0, i - half);
          final hi = min(v.length - 1, i + half);
          return (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
        }(),
    ];
  }

  /// The per-axis median direction, normalised to a unit vector.
  ///
  /// A median rather than a mean: a set that starts or ends with the arm
  /// somewhere unusual (racking a bar, re-gripping) would drag a mean far
  /// enough to shift every angle in the set.
  static List<double>? _medianDirection(List<List<double>> vectors) {
    if (vectors.isEmpty) return null;
    final axis = <double>[];
    for (var k = 0; k < 3; k++) {
      final column = [for (final v in vectors) v[k]]..sort();
      final mid = column.length ~/ 2;
      axis.add(
        column.length.isOdd ? column[mid] : (column[mid - 1] + column[mid]) / 2,
      );
    }
    final norm = sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
    if (norm <= 0) return null;
    return [axis[0] / norm, axis[1] / norm, axis[2] / norm];
  }
}
