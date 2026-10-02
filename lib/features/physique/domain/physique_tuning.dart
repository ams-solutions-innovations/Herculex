/// Named constants for the physique domain (same idiom as `TdeeTuning`).
/// Each carries its source, or `[ASSUMED]` where it is a judgement call.
abstract final class PhysiqueTuning {
  /// Age at which cut and bulk become available (D-05).
  static const adultAgeYears = 18;

  /// Maingain surplus cap for restricted users; matches
  /// `DietPhaseCalculator.defaultMaingainSurplusKcal`.
  static const minorMaingainCapKcal = 150;

  /// A visual BF band wider than this counts as low confidence (D-06).
  /// [ASSUMED] Claude's discretion per CONTEXT.
  static const maxBfBandWidthPct = 6.0;

  /// Whether an absent confidence label restricts. Stays false until the edge
  /// function returning the new fields is deployed (RESEARCH Pitfall 7).
  static const unknownConfidenceRestricts = false;

  /// Helms 2014: 0.5-1 percent of bodyweight per week for cuts.
  static const cutCeilingPctPerWeek = 1.0;

  /// Iraki 2019: bulk rate ceiling, percent bodyweight per week.
  static const bulkCeilingPctPerWeek = 0.5;

  /// [ASSUMED] A1: maingain rate ceiling, percent bodyweight per week.
  static const maingainCeilingPctPerWeek = 0.15;

  /// Shortest roadmap phase, in weeks.
  static const minPhaseWeeks = 2;

  /// Longest roadmap phase, in weeks (UI-SPEC S2).
  static const maxPhaseWeeks = 52;

  /// Average weeks per month.
  static const weeksPerMonth = 4.345;

  /// Mirrors the editor's maintenance fallback.
  static const defaultMaintenanceKcal = 2500;

  /// Existing `weeklyRateKg * 1000` convention in `DietPhaseCalculator.apply`.
  static const kcalPerKgPerWeek = 1000;

  /// [ASSUMED] Later plans: maximum width of a target band.
  static const bandMaxWidth = 0.8;

  /// [ASSUMED] Later plans: band neutral threshold.
  static const bandNeutralThreshold = 0.15;

  /// [ASSUMED] Later plans: weekly trend that contradicts the phase, kg/week.
  static const trendContradictionKgPerWeek = 0.1;

  /// [ASSUMED] Later plans: maintain drift tolerance, kg/week.
  static const maintainDriftKgPerWeek = 0.4;

  /// [ASSUMED] Later plans: check-in window, days.
  static const checkInWindowDays = 7;

  /// [ASSUMED] Later plans: days an advance prompt is postponed.
  static const advancePostponeDays = 7;

  /// [ASSUMED] Later plans: half width of the target weight band, kg.
  static const targetBandHalfWidthKg = 1.0;

  /// [ASSUMED] Later plans: baseline photos kept per check-in.
  static const maxCheckInBaselinePhotos = 3;
}
