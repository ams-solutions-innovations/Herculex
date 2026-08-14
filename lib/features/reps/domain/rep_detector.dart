import 'dart:math';

import 'motion_sample.dart';
import 'rep_movement.dart';

/// Output of one detector run over one set's samples.
class RepDetectionResult {
  /// Number of accepted full trough-peak-trough cycles.
  final int repCount;

  /// Confidence in 0-1 for each accepted rep, in time order.
  final List<double> perRepConfidence;

  /// Set-level confidence in 0-1.
  final double setConfidence;

  /// Trough-to-trough duration of each accepted cycle, in time order.
  final List<int> cyclePeriodsMs;

  /// Symmetric excursion amplitude of each accepted cycle, in time order.
  final List<double> cycleAmplitudes;

  /// True when a gap of more than [RepDetectorConfig.missedRepGapFactor] times
  /// the median period sits between two accepted reps — i.e. a rep was almost
  /// certainly performed and not counted.
  final bool missedRepSuspected;

  const RepDetectionResult({
    required this.repCount,
    required this.perRepConfidence,
    required this.setConfidence,
    required this.cyclePeriodsMs,
    required this.cycleAmplitudes,
    required this.missedRepSuspected,
  });

  /// The result for a trace with nothing countable in it.
  static const RepDetectionResult empty = RepDetectionResult(
    repCount: 0,
    perRepConfidence: [],
    setConfidence: 0,
    cyclePeriodsMs: [],
    cycleAmplitudes: [],
    missedRepSuspected: false,
  );
}

/// Every tunable constant in the detection pipeline.
///
/// Nothing in [RepDetector] may use a bare numeric literal for a threshold. A
/// future tuning pass — against a larger fixture corpus — needs exactly one
/// place to touch, and per-movement differences need to be expressible without
/// forking the pipeline.
class RepDetectorConfig {
  /// Fixed grid every input is resampled onto before anything else happens.
  final int resampleHz;

  /// Width of the centred moving average subtracted from raw magnitude when
  /// the trace came from `TYPE_ACCELEROMETER` and still carries gravity.
  final int gravityWindowMs;

  /// Taps in the centred smoothing average. Odd, so it stays phase-neutral.
  final int smoothingTaps;

  /// Trailing window the smoothed magnitude is detrended against to produce
  /// the activity signal.
  final int detrendWindowMs;

  /// Trailing window the adaptive peak threshold is computed over.
  final int thresholdWindowMs;

  /// A candidate peak must exceed `mean + thresholdK * stddev` of the trailing
  /// activity signal.
  final double thresholdK;

  /// Both excursions of a cycle must reach this fraction of the running median
  /// cycle amplitude. This is the *symmetric* half of the false-positive
  /// defence: a bare peak is trivial to produce by accident, a matched
  /// rise-and-fall pair is not.
  final double amplitudeGateFraction;

  /// Absolute floor, in m/s², below which a cycle is never a rep no matter how
  /// it compares to its neighbours.
  ///
  /// Load-bearing for the noise fixtures. A purely relative gate is scale-free:
  /// in a trace containing nothing but walking, walking *is* the running
  /// median, so every step clears a relative gate. Only an absolute floor can
  /// make a walking trace count exactly zero. Mirrors the 2.5 m/s² floor the
  /// provisional Kotlin counter (10-03a) uses for the same reason.
  final double minCycleAmplitude;

  /// Refractory period: cycles shorter than this are rejected.
  final int minPeriodMs;

  /// Cycles longer than this are rejected.
  final int maxPeriodMs;

  /// Two candidate peaks closer together than
  /// `minPeriodMs * peakMergeFraction` are the same peak; the smaller is
  /// discarded.
  final double peakMergeFraction;

  /// How many leading candidate cycles seed the running median amplitude
  /// before any cycle has been accepted.
  final int amplitudeBootstrapCycles;

