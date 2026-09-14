import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/presentation/views/program_method_guide_view.dart';

void main() {
  test('every periodization option has a concrete guide and example weeks', () {
    for (final model in PeriodizationModel.values) {
      final guide = ProgramMethodGuide.forModel(model);
      expect(guide.summary, isNotEmpty);
      expect(guide.bestFor, isNotEmpty);
      expect(guide.how, isNotEmpty);
      expect(guide.rotation, isNotEmpty);
      expect(guide.weeks, isNotEmpty);
    }
  });

  test(
    'Westside guide explains Dynamic Effort rather than hiding its volume',
    () {
      final guide = ProgramMethodGuide.forModel(PeriodizationModel.maxEffort);
      expect(guide.how.join(' '), contains('8 × 3'));
    },
  );
}
