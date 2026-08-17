import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';

/// Locks in the Quick Fast sentinel invariant: it must stay unreachable
/// through the custom-hours slider (capped at 168h in the UI), or a
/// deliberate 168h custom fast would misrender as a Quick Fast.
void main() {
  test('the Quick Fast sentinel is above the 168h custom-hours ceiling', () {
    expect(FastingPlan.quickFast.targetSeconds, greaterThan(168 * 3600));
  });

  test('isQuickFastTarget only matches the sentinel', () {
    expect(isQuickFastTarget(FastingPlan.quickFast.targetSeconds), isTrue);
    expect(isQuickFastTarget(168 * 3600), isFalse);
    expect(isQuickFastTarget(FastingPlan.h16.targetSeconds), isFalse);
    expect(isQuickFastTarget(FastingPlan.d3.targetSeconds), isFalse);
  });

  test('every plan except custom carries a positive target', () {
    for (final plan in FastingPlan.values) {
      if (plan == FastingPlan.custom) continue;
      expect(plan.targetSeconds, greaterThan(0), reason: plan.name);
    }
  });
}