  /// Weight of the amplitude term in per-rep confidence; the period-regularity
  /// term takes the remainder.
  final double confidenceAmplitudeWeight;

  /// A rep at or above this confidence counts toward set confidence.
  final double perRepConfidenceFloor;

  /// An inter-rep gap wider than this many median periods means a rep was
  /// probably missed.
  final double missedRepGapFactor;

  /// Multiplier applied to set confidence per suspected missed rep. Below the
  /// per-rep floor by construction, so a set with a hole in it can never
  /// present as confident.
  final double missedRepPenalty;

  const RepDetectorConfig({
    this.resampleHz = 50,
    this.gravityWindowMs = 2000,
    this.smoothingTaps = 5,
    this.detrendWindowMs = 5000,
    this.thresholdWindowMs = 5000,
    this.thresholdK = 1.2,
    this.amplitudeGateFraction = 0.40,
    this.minCycleAmplitude = 2.5,
    this.minPeriodMs = 800,
    this.maxPeriodMs = 8000,
    this.peakMergeFraction = 0.5,
    this.amplitudeBootstrapCycles = 3,
    this.confidenceAmplitudeWeight = 0.5,
    this.perRepConfidenceFloor = 0.5,
    this.missedRepGapFactor = 2.0,
    this.missedRepPenalty = 0.4,
  });

  /// Pull-up family: a full hang-to-chin-to-hang cycle is slow.
  const RepDetectorConfig.pullUp()
      : this(minPeriodMs: 800, maxPeriodMs: 8000, minCycleAmplitude: 2.5);

  /// Dip family: shorter range of motion and a faster cadence, so the
  /// refractory floor has to come down or fast dips are silently dropped.
  const RepDetectorConfig.dip()
      : this(minPeriodMs: 600, maxPeriodMs: 6000, minCycleAmplitude: 2.0);

  factory RepDetectorConfig.forMovement(RepMovement m) => switch (m) {
        RepMovement.pullUp => const RepDetectorConfig.pullUp(),
        RepMovement.dip => const RepDetectorConfig.dip(),
      };

  RepDetectorConfig copyWith({
    int? resampleHz,
    int? gravityWindowMs,
    int? smoothingTaps,
    int? detrendWindowMs,
    int? thresholdWindowMs,
    double? thresholdK,
    double? amplitudeGateFraction,
    double? minCycleAmplitude,
    int? minPeriodMs,
    int? maxPeriodMs,
    double? peakMergeFraction,
    int? amplitudeBootstrapCycles,
    double? confidenceAmplitudeWeight,
    double? perRepConfidenceFloor,
    double? missedRepGapFactor,
    double? missedRepPenalty,
  }) =>
      RepDetectorConfig(
        resampleHz: resampleHz ?? this.resampleHz,
        gravityWindowMs: gravityWindowMs ?? this.gravityWindowMs,
        smoothingTaps: smoothingTaps ?? this.smoothingTaps,
        detrendWindowMs: detrendWindowMs ?? this.detrendWindowMs,
        thresholdWindowMs: thresholdWindowMs ?? this.thresholdWindowMs,
        thresholdK: thresholdK ?? this.thresholdK,
        amplitudeGateFraction:
            amplitudeGateFraction ?? this.amplitudeGateFraction,
        minCycleAmplitude: minCycleAmplitude ?? this.minCycleAmplitude,
        minPeriodMs: minPeriodMs ?? this.minPeriodMs,
        maxPeriodMs: maxPeriodMs ?? this.maxPeriodMs,
        peakMergeFraction: peakMergeFraction ?? this.peakMergeFraction,
        amplitudeBootstrapCycles:
            amplitudeBootstrapCycles ?? this.amplitudeBootstrapCycles,
        confidenceAmplitudeWeight:
            confidenceAmplitudeWeight ?? this.confidenceAmplitudeWeight,
        perRepConfidenceFloor:
            perRepConfidenceFloor ?? this.perRepConfidenceFloor,
        missedRepGapFactor: missedRepGapFactor ?? this.missedRepGapFactor,
        missedRepPenalty: missedRepPenalty ?? this.missedRepPenalty,
      );
}

