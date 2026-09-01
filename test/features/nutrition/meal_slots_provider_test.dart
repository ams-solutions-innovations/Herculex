import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/meal_slots.dart';
import 'package:herculex/features/nutrition/presentation/meal_slots_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MealSlotsNotifier tests', () {
    late SharedPreferences prefs;
    late MealSlotsNotifier notifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      notifier = MealSlotsNotifier(prefs);
    });

    test('initial state loads default meal slots', () {
      expect(notifier.state.length, equals(4));
      expect(
        notifier.state.map((s) => s.key),
        containsAll(['breakfast', 'lunch', 'dinner', 'snack']),
      );
    });

    test('allows removing built-in meal slots down to 1 slot', () async {
      await notifier.remove('breakfast');
      expect(notifier.state.length, equals(3));
      expect(notifier.state.any((s) => s.key == 'breakfast'), isFalse);

      await notifier.remove('lunch');
      await notifier.remove('dinner');
      expect(notifier.state.length, equals(1));
      expect(notifier.state.first.key, equals('snack'));

      // Attempting to remove the last slot should be ignored
      await notifier.remove('snack');
      expect(notifier.state.length, equals(1));
      expect(notifier.state.first.key, equals('snack'));
    });

    test('allows re-adding classic/built-in meal slots', () async {
      await notifier.remove('breakfast');
      expect(notifier.state.any((s) => s.key == 'breakfast'), isFalse);

      final breakfastSlot = MealSlot.defaults.firstWhere(
        (s) => s.key == 'breakfast',
      );
      await notifier.addBuiltIn(breakfastSlot);

      expect(notifier.state.any((s) => s.key == 'breakfast'), isTrue);
      expect(notifier.state.last.key, equals('breakfast'));
    });

    test('adds custom meal slots', () async {
      await notifier.add('Pre-workout');
      expect(notifier.state.any((s) => s.label == 'Pre-workout'), isTrue);
    });
  });
}
