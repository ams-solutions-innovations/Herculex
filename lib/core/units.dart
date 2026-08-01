import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../features/profile/domain/profile.dart';

/// Conversion and formatting for the user's chosen measurement system.
///
/// Everything is *stored* in metric — kilograms and centimetres — so engines,
/// analytics and the database never have to care which system is on. This
/// class is the single boundary where values are converted for display and
/// converted back on input.
class Units {
  const Units._();

  static const kgPerLb = 0.45359237;
  static const cmPerInch = 2.54;

  static double kgToLb(double kg) => kg / kgPerLb;
  static double lbToKg(double lb) => lb * kgPerLb;
  static double cmToInch(double cm) => cm / cmPerInch;
  static double inchToCm(double inch) => inch * cmPerInch;
}

/// The user's measurement system, shared app-wide.
///
/// Backed by the same `units_metric` preference the profile screen has always
/// written, so existing installs keep their setting.
class UnitsNotifier extends Notifier<MeasurementUnit> {
  static const prefsKey = 'units_metric';

  @override
  MeasurementUnit build() {
    final metric =
        ref.watch(sharedPreferencesProvider).getBool(prefsKey) ?? true;
    return metric ? MeasurementUnit.metric : MeasurementUnit.imperial;
  }

  Future<void> set(MeasurementUnit unit) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(prefsKey, unit == MeasurementUnit.metric);
    state = unit;
  }

  Future<void> toggle() => set(state == MeasurementUnit.metric
      ? MeasurementUnit.imperial
      : MeasurementUnit.metric);
}

final unitsProvider =
    NotifierProvider<UnitsNotifier, MeasurementUnit>(UnitsNotifier.new);

/// Display helpers bound to the active measurement system. Obtained from
/// [weightFormatProvider] so widgets never convert by hand.
class WeightFormat {
  final MeasurementUnit unit;
  const WeightFormat(this.unit);

  bool get isMetric => unit == MeasurementUnit.metric;

  /// Short unit label: `kg` or `lb`.
  String get suffix => isMetric ? 'kg' : 'lb';

  /// Converts a stored kilogram value into the display system.
  double toDisplay(double kg) => isMetric ? kg : Units.kgToLb(kg);

  /// Converts a user-entered display value back to kilograms for storage.
  double toKg(double displayValue) =>
      isMetric ? displayValue : Units.lbToKg(displayValue);

  /// `82.5 kg` / `182 lb`. Whole numbers lose the decimal.
  String format(double kg, {int decimals = 1}) =>
      '${formatValue(kg, decimals: decimals)} $suffix';

  /// Just the number, for fields and tight layouts.
  String formatValue(double kg, {int decimals = 1}) {
    // Round *before* testing for wholeness: a lb↔kg round-trip lands on
    // 225.00000000000003, which would otherwise render as "225.0" and rewrite
    // the user's field while they type.
    final v = double.parse(toDisplay(kg).toStringAsFixed(decimals));
    return decimals == 0 || v.truncateToDouble() == v
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(decimals);
  }

  /// Large aggregates: tonnes above 1 t, otherwise the base unit.
  /// Imperial uses pounds throughout — "short tons" would confuse more than
  /// they'd shorten.
  String formatTonnage(double kg) {
    if (isMetric) {
      return kg >= 1000
          ? '${(kg / 1000).toStringAsFixed(1)} t'
          : '${kg.round()} kg';
    }
    final lb = Units.kgToLb(kg);
    return lb >= 10000
        ? '${(lb / 1000).toStringAsFixed(1)}k lb'
        : '${lb.round()} lb';
  }
}

final weightFormatProvider = Provider<WeightFormat>((ref) {
  return WeightFormat(ref.watch(unitsProvider));
});

/// Height helpers, used by the profile form.
class HeightFormat {
  final MeasurementUnit unit;
  const HeightFormat(this.unit);

  bool get isMetric => unit == MeasurementUnit.metric;
  String get suffix => isMetric ? 'cm' : 'in';

  double toDisplay(double cm) => isMetric ? cm : Units.cmToInch(cm);
  double toCm(double displayValue) =>
      isMetric ? displayValue : Units.inchToCm(displayValue);

  String formatValue(double cm, {int decimals = 1}) {
    final v = toDisplay(cm);
    return v.truncateToDouble() == v
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(decimals);
  }
}

final heightFormatProvider = Provider<HeightFormat>((ref) {
  return HeightFormat(ref.watch(unitsProvider));
});
