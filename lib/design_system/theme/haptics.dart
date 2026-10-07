import 'package:flutter/services.dart';

/// Thin wrapper over [HapticFeedback] so the whole app uses one consistent,
/// iOS-style tactile vocabulary. Call these on every meaningful interaction.
class Haptics {
  const Haptics._();

  /// Light tap — selection changes, chip taps, list-row taps, toggles.
  static void selection() => HapticFeedback.selectionClick();

  /// Light impact — primary button presses, sheet opens.
  static void light() => HapticFeedback.lightImpact();

  /// Medium impact — confirmations, saves, completing a set.
  static void medium() => HapticFeedback.mediumImpact();

  /// Heavy impact — destructive confirms, finishing a workout.
  static void heavy() => HapticFeedback.heavyImpact();

  /// Success vibration pattern (notification-style).
  static void success() => HapticFeedback.mediumImpact();
}
