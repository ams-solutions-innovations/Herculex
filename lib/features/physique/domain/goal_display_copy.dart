/// Display copy for a goal that may be a photos-only legacy import (D-08):
/// empty style and no target. Shared by the past-goals list and the progress
/// header so the wording exists once.
abstract final class GoalDisplayCopy {
  static const String importedTitle = 'Imported progress photos';

  static String title(String style) {
    final trimmed = style.trim();
    return trimmed.isEmpty ? importedTitle : trimmed;
  }

  /// Null when the goal has no target (nothing to render, no empty gap).
  static String? targetLine(double? targetBfPercent) {
    if (targetBfPercent == null) return null;
    final isWhole = targetBfPercent == targetBfPercent.roundToDouble();
    final text = isWhole
        ? targetBfPercent.round().toString()
        : targetBfPercent.toStringAsFixed(1);
    return 'Target $text% body fat';
  }
}
