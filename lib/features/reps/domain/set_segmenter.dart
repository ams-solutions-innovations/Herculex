import 'dart:math';

import 'channel_extractor.dart';
import 'motion_sample.dart';
import 'rep_tracking_profile.dart';

/// One candidate working period found inside a continuous capture.
class SetWindow {
  const SetWindow({
    required this.startMs,
    required this.endMs,
    required this.peakEnvelope,
  });

  /// Bounds in the same timebase as the trace's sample timestamps.
  final int startMs;
  final int endMs;

  /// Highest envelope value inside the window — a coarse "how vigorous was
  /// this" measure the caller can use to rank windows when more were found
  /// than sets were logged.
  final double peakEnvelope;

  int get durationMs => endMs - startMs;

  @override
  String toString() => 'SetWindow($startMs..$endMs, peak=$peakEnvelope)';
}

/// Tunables for [SetSegmenter]. Same rule as the detector: no bare numeric
/// literal for a threshold anywhere in the algorithm.
class SetSegmenterConfig {
  const SetSegmenterConfig({
    this.envelopeWindowMs = 2000,
    this.baselineWindowMs = 30000,
    this.enterK = 2.5,
    this.exitK = 1.0,
    this.exitPeakFraction = 0.25,
    this.minSustainedMs = 3000,
    this.minRestMs = 4000,
    this.minSetMs = 6000,
    this.maxSetMs = 300000,
    this.paddingMs = 1500,
  });

  /// Width of the RMS envelope. Wide enough to span a full rep so the
  /// envelope does not dip to baseline between reps and split one set into
  /// many, narrow enough to find the set's edges.
  final int envelopeWindowMs;

  /// Trailing window the resting baseline is estimated over.
  final int baselineWindowMs;

  /// Envelope must exceed `baseline + enterK * sigma` to open a set.
  final double enterK;

  /// ...and fall below `baseline + exitK * sigma` to close one. Deliberately
  /// lower than [enterK]: equal thresholds chatter, opening and closing a set
  /// on every fluctuation around a single line.
  final double exitK;

  /// A set also closes once the envelope drops below this fraction of the
  /// set's own peak, whichever threshold is higher.
  ///
  /// Without this the exit threshold is pinned just above a very quiet resting
  /// floor, and the margin between "resting" and "just above resting" is
  /// smaller than the resting noise itself — so a set that has plainly ended
  /// keeps failing the exit test and runs to the end of the capture. Judging
  /// the end of a set against how vigorous *that set* was is both more robust
  /// and closer to what the boundary actually means.
  final double exitPeakFraction;

  /// The above-threshold condition must hold this long before a set opens.
  /// One rep's worth of movement is not a set, and this is what stops racking
  /// a bar or walking to the rack from registering as one.
  final int minSustainedMs;

  /// The below-threshold condition must hold this long before a set closes.
  /// Must exceed the longest pause *within* a set — a grinding final rep can
  /// sit near-still at the sticking point for two or three seconds.
  final int minRestMs;

  /// Windows whose unpadded span is shorter than this are discarded. Three
  /// reps at a normal tempo is already ~7.5 s, so anything under six seconds
  /// is a burst of movement rather than a set.
  final int minSetMs;

  /// Windows longer than this are discarded: no set runs five minutes, so
  /// something else produced the signal.
  final int maxSetMs;

  /// Each accepted window is widened by this much at both ends, because the
  /// envelope's own width means it crosses the threshold slightly after the
  /// first rep begins and slightly before the last one ends.
  final int paddingMs;
}

/// Finds the working periods inside a continuous capture.
///
/// ## Why this exists
///
/// Capture used to be bracketed by an explicit tap per set. That is the right
/// design when tracking is opt-in per exercise, and the wrong one when it is a
/// single global setting: twenty sets means twenty extra taps, which is worse
/// than typing the number that was being avoided.
///
/// So the sensor runs for the whole workout and this splits the stream into
/// candidate sets. The split is the part that has to be right — a missed
/// boundary silently merges two sets into one over-count, and a spurious one
/// proposes a set that never happened.
///
/// ## The prior that makes this tractable
///
/// Blind segmentation of continuous accelerometry is hard. This is not blind:
/// the app already knows which exercise is selected and when a rest timer is
/// running, so [constrainTo] narrows candidates to periods the app believes
/// were working periods anyway. The envelope finds the edges; the app's own
/// state decides which windows are plausible. Neither alone is enough — the
/// app's timers are user-driven and drift, and the envelope alone cannot tell
/// a set from carrying plates back to the rack.
///
/// Pure and synchronous, like the rest of this layer.
class SetSegmenter {
  const SetSegmenter._();

