/// One day's sleep as the recovery engine sees it.
///
/// Health Connect and Samsung Health report two different "sleep" numbers, and
/// the app used to conflate them:
///
///  * [inBedMinutes] — the whole session, awake stretches included
///    ("total sleep" in most wearable apps).
///  * [asleepMinutes] — light + deep + REM + unstaged sleep ("actual sleep").
///
/// Stage minutes are `null` when the source only reported a bare session with
/// no staging, so "no data" is never confused with "zero deep sleep".
class SleepSummary {
  const SleepSummary({
    required this.inBedMinutes,
    required this.asleepMinutes,
    this.awakeMinutes = 0,
    this.lightMinutes,
    this.deepMinutes,
    this.remMinutes,
    this.awakenings,
  });

  final double inBedMinutes;
  final double asleepMinutes;

  /// Time spent awake or out of bed inside the session.
  final double awakeMinutes;

  final double? lightMinutes;
  final double? deepMinutes;
  final double? remMinutes;

  /// Separate awake periods between falling asleep and the final wake-up.
  final int? awakenings;

  double get inBedHours => inBedMinutes / 60.0;
  double get asleepHours => asleepMinutes / 60.0;

  /// Whether the source reported sleep stages, not just a session length.
  bool get hasStages =>
      lightMinutes != null || deepMinutes != null || remMinutes != null;

  /// Share of the time in bed actually spent asleep, 0–1. Only meaningful when
  /// [hasStages]; without stages the session length *is* the sleep length.
  double get efficiency =>
      inBedMinutes <= 0 ? 0.0 : (asleepMinutes / inBedMinutes).clamp(0.0, 1.0);

  /// Share of actual sleep spent in deep sleep, or null without stages.
  double? get deepShare => _share(deepMinutes);

  /// Share of actual sleep spent in REM, or null without stages.
  double? get remShare => _share(remMinutes);

  double? _share(double? minutes) {
    if (minutes == null || asleepMinutes <= 0) return null;
    return (minutes / asleepMinutes).clamp(0.0, 1.0);
  }

  // ── Persistence ──────────────────────────────────────────────────────────
  // Stored as plain `health_samples` rows (one per kind) so there is no schema
  // change. `sleep_hours` keeps its old name and now means *actual* sleep —
  // which is what every existing consumer (TDEE, weekly report, sleep-vs-RPE)
  // was always meant to read.

  static const kindAsleepHours = 'sleep_hours';
  static const kindInBedHours = 'sleep_in_bed_hours';
  static const kindAwakeMinutes = 'sleep_awake_min';
  static const kindLightMinutes = 'sleep_light_min';
  static const kindDeepMinutes = 'sleep_deep_min';
  static const kindRemMinutes = 'sleep_rem_min';
  static const kindAwakenings = 'sleep_awakenings';

  /// Every `health_samples.kind` this model writes.
  static const sampleKinds = [
    kindAsleepHours,
    kindInBedHours,
    kindAwakeMinutes,
    kindLightMinutes,
    kindDeepMinutes,
    kindRemMinutes,
    kindAwakenings,
  ];

  /// Kinds written alongside [kindAsleepHours]; cleared when a night has no
  /// value for them so a stale stage figure never outlives its night.
  static const detailKinds = [
    kindInBedHours,
    kindAwakeMinutes,
    kindLightMinutes,
    kindDeepMinutes,
    kindRemMinutes,
    kindAwakenings,
  ];

  /// The rows to persist for this night, keyed by `health_samples.kind`.
  Map<String, double> toSamples() => {
    kindAsleepHours: asleepHours,
    kindInBedHours: inBedHours,
    kindAwakeMinutes: awakeMinutes,
    kindLightMinutes: ?lightMinutes,
    kindDeepMinutes: ?deepMinutes,
    kindRemMinutes: ?remMinutes,
    if (awakenings != null) kindAwakenings: awakenings!.toDouble(),
  };

  /// The most recent night among stored rows, whatever dates they span.
  static SleepSummary? latestFromSamples(
    Iterable<({String dateIso, String kind, double value})> rows,
  ) {
    final byDate = <String, Map<String, double>>{};
    for (final r in rows) {
      byDate.putIfAbsent(r.dateIso, () => {})[r.kind] = r.value;
    }
    // ISO dates sort lexically; newest first.
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final date in dates) {
      final night = fromSamples(byDate[date]!);
      if (night != null) return night;
    }
    return null;
  }

  /// Rebuilds a night from stored rows. Null when there is no sleep row.
  ///
  /// Rows written before the detail kinds existed only have `sleep_hours`;
  /// those read back as a stage-less night where in-bed equals asleep.
  static SleepSummary? fromSamples(Map<String, double> byKind) {
    final asleepHours = byKind[kindAsleepHours];
    if (asleepHours == null || asleepHours <= 0) return null;
    final asleepMinutes = asleepHours * 60.0;
    final inBedHours = byKind[kindInBedHours];
    final awakenings = byKind[kindAwakenings];
    return SleepSummary(
      inBedMinutes: inBedHours == null ? asleepMinutes : inBedHours * 60.0,
      asleepMinutes: asleepMinutes,
      awakeMinutes: byKind[kindAwakeMinutes] ?? 0,
      lightMinutes: byKind[kindLightMinutes],
      deepMinutes: byKind[kindDeepMinutes],
      remMinutes: byKind[kindRemMinutes],
      awakenings: awakenings?.round(),
    );
  }
}
