/// How much of its planned work a finished session actually logged.
///
/// A session the user finished is always "done" in the schedule; this only
/// says how done. The ratio comes from the workout report's completed vs
/// planned working sets.
abstract final class SessionCompletion {
  /// At or above this a session reads as fully completed. Leaves room for one
  /// dropped back-off set without nagging the user.
  static const fullThreshold = 0.95;

  /// Completed / planned working sets, clamped to 0..1. A session with no
  /// known plan counts as complete.
  static double ratio({required int completed, required int planned}) {
    if (planned <= 0) return 1;
    return (completed / planned).clamp(0.0, 1.0).toDouble();
  }

  static bool isPartial(double? ratio) =>
      ratio != null && ratio < fullThreshold;

  /// "70 %".
  static String label(double ratio) => '${(ratio * 100).round()} %';
}