/// The single authoritative rep-cycle detector.
///
/// Pure and synchronous: a [MotionTrace] in, a [RepDetectionResult] out. No
/// I/O, no plugins, no database, no Flutter — a sample value physically cannot
/// reach a file, a log or the network from this layer (T-10-07). The
/// provisional Kotlin counter on the watch is never authoritative; correctness
/// lives here and nowhere else.
///
/// Built out of primitives that are easy to reason about in a test — moving
/// averages, extrema, medians — rather than out of a filter-design library,
/// because a failing fixture has to be debuggable by reading the code.
class RepDetector {
  const RepDetector._();

  static RepDetectionResult detect(
    MotionTrace trace, {
    RepDetectorConfig config = const RepDetectorConfig.pullUp(),
  }) {
    // (0) The grid is not optional and no caller can bypass it: detect()
    // resamples its own input. This is what makes a 30 Hz trace and a 50 Hz
    // trace of the same set produce the same count.
    final t = trace.resampled(hz: config.resampleHz);
    if (t.samples.length < 3 || t.durationMs <= 0) {
      return RepDetectionResult.empty;
    }

    final n = t.samples.length;
    final stepMs = 1000.0 / config.resampleHz;
    int win(int ms) => max(1, (ms / stepMs).round());

    // (a) Magnitude, plus gravity removal for raw-accelerometer traces. The
    // two sensor types are not interchangeable; a raw trace sits on a ~9.81
    // pedestal that would swamp every excursion we care about.
    var signal = t.magnitudes();
    if (t.needsGravityRemoval) {
      signal = _subtract(signal, _centredMovingAverage(signal, win(config.gravityWindowMs)));
    }

    // (b) Smooth. Centred, so peak timing is not shifted.
    signal = _centredMovingAverage(signal, config.smoothingTaps);

    // (c) Detrend against a trailing average to get the activity signal.
    final activity =
        _subtract(signal, _trailingMovingAverage(signal, win(config.detrendWindowMs)));

    // (d) Adaptive threshold from the trailing mean and stddev of the activity
    // signal. A fixed threshold cannot survive both a light watch on a wrist
    // and a phone in a pocket.
    final threshold = _trailingThreshold(
      activity,
      win(config.thresholdWindowMs),
      config.thresholdK,
    );

    // Candidate peaks: every local maximum. Whether it clears its own local
    // threshold is recorded rather than used to filter here — see the
    // detect-then-track note on the acceptance loop below.
    var peaks = <int>[];
    for (var i = 1; i < n - 1; i++) {
      if (activity[i] >= activity[i - 1] && activity[i] > activity[i + 1]) {
        peaks.add(i);
      }
    }
    peaks = _mergeNearbyPeaks(
      peaks,
      activity,
      win((config.minPeriodMs * config.peakMergeFraction).round()),
    );
    if (peaks.isEmpty) return RepDetectionResult.empty;

    final supra = [for (final p in peaks) activity[p] > threshold[p]];
    // No peak anywhere clears the adaptive threshold: the trace contains no
    // excursion distinguishable from its own baseline. Nothing to count.
    if (!supra.contains(true)) return RepDetectionResult.empty;

    // (e) A rep is a *closed cycle*: trough, peak, trough. Counting bare peaks
    // is precisely what makes walking register as reps.
    final troughs = _troughsAround(peaks, activity);

    // Candidate cycles, before gating.
    final candAmp = <double>[];
    final candPeriod = <int>[];
    for (var k = 0; k < peaks.length; k++) {
      final pre = troughs[k];
      final post = troughs[k + 1];
      final rise = activity[peaks[k]] - activity[pre];
      final fall = activity[peaks[k]] - activity[post];
      // Symmetric: the weaker of the two excursions is the cycle amplitude, so
      // a big rise followed by a drift-out cannot pass as a rep.
      candAmp.add(min(rise, fall));
      candPeriod.add(t.samples[post].tMs - t.samples[pre].tMs);
    }

    // Bootstrap the running median from the leading *supra-threshold*
    // candidates, so the first rep of a set is gated against something rather
    // than waved through, and so baseline noise never seeds the median.
    final bootstrap = _median([
      for (var k = 0; k < peaks.length; k++)
        if (supra[k]) candAmp[k],
    ].take(config.amplitudeBootstrapCycles).toList());

    final acceptedAmp = <double>[];
    final acceptedPeriod = <int>[];
    final acceptedPeakTMs = <int>[];
    for (var k = 0; k < peaks.length; k++) {
      // Detect, then track. The adaptive threshold decides where a set
      // *starts*: until the rhythm is established, only a peak that clears
      // `mean + k*stddev` of its own trailing window can be a rep. After that
      // the running-median amplitude gate takes over, because a periodic
      // signal inflates the very stddev it is measured against — a strict
      // per-peak threshold systematically drops mid-set reps, and which ones
      // it drops depends on where the resample grid happens to land. That is
      // both a missed-rep bug and a violation of 30 Hz/50 Hz count invariance.
      if (!supra[k] && acceptedAmp.length < config.amplitudeBootstrapCycles) {
        continue;
      }
      final running =
          acceptedAmp.isEmpty ? bootstrap : _median(List.of(acceptedAmp));
      final gate = max(
        running * config.amplitudeGateFraction,
        config.minCycleAmplitude,
      );
      if (candAmp[k] < gate) continue;
      // (f) Refractory period.
      if (candPeriod[k] < config.minPeriodMs) continue;
      if (candPeriod[k] > config.maxPeriodMs) continue;

      acceptedAmp.add(candAmp[k]);
      acceptedPeriod.add(candPeriod[k]);
      acceptedPeakTMs.add(t.samples[peaks[k]].tMs);
    }

    if (acceptedAmp.isEmpty) return RepDetectionResult.empty;

    // (g) Per-rep confidence: amplitude against the set median, period
    // regularity against the running median period.
    final setMedianAmp = _median(List.of(acceptedAmp));
    final perRep = <double>[];
    for (var k = 0; k < acceptedAmp.length; k++) {
      final ampScore = setMedianAmp <= 0
          ? 0.0
          : (acceptedAmp[k] / setMedianAmp).clamp(0.0, 1.0).toDouble();
      final runningPeriod =
          _median(acceptedPeriod.take(k + 1).map((e) => e.toDouble()).toList());
      final periodScore = runningPeriod <= 0
          ? 0.0
          : (1 - (acceptedPeriod[k] - runningPeriod).abs() / runningPeriod)
              .clamp(0.0, 1.0)
              .toDouble();
      perRep.add(
        config.confidenceAmplitudeWeight * ampScore +
            (1 - config.confidenceAmplitudeWeight) * periodScore,
      );
    }

    // (h) Set confidence: how much of the set cleared the per-rep floor,
    // penalised once per suspected hole in the sequence.
    final medianPeriod =
        _median(acceptedPeriod.map((e) => e.toDouble()).toList());
    var gaps = 0;
    for (var k = 1; k < acceptedPeakTMs.length; k++) {
      final gap = acceptedPeakTMs[k] - acceptedPeakTMs[k - 1];
      if (medianPeriod > 0 && gap > config.missedRepGapFactor * medianPeriod) {
        gaps++;
      }
    }
    final cleared =
        perRep.where((c) => c >= config.perRepConfidenceFloor).length;
    var setConfidence = cleared / perRep.length;
    for (var i = 0; i < gaps; i++) {
      setConfidence *= config.missedRepPenalty;
    }

    return RepDetectionResult(
      repCount: acceptedAmp.length,
      perRepConfidence: List.unmodifiable(perRep),
      setConfidence: setConfidence.clamp(0.0, 1.0).toDouble(),
      cyclePeriodsMs: List.unmodifiable(acceptedPeriod),
      cycleAmplitudes: List.unmodifiable(acceptedAmp),
      missedRepSuspected: gaps > 0,
    );
  }

