import 'package:flutter/animation.dart';

/// Animation durations and curves, so motion feels like one system rather
/// than per-screen guesses.
abstract final class HxMotion {
  /// State flips that must feel instant: chips, toggles, tap feedback.
  static const Duration fast = Duration(milliseconds: 120);

  /// The default: most fades, slides and color transitions.
  static const Duration base = Duration(milliseconds: 200);

  /// Elements entering or leaving the screen.
  static const Duration slow = Duration(milliseconds: 300);

  /// Large surfaces: sheets, the quick-add menu, page-level reveals.
  static const Duration slower = Duration(milliseconds: 450);

  /// Decelerating curve for entrances — the workhorse.
  static const Curve emphasized = Curves.easeOutCubic;

  /// Slight overshoot for playful reveals (quick-add items, the "+" rotation).
  static const Curve emphasizedOvershoot = Curves.easeOutBack;

  /// Symmetric curve for state changes that stay on screen.
  static const Curve standard = Curves.easeInOut;

  /// Stagger between siblings in a sequenced reveal.
  static const Duration stagger = Duration(milliseconds: 40);
}