  /// Segments [trace] into candidate working periods.
  ///
  /// Runs on the dynamic channel regardless of which channel the *detector*
  /// will later count on. Segmentation asks "was the body moving", which
  /// linear acceleration answers well at any tempo — its weakness is
  /// resolving individual slow reps, not noticing that work is happening.
  static List<SetWindow> segment(
    MotionTrace trace, {
    SetSegmenterConfig config = const SetSegmenterConfig(),
  }) {
    if (trace.samples.length < 3) return const [];

    final dyn = ChannelExtractor.extract(trace, preferred: const [RepChannel.dyn]);
    if (dyn.isEmpty) return const [];

    final values = dyn.first.values;
    final times = [for (final s in trace.samples) s.tMs];
    final hz = trace.meanHz;
    if (hz <= 0) return const [];

    int win(int ms) => max(1, (ms * hz / 1000).round());

    final envelope = _rmsEnvelope(values, win(config.envelopeWindowMs));

    // The resting baseline is estimated from **rest only**, and is frozen for
    // the duration of a set.
    //
    // Both halves of that are load-bearing, and getting either wrong breaks
    // segmentation in a way that looks like a threshold-tuning problem and is
    // not. A plain trailing mean over the last 30 s fills up with the set's
    // own data once the set has run that long, which lifts the exit threshold
    // above the signal and closes the set while the user is still lifting —
    // long sets get truncated and very long ones get split. And letting the
    // previous set's data linger in the baseline during the following rest
    // raises the entry threshold enough to miss the start of the next set.
    //
    // This is the same failure the detector documents at its acceptance loop:
    // a periodic signal inflates the very statistic it is being measured
    // against. The fix there is to stop adapting once the rhythm is
    // established; the fix here is to stop adapting once the set is open.
    final restEnvelope = _RestingBaseline(capacity: win(config.baselineWindowMs));

    final windows = <SetWindow>[];
    var inSet = false;
    var candidateStart = 0;
    var aboveSince = -1;
    var belowSince = -1;
    var peak = 0.0;
    var frozenFloor = 0.0;

    for (var i = 0; i < envelope.length; i++) {
      if (!inSet) {
        // Only rest feeds the baseline. A sample above the entry threshold is
        // provisionally work and is withheld, so a set that is building does
        // not raise the bar it has to clear.
        final enter = restEnvelope.mean + config.enterK * restEnvelope.stdDev;
        if (restEnvelope.isWarm && envelope[i] > enter) {
          if (aboveSince < 0) aboveSince = i;
          if (times[i] - times[aboveSince] >= config.minSustainedMs) {
            inSet = true;
            candidateStart = aboveSince;
            belowSince = -1;
            peak = envelope[i];
            // Captured from the pre-set resting statistics and held until the
            // set closes.
            frozenFloor =
                restEnvelope.mean + config.exitK * restEnvelope.stdDev;
          }
        } else {
          aboveSince = -1;
          restEnvelope.add(envelope[i]);
        }
      } else {
        peak = max(peak, envelope[i]);
        final exit = max(frozenFloor, config.exitPeakFraction * peak);
        if (envelope[i] < exit) {
          if (belowSince < 0) belowSince = i;
          if (times[i] - times[belowSince] >= config.minRestMs) {
            _close(windows, times, candidateStart, belowSince, peak, config);
            inSet = false;
            aboveSince = -1;
            belowSince = -1;
          }
        } else {
          belowSince = -1;
        }
      }
    }

    // A capture that ends mid-set still yields that set — the user stopped
    // the workout on their last rep, which is the common case, not an error.
    if (inSet) {
      _close(
        windows,
        times,
        candidateStart,
        belowSince >= 0 ? belowSince : envelope.length - 1,
        peak,
        config,
      );
    }

    return windows;
  }

  /// Keeps only the windows that overlap a period the app believed was a
  /// working set, and merges a window split across two constraints.
  ///
  /// [constraints] are `(startMs, endMs)` pairs from the app's own set/rest
  /// state. A window matching no constraint is dropped: the envelope found
  /// motion the app has no set for, which is someone walking, re-racking or
  /// adjusting a machine.
  static List<SetWindow> constrainTo(
    List<SetWindow> windows,
    List<(int, int)> constraints,
  ) {
    if (constraints.isEmpty) return windows;
    return [
      for (final w in windows)
        if (constraints.any((c) => w.startMs < c.$2 && w.endMs > c.$1)) w,
    ];
  }

  static void _close(
    List<SetWindow> out,
    List<int> times,
    int startIndex,
    int endIndex,
    double peak,
    SetSegmenterConfig config,
  ) {
    // Length is judged on the *unpadded* span. Padding exists to widen an
    // accepted window so it does not clip the first and last rep; letting it
    // count toward the minimum would let a two-second burst pad itself up to
    // the length of a real set.
    final duration = times[endIndex] - times[startIndex];
    if (duration < config.minSetMs || duration > config.maxSetMs) return;
    out.add(
      SetWindow(
        startMs: times[startIndex] - config.paddingMs,
        endMs: times[endIndex] + config.paddingMs,
        peakEnvelope: peak,
      ),
    );
  }

  // ── primitives ────────────────────────────────────────────────────────────

  /// Centred RMS over [window] samples. Centred so a window's edges are not
  /// pushed later than the motion that produced them.
  static List<double> _rmsEnvelope(List<double> v, int window) {
    final half = max(1, window ~/ 2);
    final squares = [for (final x in v) x * x];
    final prefix = _prefixSum(squares);
    return [
      for (var i = 0; i < v.length; i++)
        () {
          final lo = max(0, i - half);
          final hi = min(v.length - 1, i + half);
          return sqrt((prefix[hi + 1] - prefix[lo]) / (hi - lo + 1));
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
}

/// Running mean and standard deviation over the most recent rest-classified
/// envelope values.
///
/// A fixed-capacity ring rather than a full history: a gym's noise floor
/// changes over a session (a different machine, a different surface), and a
/// baseline averaged over the whole workout would lag it.
class _RestingBaseline {
  _RestingBaseline({required this.capacity});

  final int capacity;
  final _values = <double>[];

  /// True once enough rest has been observed to trust the statistics. Before
  /// this, no set may open — a capture that begins mid-set has no resting
  /// reference and would otherwise compare the set against itself.
  bool get isWarm => _values.length >= max(2, capacity ~/ 10);

  double get mean =>
      _values.isEmpty ? 0 : _values.reduce((a, b) => a + b) / _values.length;

  double get stdDev {
    if (_values.length < 2) return 0;
    final m = mean;
    var sum = 0.0;
    for (final v in _values) {
      sum += (v - m) * (v - m);
    }
    return sqrt(sum / _values.length);
  }

  void add(double value) {
    _values.add(value);
    if (_values.length > capacity) _values.removeAt(0);
  }
}
