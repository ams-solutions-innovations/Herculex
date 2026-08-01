import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/features/profile/domain/profile.dart';

void main() {
  const metric = WeightFormat(MeasurementUnit.metric);
  const imperial = WeightFormat(MeasurementUnit.imperial);

  group('Units conversion', () {
    test('kilograms round-trip through pounds', () {
      expect(Units.lbToKg(Units.kgToLb(100)), closeTo(100, 1e-9));
    });

    test('uses the international avoirdupois pound', () {
      expect(Units.kgToLb(1), closeTo(2.2046226, 1e-6));
      expect(Units.lbToKg(1), closeTo(0.45359237, 1e-9));
    });

    test('centimetres round-trip through inches', () {
      expect(Units.inchToCm(Units.cmToInch(180)), closeTo(180, 1e-9));
      expect(Units.cmToInch(2.54), closeTo(1, 1e-9));
    });
  });

  group('WeightFormat', () {
    test('metric passes kilograms through unchanged', () {
      expect(metric.toDisplay(82.5), 82.5);
      expect(metric.format(82.5), '82.5 kg');
      expect(metric.suffix, 'kg');
    });

    test('imperial converts to pounds', () {
      expect(imperial.toDisplay(100), closeTo(220.462, 0.001));
      expect(imperial.suffix, 'lb');
      expect(imperial.format(100), '220.5 lb');
    });

    test('whole values drop the decimal in both systems', () {
      expect(metric.format(80), '80 kg');
      expect(imperial.format(Units.lbToKg(225)), '225 lb');
    });

    test('input converts back to kilograms for storage', () {
      expect(metric.toKg(80), 80);
      expect(imperial.toKg(225), closeTo(102.058, 0.001));
    });

    test('metric tonnage switches to tonnes past 1000 kg', () {
      expect(metric.formatTonnage(450), '450 kg');
      expect(metric.formatTonnage(12500), '12.5 t');
    });

    test('imperial tonnage stays in pounds, abbreviating past 10k', () {
      expect(imperial.formatTonnage(Units.lbToKg(800)), '800 lb');
      expect(imperial.formatTonnage(Units.lbToKg(25000)), '25.0k lb');
    });
  });

  group('HeightFormat', () {
    const metricH = HeightFormat(MeasurementUnit.metric);
    const imperialH = HeightFormat(MeasurementUnit.imperial);

    test('metric passes centimetres through', () {
      expect(metricH.formatValue(180), '180');
      expect(metricH.suffix, 'cm');
    });

    test('imperial converts to inches and back', () {
      expect(imperialH.toDisplay(180), closeTo(70.866, 0.001));
      expect(imperialH.toCm(70), closeTo(177.8, 1e-9));
      expect(imperialH.suffix, 'in');
    });
  });
}
