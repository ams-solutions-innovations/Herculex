import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/physique/domain/goal_display_copy.dart';

void main() {
  group('GoalDisplayCopy.title', () {
    test('empty and whitespace styles read as imported photos', () {
      expect(GoalDisplayCopy.title(''), 'Imported progress photos');
      expect(GoalDisplayCopy.title('   '), 'Imported progress photos');
    });

    test('a style is returned trimmed', () {
      expect(GoalDisplayCopy.title('  Lean athletic '), 'Lean athletic');
    });
  });

  group('GoalDisplayCopy.targetLine', () {
    test('null target yields null', () {
      expect(GoalDisplayCopy.targetLine(null), isNull);
    });

    test('whole numbers drop the decimal', () {
      expect(GoalDisplayCopy.targetLine(12.0), 'Target 12% body fat');
    });

    test('fractions keep one decimal', () {
      expect(GoalDisplayCopy.targetLine(12.5), 'Target 12.5% body fat');
    });
  });
}
