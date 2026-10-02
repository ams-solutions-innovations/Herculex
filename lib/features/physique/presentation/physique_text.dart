import 'package:flutter/material.dart';

/// The only text styles Phase 23 widgets may use: four sizes (24/17/15/13) and
/// two weights (400/600), enforced in one place.
abstract final class PhysiqueText {
  static TextStyle _make(
    TextStyle? base,
    double size,
    FontWeight weight,
    double height,
    Color? color, {
    bool tabular = false,
  }) {
    return (base ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static TextTheme _t(BuildContext c) => Theme.of(c).textTheme;

  static TextStyle display(BuildContext context, {Color? color}) => _make(
    _t(context).headlineSmall,
    24,
    FontWeight.w600,
    1.2,
    color,
    tabular: true,
  );

  static TextStyle heading(BuildContext context, {Color? color}) =>
      _make(_t(context).titleMedium, 17, FontWeight.w600, 1.2, color);

  static TextStyle body(BuildContext context, {Color? color}) =>
      _make(_t(context).bodyMedium, 15, FontWeight.w400, 1.5, color);

  static TextStyle bodyStrong(BuildContext context, {Color? color}) =>
      _make(_t(context).bodyMedium, 15, FontWeight.w600, 1.5, color);

  static TextStyle bodyTabular(BuildContext context, {Color? color}) => _make(
    _t(context).bodyMedium,
    15,
    FontWeight.w400,
    1.5,
    color,
    tabular: true,
  );

  static TextStyle label(BuildContext context, {Color? color}) =>
      _make(_t(context).bodySmall, 13, FontWeight.w400, 1.5, color);

  static TextStyle labelStrong(BuildContext context, {Color? color}) =>
      _make(_t(context).bodySmall, 13, FontWeight.w600, 1.5, color);

  static TextStyle labelTabular(BuildContext context, {Color? color}) => _make(
    _t(context).bodySmall,
    13,
    FontWeight.w400,
    1.5,
    color,
    tabular: true,
  );
}
