import 'dart:math';

/// One tri-axial accelerometer reading.
///
/// [tMs] is a monotonic millisecond timestamp relative to the start of capture
/// (or any fixed epoch — only differences are ever used). [x], [y] and [z] are
/// in m/s². Whether gravity has already been removed is a property of the
/// enclosing [MotionTrace.sensorType], not of the sample.
class MotionSample {
  final int tMs;
  final double x;
  final double y;
  final double z;

  const MotionSample(this.tMs, this.x, this.y, this.z);

  @override
  String toString() => 'MotionSample($tMs, $x, $y, $z)';

  @override
  bool operator ==(Object other) =>
      other is MotionSample &&
      other.tMs == tMs &&
      other.x == x &&
      other.y == y &&
      other.z == z;

  @override
  int get hashCode => Object.hash(tMs, x, y, z);
}

/// Sensor type a trace was captured from.
///
/// These are not interchangeable: `linear_acceleration` has gravity removed by
/// the platform sensor fusion, `accelerometer` does not. The detector
/// high-pass-detrends the latter before doing anything else, and the
/// calibration profile keys on it, so a trace must always carry which one it
/// came from.
class MotionSensorType {
  static const String linearAcceleration = 'linear_acceleration';
  static const String accelerometer = 'accelerometer';

  const MotionSensorType._();
}

/// A time-ordered run of [MotionSample]s from one capture.
///
/// The important member here is [resampled]. Live capture arrives at whatever
/// cadence `SENSOR_DELAY_GAME` happens to deliver (jittery, ~40-60 Hz, with
/// gaps), while a fixture CSV is whatever it was recorded at. Putting every
/// input through the same fixed-grid interpolation before detection is what
/// makes a fixture test meaningful: detector correctness must never depend on
/// delivery rate.
class MotionTrace {
  /// Time-ordered samples. May be empty.
  final List<MotionSample> samples;

  /// `linear_acceleration` | `accelerometer` — see [MotionSensorType].
  final String sensorType;

  const MotionTrace({
    required this.samples,
    required this.sensorType,
  });

  /// True when this trace still contains the gravity vector and needs
  /// detrending before magnitude is meaningful.
  bool get needsGravityRemoval => sensorType == MotionSensorType.accelerometer;

  /// Span in milliseconds from the first to the last sample; 0 when empty or
  /// single-sampled.
  int get durationMs =>
      samples.length < 2 ? 0 : samples.last.tMs - samples.first.tMs;

  /// Effective mean sample rate of the *raw* trace, in Hz. 0 when undefined.
  double get meanHz =>
      durationMs <= 0 ? 0 : (samples.length - 1) * 1000.0 / durationMs;

  /// Linearly interpolate every axis onto a fixed `1000 / hz` ms grid spanning
  /// `samples.first.tMs` to `samples.last.tMs`, preserving [sensorType].
  ///
  /// Degenerate inputs are returned unchanged rather than throwing: an empty
  /// trace has no grid to build, and a single sample has no interval to divide
  /// by. Callers pass raw capture output here without pre-validating it.
  MotionTrace resampled({int hz = 50}) {
    if (hz <= 0) {
      throw ArgumentError.value(hz, 'hz', 'must be positive');
    }
    if (samples.length < 2) {
      return this;
    }

    final stepMs = 1000 / hz;
    final startMs = samples.first.tMs;
    final endMs = samples.last.tMs;
    if (endMs <= startMs) {
      // Degenerate or non-advancing timestamps — nothing to interpolate onto.
      return this;
    }

    final gridCount = ((endMs - startMs) / stepMs).floor() + 1;
    final out = <MotionSample>[];

    // Single forward sweep: `lo` is the index of the last raw sample at or
    // before the current grid time, so the whole resample is O(n + m).
    var lo = 0;
    for (var i = 0; i < gridCount; i++) {
      final t = startMs + i * stepMs;
      while (lo + 2 < samples.length && samples[lo + 1].tMs <= t) {
        lo++;
      }
      final a = samples[lo];
      final b = samples[lo + 1];
      final span = (b.tMs - a.tMs).toDouble();
      // Duplicate timestamps collapse to the earlier sample rather than
      // dividing by zero.
      final f = span <= 0 ? 0.0 : ((t - a.tMs) / span).clamp(0.0, 1.0);
      out.add(
        MotionSample(
          t.round(),
          a.x + (b.x - a.x) * f,
          a.y + (b.y - a.y) * f,
          a.z + (b.z - a.z) * f,
        ),
      );
    }

    return MotionTrace(samples: out, sensorType: sensorType);
  }

  /// Per-sample vector magnitude `sqrt(x² + y² + z²)`.
  List<double> magnitudes() => [
        for (final s in samples) sqrt(s.x * s.x + s.y * s.y + s.z * s.z),
      ];

  /// Parse a `t_ms,x,y,z` CSV body (the fixture corpus format). A leading
  /// header row is tolerated; blank lines are skipped.
  static MotionTrace fromCsv(String csv, {required String sensorType}) {
    final samples = <MotionSample>[];
    for (final rawLine in csv.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 4) continue;
      final tMs = int.tryParse(parts[0].trim());
      if (tMs == null) continue; // header row
      final x = double.tryParse(parts[1].trim());
      final y = double.tryParse(parts[2].trim());
      final z = double.tryParse(parts[3].trim());
      if (x == null || y == null || z == null) continue;
      samples.add(MotionSample(tMs, x, y, z));
    }
    return MotionTrace(samples: samples, sensorType: sensorType);
  }

  /// Serialise back to the `t_ms,x,y,z` CSV body, header included.
  String toCsv() {
    final b = StringBuffer('t_ms,x,y,z\n');
    for (final s in samples) {
      b.writeln(
        '${s.tMs},${s.x.toStringAsFixed(6)},'
        '${s.y.toStringAsFixed(6)},${s.z.toStringAsFixed(6)}',
      );
    }
    return b.toString();
  }
}
