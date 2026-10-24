/// One finished week of a program: sessions scheduled vs. trained.
typedef WeekAdherence = ({int planned, int done});

enum BlockAdjustmentReason { lowAdherence, poorRecovery }

/// A suggestion to rebuild the rest of the block. Never applied on its own:
/// the user reviews the regenerated plan and confirms it.
class BlockAdjustmentRecommendation {
  const BlockAdjustmentRecommendation({
    required this.reason,
    required this.currentDaysPerWeek,
    required this.suggestedDaysPerWeek,
    required this.lighter,
    required this.message,
  });

  final BlockAdjustmentReason reason;
  final int currentDaysPerWeek;
  final int suggestedDaysPerWeek;

  /// Reduce working volume across the regenerated weeks.
  final bool lighter;
  final String message;
}

/// Deterministic rules for when a block no longer fits the user's life or
/// recovery. Adherence wins over recovery: a plan the user cannot attend is
/// the first thing to fix.
abstract final class BlockAdjustmentAdvisor {
  /// A week below this share of its planned sessions counts as missed.
  static const adherenceFloor = 0.7;

  /// Below this average muscle recovery score (0–100) the block is too hard.
  static const recoveryFloor = 45.0;

  static const minDaysPerWeek = 2;

  static BlockAdjustmentRecommendation? evaluate({
    required int daysPerWeek,
    required List<WeekAdherence> recentWeeks,
    required bool deloadRecommended,
    required bool cnsDeloadSuggested,
    double? averageRecoveryScore,
  }) {
    final weeks = recentWeeks.where((w) => w.planned > 0).toList();
    if (weeks.length >= 2) {
      final missed = weeks
          .where((w) => w.done / w.planned < adherenceFloor)
          .length;
      if (missed * 3 >= weeks.length * 2) {
        final avgDone =
            weeks.fold<int>(0, (sum, w) => sum + w.done) / weeks.length;
        final suggested = avgDone.round().clamp(minDaysPerWeek, daysPerWeek);
        if (suggested < daysPerWeek) {
          return BlockAdjustmentRecommendation(
            reason: BlockAdjustmentReason.lowAdherence,
            currentDaysPerWeek: daysPerWeek,
            suggestedDaysPerWeek: suggested,
            lighter: false,
            message:
                'Lately you have trained about ${avgDone.toStringAsFixed(1)} of '
                '$daysPerWeek planned sessions a week. A $suggested-day plan '
                'you can keep will build more than a $daysPerWeek-day plan '
                'you keep missing.',
          );
        }
      }
    }

    final recoveryLow =
        averageRecoveryScore != null && averageRecoveryScore < recoveryFloor;
    if (deloadRecommended || cnsDeloadSuggested || recoveryLow) {
      final suggested = (daysPerWeek - 1).clamp(minDaysPerWeek, daysPerWeek);
      return BlockAdjustmentRecommendation(
        reason: BlockAdjustmentReason.poorRecovery,
        currentDaysPerWeek: daysPerWeek,
        suggestedDaysPerWeek: suggested,
        lighter: true,
        message:
            'Your recovery has been lagging behind your training. A lighter '
            'block${suggested < daysPerWeek ? ' with $suggested days a week' : ''} '
            'lets you recover and keep progressing.',
      );
    }
    return null;
  }
}
