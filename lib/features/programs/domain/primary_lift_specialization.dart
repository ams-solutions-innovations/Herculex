/// Optional, user-owned primary-lift specialization settings.
///
/// The app uses these inputs to bias an otherwise full-body plan. It never
/// promises a particular PR or silently replaces a user's existing program.
enum PrimaryLift {
  squat('Squat', 'squat', {'barbell-back-squat'}),
  deadlift('Deadlift', 'hinge', {'conventional-deadlift'}),
  benchPress('Bench press', 'horizontal_push', {'barbell-bench-press'}),
  overheadPress('Overhead press', 'vertical_push', {'overhead-press'}),
  pullUp('Pull-up', 'vertical_pull', {'pull-up', 'pull-up-wide-grip'});

  const PrimaryLift(this.label, this.movementPattern, this.preferredSlugs);
  final String label;
  final String movementPattern;
  final Set<String> preferredSlugs;

  bool appliesToDayLabel(String label) {
    final value = label.toLowerCase();
    if (value.contains('full')) return true;
    return switch (this) {
      PrimaryLift.squat ||
      PrimaryLift.deadlift => value.contains('lower') || value.contains('leg'),
      _ =>
        value.contains('upper') ||
            value.contains('push') ||
            value.contains('pull'),
    };
  }
}

enum PrimaryLiftStickingPoint {
  bottom('Out of the bottom', {PrimaryLift.squat, PrimaryLift.overheadPress}),
  chest('Off the chest', {PrimaryLift.benchPress}),
  offFloor('Off the floor', {PrimaryLift.deadlift}),
  deadHang('From a dead hang', {PrimaryLift.pullUp}),
  midRange('Through the middle', {
    PrimaryLift.squat,
    PrimaryLift.deadlift,
    PrimaryLift.benchPress,
    PrimaryLift.overheadPress,
    PrimaryLift.pullUp,
  }),
  lockout('At lockout / the top', {
    PrimaryLift.squat,
    PrimaryLift.deadlift,
    PrimaryLift.benchPress,
    PrimaryLift.overheadPress,
    PrimaryLift.pullUp,
  }),
  unknown('Not sure yet', {
    PrimaryLift.squat,
    PrimaryLift.deadlift,
    PrimaryLift.benchPress,
    PrimaryLift.overheadPress,
    PrimaryLift.pullUp,
  });

  const PrimaryLiftStickingPoint(this.label, this.supportedLifts);
  final String label;
  final Set<PrimaryLift> supportedLifts;
}

class PrimaryLiftSpecialization {
  const PrimaryLiftSpecialization({
    required this.lift,
    required this.currentKg,
    required this.targetKg,
    required this.weeks,
    required this.stickingPoint,
  });

  final PrimaryLift lift;
  final double currentKg;
  final double targetKg;
  final int weeks;
  final PrimaryLiftStickingPoint stickingPoint;

  static int recommendedWeeks({
    required double currentKg,
    required double targetKg,
    required bool isNovice,
  }) {
    final increase = (targetKg - currentKg).clamp(0, double.infinity);
    final base = isNovice ? 16 : 12;
    if (increase > 30) return base + 8;
    if (increase > 15) return base + 4;
    return base;
  }

  String get assistanceFocus => switch ((lift, stickingPoint)) {
    (PrimaryLift.squat, PrimaryLiftStickingPoint.bottom) =>
      'Quad strength and a controlled squat pattern are prioritised.',
    (PrimaryLift.squat, PrimaryLiftStickingPoint.lockout) =>
      'Hip and posterior-chain assistance are prioritised.',
    (PrimaryLift.deadlift, PrimaryLiftStickingPoint.offFloor) =>
      'Leg drive and controlled hinge volume are prioritised.',
    (PrimaryLift.deadlift, _) =>
      'Posterior-chain strength and lat control are prioritised.',
    (PrimaryLift.benchPress, PrimaryLiftStickingPoint.chest) =>
      'Chest volume and stable pressing technique are prioritised.',
    (PrimaryLift.benchPress, _) =>
      'Triceps and upper-back assistance are prioritised.',
    (PrimaryLift.overheadPress, PrimaryLiftStickingPoint.bottom) =>
      'Strict pressing practice and shoulder control are prioritised.',
    (PrimaryLift.overheadPress, _) =>
      'Triceps and upper-back assistance are prioritised.',
    (PrimaryLift.pullUp, PrimaryLiftStickingPoint.deadHang) =>
      'Scapular control and vertical-pull volume are prioritised.',
    (PrimaryLift.pullUp, _) =>
      'Upper-back and elbow-flexor assistance are prioritised.',
    _ => 'Balanced assistance is prioritised for this primary lift.',
  };
}
