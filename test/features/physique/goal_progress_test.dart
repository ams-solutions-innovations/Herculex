import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/physique/domain/goal_progress.dart';

double? _f(double? start, double? current, double? target) =>
    GoalProgress.fraction(
      startBfPercent: start,
      currentBfPercent: current,
      targetBfPercent: target,
    );

void main() {
  test('halfway between start and target is 0.5', () {
    expect(_f(25, 18, 11), closeTo(0.5, 1e-9));
  });

  test('no change is 0 and reaching the target is 1', () {
    expect(_f(25, 25, 11), 0);
    expect(_f(25, 11, 11), 1);
  });

  test('clamps when moving the wrong way or overshooting', () {
    expect(_f(25, 28, 11), 0);
    expect(_f(25, 9, 11), 1);
  });

  test('is null when a figure is missing or there is nothing to lose', () {
    expect(_f(null, 18, 11), isNull);
    expect(_f(25, null, 11), isNull);
    expect(_f(25, 18, null), isNull);
    expect(_f(10, 10, 11), isNull);
  });
}
