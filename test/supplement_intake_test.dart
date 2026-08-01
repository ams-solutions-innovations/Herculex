import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_intake.dart';

Supplement _s(
  String id,
  String name, {
  Map<String, double> nutrients = const {},
  double? dose,
  String? unit,
  String? brand,
}) =>
    Supplement(
      id: id,
      name: name,
      brand: brand,
      doseAmount: dose,
      doseUnit: unit,
      nutrients: nutrients,
    );

void main() {
  group('SupplementIntake.forDay', () {
    test('unticked supplements contribute nothing', () {
      final intake = SupplementIntake.forDay(
        supplements: [
          _s('a', 'Vitamin D', nutrients: {'vitamin_d': 25}),
        ],
        takenIds: const {},
      );
      expect(intake.isEmpty, isTrue);
    });

    test('sums nutrients across ticked supplements', () {
      final intake = SupplementIntake.forDay(
        supplements: [
          _s('a', 'Multivitamin',
              nutrients: {'vitamin_d': 10, 'magnesium': 100}),
          _s('b', 'Magnesium', nutrients: {'magnesium': 300}),
          _s('c', 'Zinc', nutrients: {'zinc': 15}),
        ],
        takenIds: const {'a', 'b'},
      );
      expect(intake.nutrients['magnesium'], 400);
      expect(intake.nutrients['vitamin_d'], 10);
      // Zinc wasn't ticked.
      expect(intake.nutrients.containsKey('zinc'), isFalse);
    });

    test('counts each ticked supplement exactly once', () {
      // The same supplement listed twice (a corrupt config) must not
      // double-count — the tracker is a checklist, not a counter.
      final omega = _s('a', 'Omega 3', nutrients: {'omega_3': 2});
      final intake = SupplementIntake.forDay(
        supplements: [omega],
        takenIds: const {'a'},
      );
      expect(intake.nutrients['omega_3'], 2);
    });

    test('a ticked supplement with no nutrients is reported as untracked', () {
      final intake = SupplementIntake.forDay(
        supplements: [_s('a', 'Creatine', dose: 5, unit: 'g')],
        takenIds: const {'a'},
      );
      expect(intake.nutrients, isEmpty);
      expect(intake.untrackedNames, ['Creatine']);
    });

    test('zero and negative amounts are ignored', () {
      final intake = SupplementIntake.forDay(
        supplements: [
          _s('a', 'Odd', nutrients: {'iron': 0, 'zinc': -5, 'calcium': 200}),
        ],
        takenIds: const {'a'},
      );
      // All-zero values mean the supplement contributes nothing at all.
      expect(intake.nutrients, {'calcium': 200});
    });

    test('the returned map is unmodifiable', () {
      final intake = SupplementIntake.forDay(
        supplements: [_s('a', 'Iron', nutrients: {'iron': 18})],
        takenIds: const {'a'},
      );
      expect(() => intake.nutrients['iron'] = 99, throwsUnsupportedError);
    });
  });

  group('Supplement serialization', () {
    test('round-trips brand, barcode, dose and nutrients', () {
      final original = Supplement(
        id: 'x',
        name: 'Creatine',
        brand: 'Bulk',
        barcode: '5060105890123',
        doseAmount: 5,
        doseUnit: 'g',
        nutrients: const {'magnesium': 50},
        schedule: SupplementSchedule.postWorkout,
      );
      final decoded =
          Supplement.listFromJson(Supplement.listToJson([original])).single;

      expect(decoded.brand, 'Bulk');
      expect(decoded.barcode, '5060105890123');
      expect(decoded.doseAmount, 5);
      expect(decoded.doseUnit, 'g');
      expect(decoded.nutrients, {'magnesium': 50});
      expect(decoded.schedule, SupplementSchedule.postWorkout);
    });

    test('decodes pre-v2 entries that predate the new fields', () {
      final decoded = Supplement.listFromJson(
        '[{"id":"old","name":"Vitamin C","schedule":"none"}]',
      ).single;

      expect(decoded.name, 'Vitamin C');
      expect(decoded.brand, isNull);
      expect(decoded.nutrients, isEmpty);
      expect(decoded.contributesNutrients, isFalse);
    });

    test('malformed nutrient values are dropped, not fatal', () {
      final decoded = Supplement.listFromJson(
        '[{"id":"a","name":"X","schedule":"none",'
        '"nutrients":{"iron":"lots","zinc":11,"calcium":null}}]',
      ).single;

      expect(decoded.nutrients, {'zinc': 11.0});
    });

    test('doseLabel drops a trailing zero', () {
      expect(_s('a', 'X', dose: 5, unit: 'g').doseLabel, '5 g');
      expect(_s('a', 'X', dose: 2.5, unit: 'g').doseLabel, '2.5 g');
      expect(_s('a', 'X').doseLabel, isNull);
    });
  });
}
