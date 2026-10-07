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

  test(
    'periodized models show a literal 8-week example; none stays short by documented choice (D-06)',
    () {
      for (final model in PeriodizationModel.values) {
        final guide = ProgramMethodGuide.forModel(model);
        switch (model) {
          case PeriodizationModel.linear:
          case PeriodizationModel.concurrent:
          case PeriodizationModel.block:
          case PeriodizationModel.maxEffort:
            expect(
              guide.weeks.length,
              8,
              reason: '${model.label} should show a full 8-week example',
            );
          case PeriodizationModel.none:
            expect(
              guide.weeks.length,
              2,
              reason: 'none has no phases to map onto 8 weeks (D-06)',
            );
        }

        // Copywriting Contract: no placeholder text and no two consecutive
        // weeks share a verbatim description.
        for (var i = 0; i < guide.weeks.length; i++) {
          expect(guide.weeks[i].description, isNot('TBD'));
          if (i > 0) {
            expect(
              guide.weeks[i].description,
              isNot(guide.weeks[i - 1].description),
            );
          }
        }
      }
    },
  );

  test(
    "block's realization phase lands on week 8, matching Periodization._block(8)'s boundaries",
    () {
      final guide = ProgramMethodGuide.forModel(PeriodizationModel.block);
      expect(
        guide.weeks.where((w) => w.title == 'Realization').single.number,
        8,
      );

      final numbers = guide.weeks.map((w) => w.number).toList()..sort();
      expect(numbers, List.generate(8, (i) => i + 1));
    },
  );
}
