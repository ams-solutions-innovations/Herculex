import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/domain/fixture_corpus.dart';

void main() {
  group('requiredFixtures', () {
    test('has exactly 11 entries', () {
      expect(requiredFixtures.length, 11);
    });

    test('every name is unique', () {
      final names = requiredFixtures.map((f) => f.name).toSet();
      expect(names.length, requiredFixtures.length);
    });
  });

  group('FixtureCorpusStatus.evaluate', () {
    test('an empty corpus reports all 11 missing and is not sufficient', () {
      final status = FixtureCorpusStatus.evaluate(const []);
      expect(status.sufficient, isFalse);
      expect(
        status.byName.values.every((s) => s == FixtureRecordState.missing),
        isTrue,
      );
      expect(status.missingSpecs.length, 11);
    });

    test('10 of 11 recorded reports exactly one missing and is not sufficient', () {
      final names = requiredFixtures.map((f) => f.name).toList()..removeLast();
      final status = FixtureCorpusStatus.evaluate(names);

      expect(status.sufficient, isFalse);
      final missing =
          status.byName.entries.where((e) => e.value == FixtureRecordState.missing);
      expect(missing.length, 1);
      expect(status.missingSpecs.length, 1);
    });

    test('all 11 recorded reports sufficient', () {
      final names = requiredFixtures.map((f) => f.name).toList();
      final status = FixtureCorpusStatus.evaluate(names);

      expect(status.sufficient, isTrue);
      expect(
        status.byName.values.every((s) => s == FixtureRecordState.recorded),
        isTrue,
      );
      expect(status.missingSpecs, isEmpty);
    });
  });
}
