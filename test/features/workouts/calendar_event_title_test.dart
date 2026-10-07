import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/calendar_service.dart';

void main() {
  test('planned workout reads "Name emoji" with no app prefix', () {
    expect(calendarEventTitle('Upper Push', done: false), 'Upper Push 💪');
    expect(calendarEventTitle('Lower', done: false), 'Lower 🦵');
    expect(calendarEventTitle('Upper', done: false), 'Upper 💪');
  });

  test('finished workout gets a trailing check', () {
    expect(calendarEventTitle('Pull', done: true), 'Pull 🏋️ ✅');
  });

  test('blank name falls back to Workout', () {
    expect(calendarEventTitle('  ', done: false), 'Workout 🗓️');
  });
}
