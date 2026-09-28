/// How a maintenance-calorie estimate was produced.
///
/// Persisted as `method.name` (`observed`, `classifier`, `coldStart`).
enum TdeeMethod {
  /// Measured from logged intake plus the bodyweight trend.
  observed,

  /// Derived from the activity classifier (steps + logged training).
  classifier,

  /// No usable data yet; the onboarding activity level seeds the number.
  coldStart;

  /// Parses persisted text. Unknown or null text falls back to [coldStart]
  /// so a corrupt or future value never selects an unvalidated method.
  static TdeeMethod fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => coldStart);
}

/// How much the estimate should be trusted.
enum TdeeConfidence {
  high,
  medium,
  low;

  /// Parses persisted text. Unknown or null text falls back to [low].
  static TdeeConfidence fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => low);

  String get label => switch (this) {
    TdeeConfidence.high => 'High',
    TdeeConfidence.medium => 'Medium',
    TdeeConfidence.low => 'Low',
  };
}

/// Which badge the UI shows next to "Maintenance calories".
enum TdeeBadgeState {
  measured,
  measuredAging,
  classified,
  calibrating;

  /// Badge copy. Wording is locked by 28-UI-SPEC (D-05, D-08); the middle dot
  /// and em dash are escapes so file encoding cannot corrupt them.
  String label(TdeeConfidence confidence) => switch (this) {
    TdeeBadgeState.measured => 'Measured · ${confidence.label} confidence',
    TdeeBadgeState.measuredAging => 'Measured · Aging estimate',
    // The classifier never reports high confidence, so clamp defensively.
    TdeeBadgeState.classified =>
      'Classified · '
          '${confidence == TdeeConfidence.high ? TdeeConfidence.medium.label : confidence.label}'
          ' confidence',
    TdeeBadgeState.calibrating => 'Calibrating — using onboarding estimate',
  };
}

/// One maintenance-calorie estimate: the value plus how it was reached.
///
/// This same type is what the estimate-history table persists (D-11), so
/// history is a `List<TdeeEstimateResult>` ordered newest first. There is no
/// isManual/isCurrent flag: a saved manual target always wins in
/// `TargetResolver`, which already guarantees TDEE-04.
class TdeeEstimateResult {
  const TdeeEstimateResult({
    required this.kcal,
    required this.method,
    required this.confidence,
    required this.windowDays,
    required this.observedQualified,
    required this.inputs,
    required this.estimatedAt,
  });

  final int kcal;
  final TdeeMethod method;
  final TdeeConfidence confidence;

  /// Window (in days) the estimate was computed over.
  final int windowDays;

  /// Whether the observed-expenditure adherence gates passed at this
  /// recalibration, whether or not observed was promoted to the active method.
  /// Doubles as the freshness flag: observed and not qualified means held.
  final bool observedQualified;

  /// Named inputs the estimate used, shown individually in the detail sheet.
  final Map<String, Object?> inputs;

  final DateTime estimatedAt;

  /// The D-04 "aging" state: observed is still being shown but its gates no
  /// longer pass.
  bool get isHeld => method == TdeeMethod.observed && !observedQualified;

  TdeeBadgeState get badgeState => switch (method) {
    TdeeMethod.observed =>
      observedQualified
          ? TdeeBadgeState.measured
          : TdeeBadgeState.measuredAging,
    TdeeMethod.classifier => TdeeBadgeState.classified,
    TdeeMethod.coldStart => TdeeBadgeState.calibrating,
  };
}
