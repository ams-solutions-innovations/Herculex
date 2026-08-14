// Deterministic synthetic motion-trace generator.
//
// SCOPE — read this before using the output for anything.
//
// This tool exists for **CI coverage of edge cases and regressions only**. It
// cannot substitute for recorded traces, and REP-06 says *recorded*.
//
// The reason is not procedural fussiness. A synthetic sine wave is exactly the
// signal any peak counter gets right: it has a constant period, a constant
// amplitude, no gravity leakage, no wrist rotation, no bar swing, no grip
// shuffle and no sensor dropout. Accuracy measured against a corpus of
// generated traces would be a measurement of the generator, not of the
// detector, and it would be uniformly excellent while telling you nothing
// about whether the app can count a real set of pull-ups.
//
// Every sidecar this tool writes therefore carries `"synthetic": true`, and
// `test/rep_fixture_provenance_test.dart` fails the build if a file carrying
// that flag is named in the accuracy-fixture list. Use these traces for
// determinism checks, resampling-invariance checks, degenerate-input checks
// and regression pinning. Nothing else.
//
// Usage:
//   dart run tool/synthesize_motion_trace.dart \
//     --reps 8 --period-ms 2000 --amplitude 3.0 --jitter 0.1 \
//     --noise-floor 0.05 --seed 42 --out build/tmp_trace.csv
//
// Options:
//   --reps N               rep cycles to synthesise (default 8)
//   --period-ms N          nominal cycle period in ms (default 2000)
//   --amplitude F          nominal peak acceleration, m/s^2 (default 3.0)
//   --jitter F             fractional per-cycle period/amplitude jitter (0.1)
//   --noise-floor F        gaussian noise stddev, m/s^2 (default 0.05)
//   --walking-segment-s N  seconds of walking-like noise appended (default 0)
//   --hz N                 emitted sample rate (default 50)
//   --seed N               RNG seed; identical args => identical bytes (42)
//   --out PATH             CSV output path; the sidecar replaces .csv with
//                          .json (default build/synthetic_trace.csv)
//   --movement S           pullUp | dip, written to the sidecar (pullUp)
//   --source S             wrist | phone, written to the sidecar (wrist)
//   --placement S          sidecar placement, or omitted for null
//   --sensor-type S        linear_acceleration | accelerometer
//   --description S        sidecar description
//
// CSV format (identical to the recorded corpus — see
// test/fixtures/motion/README.md):
//
//   t_ms,x,y,z
//   0,0.001234,-0.004321,0.000987
//
// t_ms is a monotonic millisecond timestamp from the start of capture; x, y
// and z are m/s^2.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Sentinel recording time for synthetic traces.
///
/// Fixed rather than `DateTime.now()` so a regenerated fixture is byte-identical
/// and never shows up as a spurious diff. A synthetic trace has no recording
/// time; this value is deliberately implausible as one.
const String _syntheticRecordedAt = '1970-01-01T00:00:00.000Z';

