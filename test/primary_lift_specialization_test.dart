import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';

void main() {
  test('each primary lift exposes only its relevant weak-point choices', () {
    final deadliftPoints = PrimaryLiftStickingPoint.values
        .where((point) => point.supportedLifts.contains(PrimaryLift.deadlift))
        .toList();
    final pullUpPoints = PrimaryLiftStickingPoint.values
        .where((point) => point.supportedLifts.contains(PrimaryLift.pullUp))
        .toList();

    expect(deadliftPoints, contains(PrimaryLiftStickingPoint.offFloor));
    expect(deadliftPoints, isNot(contains(PrimaryLiftStickingPoint.chest)));
    expect(pullUpPoints, contains(PrimaryLiftStickingPoint.deadHang));
    expect(pullUpPoints, isNot(contains(PrimaryLiftStickingPoint.offFloor)));
  });

  test('lift labels map to stable, common movement patterns', () {
    expect(PrimaryLift.deadlift.movementPattern, 'hinge');
    expect(PrimaryLift.benchPress.movementPattern, 'horizontal_push');
    expect(PrimaryLift.overheadPress.movementPattern, 'vertical_push');
    expect(PrimaryLift.pullUp.movementPattern, 'vertical_pull');
  });
}
