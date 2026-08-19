import 'dart:math';

/// One synchronised inertial reading.
///
/// [tMs] is a monotonic millisecond timestamp relative to the start of capture
/// (or any fixed epoch — only differences are ever used). [x], [y] and [z] are
/// in m/s². Whether gravity has already been removed is a property of the
/// enclosing [MotionTrace.sensorType], not of the sample.
///
/// The gravity and gyroscope axes are **optional and default to null**, so
/// every existing three-axis call site and every recorded fixture still
/// constructs a valid sample. A null channel is absent, not zero: zero is a
/// legitimate reading and would present as "device perfectly level" or "no
/// rotation" rather than "we did not measure this".
class MotionSample {
  final int tMs;
  final double x;
  final double y;
  final double z;

  /// Gravity direction in device frame, m/s², from `TYPE_GRAVITY`.
  ///
  /// This is what makes a slow rep countable at all. A 3-second biceps curl
  /// peaks near 1.1 m/s² of linear acceleration at the wrist — under any
  /// amplitude floor that also keeps walking at zero — but rotates the forearm
  /// through 60°+, which this vector tracks regardless of how slowly it
  /// happens. Amplitude in the linear channel scales with the square of
  /// cadence; amplitude here does not scale with cadence at all.
  final double? gx;
  final double? gy;
  final double? gz;

  /// Angular velocity in device frame, rad/s, from `TYPE_GYROSCOPE`.
  ///
  /// Carries rotation about the gravity axis, which the gravity vector cannot
  /// see — a seated torso rotation changes the gyro reading and leaves the
  /// gravity direction untouched.
  final double? rx;
  final double? ry;
  final double? rz;

  const MotionSample(
    this.tMs,
    this.x,
    this.y,
    this.z, {
    this.gx,
    this.gy,
    this.gz,
    this.rx,
    this.ry,
    this.rz,
  });

  /// True when this sample carries a usable gravity vector.
  bool get hasGravity => gx != null && gy != null && gz != null;

  /// True when this sample carries a usable angular velocity.
  bool get hasGyro => rx != null && ry != null && rz != null;

  @override
  String toString() => 'MotionSample($tMs, $x, $y, $z'
      '${hasGravity ? ', g=($gx, $gy, $gz)' : ''}'
      '${hasGyro ? ', r=($rx, $ry, $rz)' : ''})';

  @override
  bool operator ==(Object other) =>
      other is MotionSample &&
      other.tMs == tMs &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.gx == gx &&
      other.gy == gy &&
      other.gz == gz &&
      other.rx == rx &&
      other.ry == ry &&
      other.rz == rz;

  @override
  int get hashCode => Object.hash(tMs, x, y, z, gx, gy, gz, rx, ry, rz);
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
      // An axis is interpolated only when *both* bracketing samples carry it.
      // Interpolating from a null toward a value would invent a reading, and
      // an invented gravity direction is indistinguishable from a real one
      // downstream.
      double? lerp(double? from, double? to) =>
          (from == null || to == null) ? null : from + (to - from) * f;
      out.add(
        MotionSample(
          t.round(),
          a.x + (b.x - a.x) * f,
          a.y + (b.y - a.y) * f,
          a.z + (b.z - a.z) * f,
          gx: lerp(a.gx, b.gx),
          gy: lerp(a.gy, b.gy),
          gz: lerp(a.gz, b.gz),
          rx: lerp(a.rx, b.rx),
          ry: lerp(a.ry, b.ry),
          rz: lerp(a.rz, b.rz),
        ),
      );
    }

    return MotionTrace(samples: out, sensorType: sensorType);
  }

  /// Per-sample vector magnitude `sqrt(x² + y² + z²)`.
  List<double> magnitudes() => [
        for (final s in samples) sqrt(s.x * s.x + s.y * s.y + s.z * s.z),
      ];

  /// Parse a fixture-corpus CSV body. A leading header row is tolerated;
  /// blank lines are skipped.
  ///
  /// Two column layouts are accepted, and the narrow one is not deprecated:
  ///
  ///   * `t_ms,x,y,z` — the original three-axis format. Every trace recorded
  ///     before the gravity and gyroscope channels existed is in this shape
  ///     and must keep parsing, so the extra axes come back null and the
  ///     detector simply has fewer channels to choose between.
  ///   * `t_ms,x,y,z,gx,gy,gz,rx,ry,rz` — the full layout.
  ///
  /// A row is read by position and truncated rows keep whatever they carry, so
  /// a `t_ms,x,y,z,gx,gy,gz` trace (gravity but no gyro) is also valid.
  static MotionTrace fromCsv(String csv, {required String sensorType}) {
    final samples = <MotionSample>[];
    for (final rawLine in csv.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 4) continue;
      final tMs = int.tryParse(parts[0].trim());
      if (tMs == null) continue; // header row
      double? at(int i) =>
          i < parts.length ? double.tryParse(parts[i].trim()) : null;
      final x = at(1);
      final y = at(2);
      final z = at(3);
      if (x == null || y == null || z == null) continue;
      samples.add(
        MotionSample(
          tMs, x, y, z,
          gx: at(4), gy: at(5), gz: at(6),
          rx: at(7), ry: at(8), rz: at(9),
        ),
      );
    }
    return MotionTrace(samples: samples, sensorType: sensorType);
  }

  /// True when every sample carries a gravity vector.
  bool get hasGravity => samples.isNotEmpty && samples.every((s) => s.hasGravity);

  /// True when every sample carries an angular velocity.
  bool get hasGyro => samples.isNotEmpty && samples.every((s) => s.hasGyro);

  /// Serialise back to CSV, header included.
  ///
  /// Emits the narrow `t_ms,x,y,z` layout when the trace carries no extra
  /// axes, so a three-axis trace round-trips byte-identically and an existing
  /// fixture does not show up as a spurious diff after a re-save.
  String toCsv() {
    final wide = samples.any((s) => s.hasGravity || s.hasGyro);
    if (!wide) {
      final b = StringBuffer('t_ms,x,y,z\n');
      for (final s in samples) {
        b.writeln(
          '${s.tMs},${s.x.toStringAsFixed(6)},'
          '${s.y.toStringAsFixed(6)},${s.z.toStringAsFixed(6)}',
        );
      }
      return b.toString();
    }

    String f(double? v) => v == null ? '' : v.toStringAsFixed(6);
    final b = StringBuffer('t_ms,x,y,z,gx,gy,gz,rx,ry,rz\n');
    for (final s in samples) {
      b.writeln(
        '${s.tMs},${f(s.x)},${f(s.y)},${f(s.z)},'
        '${f(s.gx)},${f(s.gy)},${f(s.gz)},'
        '${f(s.rx)},${f(s.ry)},${f(s.rz)}',
      );
    }
    return b.toString();
  }
}
