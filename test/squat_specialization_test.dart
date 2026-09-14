import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/squat_specialization.dart';

void main() {
  test(
    'squat specialization recommendation is conservative and explainable',
    () {
      expect(
        SquatSpecialization.recommendedWeeks(
          currentKg: 100,
          targetKg: 140,
          isNovice: false,
        ),
        20,
      );
      expect(
        const SquatSpecialization(
          currentKg: 100,
          targetKg: 140,
          weeks: 20,
          stickingPoint: SquatStickingPoint.bottom,
        ).assistanceFocus,
        contains('quad'),
      );
    },
  );
}