void main(List<String> argv) {
  final args = _parseArgs(argv);
  if (args.containsKey('help') || args.containsKey('h')) {
    stdout.writeln(_usage);
    return;
  }

  final reps = int.parse(args['reps'] ?? '8');
  final periodMs = int.parse(args['period-ms'] ?? '2000');
  final amplitude = double.parse(args['amplitude'] ?? '3.0');
  final jitter = double.parse(args['jitter'] ?? '0.1');
  final noiseFloor = double.parse(args['noise-floor'] ?? '0.05');
  final walkingS = int.parse(args['walking-segment-s'] ?? '0');
  final hz = int.parse(args['hz'] ?? '50');
  final seed = int.parse(args['seed'] ?? '42');
  final outPath = args['out'] ?? 'build/synthetic_trace.csv';
  final movement = args['movement'] ?? 'pullUp';
  final source = args['source'] ?? 'wrist';
  final placement = args['placement'];
  final sensorType = args['sensor-type'] ?? 'linear_acceleration';
  final description = args['description'] ??
      'synthetic $movement trace: $reps reps @ ${periodMs}ms, '
          'amplitude $amplitude, jitter $jitter, noise $noiseFloor, seed $seed';

  if (hz <= 0) throw ArgumentError('--hz must be positive');
  if (reps < 0) throw ArgumentError('--reps must not be negative');
  if (periodMs <= 0) throw ArgumentError('--period-ms must be positive');

  // Seeded RNG only. The same arguments must produce byte-identical output so
  // a regression fixture never flakes.
  final rnd = Random(seed);

  final rows = <List<num>>[];
  final stepMs = 1000 ~/ hz;

  // Leading rest so the detector's trailing windows have a baseline to learn.
  var tMs = 0;
  final leadInMs = 2000;
  for (; tMs < leadInMs; tMs += stepMs) {
    rows.add([tMs, ..._noise(rnd, noiseFloor)]);
  }

  // Rep cycles. Each cycle gets its own jittered period and amplitude, so the
  // trace is periodic but not metronomic.
  for (var r = 0; r < reps; r++) {
    final p = (periodMs * (1 + _uniform(rnd, jitter))).round().clamp(1, 1 << 30);
    final a = amplitude * (1 + _uniform(rnd, jitter));
    final cycleStart = tMs;
    while (tMs - cycleStart < p) {
      final phase = 2 * pi * (tMs - cycleStart) / p;
      // Vertical axis carries the rep; the other two carry noise only.
      final n = _noise(rnd, noiseFloor);
      rows.add([tMs, n[0], a * sin(phase) + n[1], n[2]]);
      tMs += stepMs;
    }
  }

  // Optional walking-like segment: ~1.1 Hz, low amplitude. Present so a
  // regression test can pin false-positive behaviour without waiting on the
  // recorded noise fixtures — it is NOT a substitute for them.
  final walkingEndMs = tMs + walkingS * 1000;
  const walkStepPeriodMs = 900;
  const walkAmplitude = 1.2;
  final walkStart = tMs;
  for (; tMs < walkingEndMs; tMs += stepMs) {
    final phase = 2 * pi * (tMs - walkStart) / walkStepPeriodMs;
    final n = _noise(rnd, noiseFloor);
    rows.add([
      tMs,
      walkAmplitude * 0.4 * sin(phase * 0.5) + n[0],
      walkAmplitude * sin(phase) + n[1],
      walkAmplitude * 0.3 * cos(phase) + n[2],
    ]);
  }

  // Trailing rest.
  final tailEndMs = tMs + 2000;
  for (; tMs < tailEndMs; tMs += stepMs) {
    rows.add([tMs, ..._noise(rnd, noiseFloor)]);
  }

  final csv = StringBuffer('t_ms,x,y,z\n');
  for (final row in rows) {
    csv.writeln(
      '${row[0]},${(row[1] as double).toStringAsFixed(6)},'
      '${(row[2] as double).toStringAsFixed(6)},'
      '${(row[3] as double).toStringAsFixed(6)}',
    );
  }

  final sidecar = <String, dynamic>{
    'repCount': reps,
    'movement': movement,
    'source': source,
    'placement': placement,
    'sensorType': sensorType,
    'description': description,
    'recordedBy': 'tool/synthesize_motion_trace.dart',
    'recordedAt': _syntheticRecordedAt,
    'deviceModel': null,
    // Load-bearing. test/rep_fixture_provenance_test.dart fails the build if a
    // file carrying this flag is listed as an accuracy fixture.
    'synthetic': true,
  };

  final csvFile = File(outPath);
  csvFile.parent.createSync(recursive: true);
  csvFile.writeAsStringSync(csv.toString());

  final jsonPath = outPath.endsWith('.csv')
      ? '${outPath.substring(0, outPath.length - 4)}.json'
      : '$outPath.json';
  File(jsonPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sidecar)}\n',
  );

  stdout.writeln('wrote ${rows.length} samples -> $outPath');
  stdout.writeln('wrote sidecar (synthetic: true) -> $jsonPath');
}

/// Three independent gaussian noise values with stddev [sigma].
List<double> _noise(Random rnd, double sigma) =>
    [for (var i = 0; i < 3; i++) _gaussian(rnd) * sigma];

/// Box-Muller, so the noise floor is gaussian rather than uniform — uniform
/// noise has hard bounds a threshold detector can exploit.
double _gaussian(Random rnd) {
  final u1 = 1 - rnd.nextDouble();
  final u2 = rnd.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}

/// Uniform in [-spread, spread].
double _uniform(Random rnd, double spread) => (rnd.nextDouble() * 2 - 1) * spread;

Map<String, String> _parseArgs(List<String> argv) {
  // Hand-rolled rather than package:args: this plan deliberately adds no
  // package-manager dependency (threat register T-10-SC).
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) continue;
    final key = a.substring(2);
    if (key == 'help' || key == 'h') {
      out[key] = 'true';
      continue;
    }
    if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) {
      out[key] = 'true';
    } else {
      out[key] = argv[++i];
    }
  }
  return out;
}

const String _usage = '''
Deterministic synthetic motion-trace generator (CI edge cases and regressions
ONLY — never an accuracy fixture; see the header comment).

  dart run tool/synthesize_motion_trace.dart --reps 8 --period-ms 2000 \\
    --amplitude 3.0 --jitter 0.1 --noise-floor 0.05 --seed 42 \\
    --out build/tmp_trace.csv

Options: --reps --period-ms --amplitude --jitter --noise-floor
         --walking-segment-s --hz --seed --out --movement --source
         --placement --sensor-type --description
''';
