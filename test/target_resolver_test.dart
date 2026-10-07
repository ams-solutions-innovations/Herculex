import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';

// 2029-12-31 is a Monday (weekday 1).
final _monday = DateTime(2029, 12, 31);

TargetRule _rule(String appliesTo, int kcal) => TargetRule(
  kcal: kcal,
  proteinG: 150,
  carbsG: 250,
  fatG: 70,
  appliesTo: appliesTo,
);

MacroTargets _fallback(int kcal) =>
    MacroTargets(kcal: kcal, proteinG: 120, carbsG: 200, fatG: 60);

void main() {
  group('TargetResolver manual target wins (TDEE-04)', () {
    test('a global rule beats any non-null fallback', () {
      final result = TargetResolver.resolve(
        rules: [_rule('global', 2400)],
        date: _monday,
        isTrainingDay: true,
        fallback: _fallback(1800),
      );
      expect(result, isNotNull);
      expect(result!.kcal, 2400);
      expect(result.kcal, isNot(1800));
    });

    test('result is identical whatever the fallback value is', () {
      final rules = [_rule('global', 2400)];
      final low = TargetResolver.resolve(
        rules: rules,
        date: _monday,
        isTrainingDay: true,
        fallback: _fallback(1800),
      )!;
      final high = TargetResolver.resolve(
        rules: rules,
        date: _monday,
        isTrainingDay: true,
        fallback: _fallback(3400),
      )!;
      expect(high.kcal, low.kcal);
      expect(high.proteinG, low.proteinG);
      expect(high.carbsG, low.carbsG);
      expect(high.fatG, low.fatG);
    });

    test('no rules returns the fallback; null fallback returns null', () {
      final withFallback = TargetResolver.resolve(
        rules: const [],
        date: _monday,
        isTrainingDay: true,
        fallback: _fallback(2100),
      );
      expect(withFallback!.kcal, 2100);

      final none = TargetResolver.resolve(
        rules: const [],
        date: _monday,
        isTrainingDay: true,
      );
      expect(none, isNull);
    });

    test('rules whose scope does not match are ignored', () {
      final result = TargetResolver.resolve(
        rules: [
          _rule('weekday:3', 2000),
          _rule('date:2030-01-01', 2100),
          _rule('rest_day', 2200),
        ],
        date: _monday,
        isTrainingDay: true,
        fallback: _fallback(2600),
      );
      expect(result!.kcal, 2600);
    });

    test('fallback is consulted only when resolveRule yields null', () {
      final rules = [_rule('weekday:3', 2000)];
      expect(
        TargetResolver.resolveRule(
          rules: rules,
          date: _monday,
          isTrainingDay: true,
        ),
        isNull,
      );
      expect(
        TargetResolver.resolve(
          rules: rules,
          date: _monday,
          isTrainingDay: true,
          fallback: _fallback(2600),
        )!.kcal,
        2600,
      );
      // Same rule, on the matching weekday: the rule wins over the fallback.
      expect(
        TargetResolver.resolve(
          rules: rules,
          date: DateTime(2030, 1, 2), // Wednesday
          isTrainingDay: true,
          fallback: _fallback(2600),
        )!.kcal,
        2000,
      );
    });

    test('specificity: date > weekday > training/rest > global', () {
      final rules = [
        _rule('global', 1000),
        _rule('training_day', 2000),
        _rule('weekday:1', 3000),
        _rule('date:2029-12-31', 4000),
      ];
      int kcalWith(List<TargetRule> r) => TargetResolver.resolve(
        rules: r,
        date: _monday,
        isTrainingDay: true,
        fallback: _fallback(9999),
      )!.kcal;

      expect(kcalWith(rules), 4000);
      expect(kcalWith(rules.sublist(0, 3)), 3000);
      expect(kcalWith(rules.sublist(0, 2)), 2000);
      expect(kcalWith(rules.sublist(0, 1)), 1000);
    });

    test('active diet schedule still reduces the winning rule', () {
      final schedule = DietScheduleRule(
        startDate: DateTime(2029, 12, 1),
        reducePct: 10,
        intervalDays: 10,
      );
      // 30 days elapsed -> 3 steps of -10%: 2000 * 0.9^3 = 1458.
      final result = TargetResolver.resolve(
        rules: [_rule('global', 2000)],
        date: _monday,
        isTrainingDay: true,
        schedule: schedule,
        fallback: _fallback(3400),
      );
      expect(result!.kcal, 1458);
      expect(result.proteinG, 150);
    });
  });
}
