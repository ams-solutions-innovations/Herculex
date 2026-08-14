import 'package:flutter/foundation.dart';

import 'rep_features.dart';
import 'rep_movement.dart';

/// The single state every rep-tracking surface renders from (10-CONTEXT
/// "Confidence and fallback states"). Exactly five values — no more, no
/// fewer — and `countOnly`/`manual` are **not** error states; nothing that
/// touches this enum may style or describe them as failures.
///
///  * [disabled] — no consent, or the exercise is not opted in. Nothing shown.
///  * [ready] — eligible, consent given, sensor available. "Start tracking".
///  * [tracking] — capture running. Live count + confidence bar.
///  * [countOnly] — low confidence, placement changed, or calibration
///    insufficient. Count proposed, no RPE.
///  * [manual] — sensor unavailable, disconnected, battery gate, or capture
///    aborted. Today's manual entry, plus the stated reason.
enum TrackerState { disabled, ready, tracking, countOnly, manual }

/// Ordered confidence band a [RepSuggestion] is shown at.
///
/// Ordered `high` -> `medium` -> `low`; [lowerByOne] steps down exactly one
/// rung and saturates at [low] rather than wrapping, so repeated penalties
/// (there is currently only one — the provisional-disagreement rule — but
/// the saturation makes composing a second one safe later) can never cycle
/// back to [high].
enum ConfidenceBand { high, medium, low }

/// Steps a [ConfidenceBand] down exactly one rung, saturating at [low].
extension ConfidenceBandStep on ConfidenceBand {
  ConfidenceBand lowerByOne() {
    switch (this) {
      case ConfidenceBand.high:
        return ConfidenceBand.medium;
      case ConfidenceBand.medium:
      case ConfidenceBand.low:
        return ConfidenceBand.low;
    }
  }
}

/// The immutable, terminal output of one capture: what the review sheet
/// proposes and what 10-05's calibration path consumes.
///
/// **`proposedReps` is authoritative — always [RepDetectionResult.repCount]
/// (via `RepDetector.detect`).** `provisionalCount` is the non-authoritative
/// watch count: display/diagnostic only, never used to compute
/// `proposedReps`, never averaged with it (10-CONTEXT "Where detection
/// runs"). That invariant is the contract 10-04 relies on when it renders
/// the disagreement notice.
@immutable
class RepSuggestion {
  final String captureId;
  final String exerciseSlug;
  final RepMovement movement;

  /// `'wrist'` | `'phone'`.
  final String source;

  /// `'pocket_front'` | `'armband'` | null (null for the wrist source).
  final String? placement;

  /// `'linear_acceleration'` | `'accelerometer'`.
  final String sensorType;

  /// AUTHORITATIVE — always `RepDetectionResult.repCount`. Never adjusted by
  /// any function of [provisionalCount].
  final int proposedReps;

  /// NON-AUTHORITATIVE watch count; display/diagnostic only.
  final int? provisionalCount;

  /// `(provisionalCount - proposedReps).abs() > 1`.
  final bool provisionalDisagrees;

  /// 0-1, from the detector.
  final double setConfidence;

  /// [setConfidence] banded via [bandFor], then [ConfidenceBandStep.lowerByOne]
  /// applied once when [provisionalDisagrees] is true.
  final ConfidenceBand confidenceBand;

  final bool missedRepSuspected;
  final int missedBatches;
  final int sampleCount;

  /// received batches / expected `batchCount` from the capture-end payload.
  final double coverageRatio;

  /// `RepFeatures.toJson()`, for `recordObservation`. 10-04 passes this
  /// straight through; 10-05 must consume [features], not this raw map.
  final Map<String, dynamic>? featuresJson;

  final TrackerState state;

  /// Non-null whenever [state] is [TrackerState.manual] or
  /// [TrackerState.countOnly].
  final String? stateReason;

  const RepSuggestion({
    required this.captureId,
    required this.exerciseSlug,
    required this.movement,
    required this.source,
    this.placement,
    required this.sensorType,
    required this.proposedReps,
    this.provisionalCount,
    required this.provisionalDisagrees,
    required this.setConfidence,
    required this.confidenceBand,
    required this.missedRepSuspected,
    required this.missedBatches,
    required this.sampleCount,
    required this.coverageRatio,
    this.featuresJson,
    required this.state,
    this.stateReason,
  }) : assert(
          (state != TrackerState.manual && state != TrackerState.countOnly) ||
              stateReason != null,
          'stateReason must be non-null whenever state is manual or countOnly',
        );

  /// Derived: `RepFeatures.fromJson(featuresJson)`. Null both when nothing
  /// was captured and when the stored vector's `v` key does not match the
  /// current detector version — the same behaviour 10-05's gate expects.
  /// **This is the contract 10-05 consumes** (`estimate(suggestion.features)`).
  RepFeatures? get features =>
      featuresJson == null ? null : RepFeatures.fromJson(featuresJson!);

  /// Fixed thresholds so band derivation lives in exactly one place.
  static ConfidenceBand bandFor(double setConfidence) {
    if (setConfidence >= 0.75) return ConfidenceBand.high;
    if (setConfidence >= 0.45) return ConfidenceBand.medium;
    return ConfidenceBand.low;
  }
}
