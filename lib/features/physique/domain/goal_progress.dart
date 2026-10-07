/// How far along the body-fat journey from start to target the user is.
///
/// Derived only, display only. Null when it cannot be stated honestly: a
/// missing figure, or a target that is not below the start (nothing to lose).
abstract final class GoalProgress {
  /// Fraction of the start-to-target body-fat distance covered, 0..1.
  static double? fraction({
    required double? startBfPercent,
    required double? currentBfPercent,
    required double? targetBfPercent,
  }) {
    if (startBfPercent == null ||
        currentBfPercent == null ||
        targetBfPercent == null) {
      return null;
    }
    final span = startBfPercent - targetBfPercent;
    if (span <= 0) return null;
    return ((startBfPercent - currentBfPercent) / span).clamp(0.0, 1.0);
  }
}