  // --- primitives -----------------------------------------------------------

  static List<double> _subtract(List<double> a, List<double> b) =>
      [for (var i = 0; i < a.length; i++) a[i] - b[i]];

  /// Centred moving average over [taps] samples, edge-clamped so the output is
  /// the same length as the input.
  static List<double> _centredMovingAverage(List<double> v, int taps) {
    if (taps <= 1 || v.length < 2) return List.of(v);
    final half = taps ~/ 2;
    final prefix = _prefixSum(v);
    return [
      for (var i = 0; i < v.length; i++)
        () {
          final lo = max(0, i - half);
          final hi = min(v.length - 1, i + half);
          return (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
        }(),
    ];
  }

  /// Trailing moving average over [window] samples, edge-clamped at the start.
  static List<double> _trailingMovingAverage(List<double> v, int window) {
    if (window <= 1 || v.length < 2) return List.of(v);
    final prefix = _prefixSum(v);
    return [
      for (var i = 0; i < v.length; i++)
        () {
          final lo = max(0, i - window + 1);
          return (prefix[i + 1] - prefix[lo]) / (i - lo + 1);
        }(),
    ];
  }

  /// `mean + k * stddev` of the trailing [window] samples, per index.
  static List<double> _trailingThreshold(
    List<double> v,
    int window,
    double k,
  ) {
    final prefix = _prefixSum(v);
    final prefixSq = _prefixSum([for (final x in v) x * x]);
    return [
      for (var i = 0; i < v.length; i++)
        () {
          final lo = max(0, i - window + 1);
          final count = i - lo + 1;
          final mean = (prefix[i + 1] - prefix[lo]) / count;
          final meanSq = (prefixSq[i + 1] - prefixSq[lo]) / count;
          final variance = max(0.0, meanSq - mean * mean);
          return mean + k * sqrt(variance);
        }(),
    ];
  }

  static List<double> _prefixSum(List<double> v) {
    final p = List<double>.filled(v.length + 1, 0);
    for (var i = 0; i < v.length; i++) {
      p[i + 1] = p[i] + v[i];
    }
    return p;
  }

  /// Collapse peaks closer together than [minGapSamples], keeping the taller.
  static List<int> _mergeNearbyPeaks(
    List<int> peaks,
    List<double> v,
    int minGapSamples,
  ) {
    if (peaks.length < 2 || minGapSamples <= 0) return peaks;
    final out = <int>[peaks.first];
    for (var i = 1; i < peaks.length; i++) {
      if (peaks[i] - out.last < minGapSamples) {
        if (v[peaks[i]] > v[out.last]) out[out.length - 1] = peaks[i];
      } else {
        out.add(peaks[i]);
      }
    }
    return out;
  }

  /// The `peaks.length + 1` troughs bracketing each peak: the minimum before
  /// the first peak, between each consecutive pair, and after the last.
  static List<int> _troughsAround(List<int> peaks, List<double> v) {
    final troughs = <int>[];
    troughs.add(_argMin(v, 0, peaks.first));
    for (var i = 1; i < peaks.length; i++) {
      troughs.add(_argMin(v, peaks[i - 1], peaks[i]));
    }
    troughs.add(_argMin(v, peaks.last, v.length - 1));
    return troughs;
  }

  static int _argMin(List<double> v, int from, int to) {
    var best = from;
    for (var i = from; i <= to && i < v.length; i++) {
      if (v[i] < v[best]) best = i;
    }
    return best;
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = List<double>.of(v)..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }
}
