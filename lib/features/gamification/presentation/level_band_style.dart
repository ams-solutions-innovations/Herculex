import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';

/// Shared look of a rank band, so the level screen, the explainer and the
/// profile card agree.
extension LevelBandStyle on LevelBand {
  Color color(BuildContext context) {
    final hx = context.hx;
    return switch (this) {
      LevelBand.novice => hx.success,
      LevelBand.intermediate => hx.domainFasting,
      LevelBand.advanced => hx.warning,
      LevelBand.elite => hx.domainRecovery,
    };
  }

  IconData get icon => switch (this) {
    LevelBand.novice => Icons.military_tech_rounded,
    LevelBand.intermediate => Icons.shield_rounded,
    LevelBand.advanced => Icons.diamond_rounded,
    LevelBand.elite => Icons.workspace_premium_rounded,
  };

  String get lore => switch (this) {
    LevelBand.novice => 'Building the habit and learning the movements.',
    LevelBand.intermediate => 'Solid technique and real strength on the bar.',
    LevelBand.advanced => 'Strong by any gym standard, earned over years.',
    LevelBand.elite => 'Rare strength, proven in your own logs.',
  };
}

/// "1.75× BW" for barbell lifts, "15 reps" for calisthenics.
String formatStrengthValue(StrengthLift lift, double value) =>
    switch (lift.measure) {
      StrengthMeasure.bodyweightRatio => '${value.toStringAsFixed(2)}× BW',
      StrengthMeasure.reps =>
        '${value.round()} ${value.round() == 1 ? 'rep' : 'reps'}',
    };

String requirementStatus(LiftRequirement requirement) {
  final current = requirement.current;
  if (requirement.needsLogging) return 'Log it in Herculex to count';
  if (current == null) return 'Not logged yet';
  return 'Now ${formatStrengthValue(requirement.lift, current)}';
}
