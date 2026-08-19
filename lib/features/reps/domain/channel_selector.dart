import 'dart:math';

import 'channel_extractor.dart';
import 'rep_tracking_profile.dart';

/// A scored candidate channel.
class ChannelScore {
  const ChannelScore({
    required this.channel,
    required this.periodicity,
    required this.dominantPeriodMs,
  });

  final ExtractedChannel channel;

  /// Strength of the strongest repeating structure in the signal, 0-1.
  final double periodicity;

  /// Lag, in ms, of the autocorrelation peak that produced [periodicity].
  final int dominantPeriodMs;
}

/// Picks which extracted channel the detector should count cycles on for one
/// set.
///
/// ## Why this is a per-set decision, not a per-exercise one
///
/// The exercise's profile says which channels are *plausible* — a curl is
/// `tilt`+`rot`, a pull-up is `dyn`. It cannot say which one actually carried
/// the signal this time, because that depends on how the set was performed: a
/// bench press ground out at 5 s per rep lives almost entirely in `tilt`,
/// while the same lift done explosively has a strong `dyn` component too. And
/// a watch that slid round the wrist mid-set degrades `tilt` without touching
/// `dyn`.
///
/// So the profile narrows the candidates and this picks between them, per set,
/// on evidence.
///
/// ## How
///
/// Each candidate is z-normalised — mandatory, since degrees and m/s² are not
/// comparable — and scored by the prominence of its strongest
/// autocorrelation peak within the plausible rep-period band. A signal that
/// repeats cleanly at some lag between [minPeriodMs] and [maxPeriodMs] scores
/// high; noise, drift and one-off events score near zero.
///
/// The selected channel is recorded on the suggestion, because a calibration
/// profile learned on `tilt` says nothing about a set measured on `dyn`.
class ChannelSelector {
  const ChannelSelector._();

  /// Scores every candidate and returns them best-first.
  ///
  /// [minPeriodMs] and [maxPeriodMs] come from the exercise's profile — the
  /// same refractory bounds the detector uses — so the search never reports a
  /// "period" no human rep could have.
  static List<ChannelScore> score(
    List<ExtractedChannel> candidates, {
    required int sampleRateHz,
    required int minPeriodMs,
    required int maxPeriodMs,
  }) {
    final scored = <ChannelScore>[];
    for (final candidate in candidates) {
      final normalised = _zNormalise(candidate.values);
      if (normalised == null) continue; // constant signal: nothing to find

      final minLag = max(1, (minPeriodMs * sampleRateHz / 1000).round());
      final maxLag = min(
        normalised.length ~/ 2,
        (maxPeriodMs * sampleRateHz / 1000).round(),
      );
      if (maxLag <= minLag) continue;

      var bestLag = minLag;
      var best = 0.0;
      for (var lag = minLag; lag <= maxLag; lag++) {
        final r = _autocorrelation(normalised, lag);
        if (r > best) {
          best = r;
          bestLag = lag;
        }
      }

      scored.add(
        ChannelScore(
          channel: candidate,
          periodicity: best.clamp(0.0, 1.0),
          dominantPeriodMs: (bestLag * 1000 / sampleRateHz).round(),
        ),
      );
    }

    scored.sort((a, b) => b.periodicity.compareTo(a.periodicity));
    return scored;
  }

  /// The best candidate, or null when none showed any repeating structure.
  ///
  /// Returning null rather than "the least bad option" is deliberate. A set
  /// with no periodic signal in any channel is a set the tracker could not
  /// measure, and the honest output for that is the manual state with a stated
  /// reason — not a rep count derived from whichever noise floor happened to
  /// score highest.
  static ChannelScore? select(
    List<ExtractedChannel> candidates, {
    required int sampleRateHz,
    required int minPeriodMs,
    required int maxPeriodMs,
    double minPeriodicity = 0.25,
  }) {
    final scored = score(
      candidates,
      sampleRateHz: sampleRateHz,
      minPeriodMs: minPeriodMs,
      maxPeriodMs: maxPeriodMs,
    );
    if (scored.isEmpty) return null;
    return scored.first.periodicity >= minPeriodicity ? scored.first : null;
  }

  /// Narrows [available] to the channels an exercise's profile allows, in the
  /// profile's own preference order.
  ///
  /// The profile is a filter, never a source: a channel the trace does not
  /// carry cannot be conjured by listing it, and a channel the trace carries
  /// but the profile excludes is dropped. A shrug lists `tilt`+`rot` because
  /// its `dyn` signal is a tenth of a pull-up's — counting it there would let
  /// a bump register as a rep.
  static List<ExtractedChannel> allowedBy(
    RepTrackingProfile profile,
    List<ExtractedChannel> available,
  ) =>
      [
        for (final wanted in profile.channels)
          ...available.where((c) => c.channel == wanted),
      ];

  // ── primitives ────────────────────────────────────────────────────────────

  /// Zero mean, unit standard deviation. Null for a constant signal, whose
  /// standard deviation is zero and which has no structure to normalise.
  static List<double>? _zNormalise(List<double> v) {
    if (v.length < 4) return null;
    final mean = v.reduce((a, b) => a + b) / v.length;
    var variance = 0.0;
    for (final x in v) {
      variance += (x - mean) * (x - mean);
    }
    variance /= v.length;
    final sd = sqrt(variance);
    if (sd <= 1e-9) return null;
    return [for (final x in v) (x - mean) / sd];
  }

  /// Normalised autocorrelation of an already z-normalised signal at [lag].
  ///
  /// Divided by the overlap length rather than the full length, so a long lag
  /// is not penalised simply for having fewer terms to sum.
  static double _autocorrelation(List<double> v, int lag) {
    final overlap = v.length - lag;
    if (overlap <= 0) return 0;
    var sum = 0.0;
    for (var i = 0; i < overlap; i++) {
      sum += v[i] * v[i + lag];
    }
    return sum / overlap;
  }
}
