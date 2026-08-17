import 'package:flutter/widgets.dart';

/// Spacing scale. Values match the de-facto rhythm already used across the
/// app (card padding 20, card gap 24) so migrated screens do not shift.
abstract final class HxSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
}

/// Corner radii. The app's design language is the iOS pill family, so the
/// large end is deliberately generous and [pill] is fully rounded.
abstract final class HxRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);

  /// Sheet shells: rounded top corners only.
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(xl));
}
