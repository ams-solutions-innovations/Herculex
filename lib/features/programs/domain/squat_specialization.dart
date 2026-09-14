/// User-owned inputs for an optional squat-centred block.
///
/// This is deliberately a training preference, not a promise that a target
/// load will be reached by a given date. The generated plan keeps whole-body
/// work while adding predictable squat exposure and targeted assistance.
enum SquatStickingPoint {
  bottom('Out of the bottom'),
  midRange('Through the middle'),
  lockout('At the top / lockout'),
  unknown('Not sure yet');

  const SquatStickingPoint(this.label);
  final String label;
}

class SquatSpecialization {
  const SquatSpecialization({
    required this.currentKg,
    required this.targetKg,
    required this.weeks,
    required this.stickingPoint,
  });

  final double currentKg;
  final double targetKg;
  final int weeks;
  final SquatStickingPoint stickingPoint;

  double get requiredIncreaseKg =>
      (targetKg - currentKg).clamp(0, double.infinity);

  /// Conservative planning horizon, based on the requested increase rather
  /// than presenting a strength outcome as certain.
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

  String get assistanceFocus => switch (stickingPoint) {
    SquatStickingPoint.bottom =>
      'Tempo/paused squat pattern and quad strength are prioritised.',
    SquatStickingPoint.midRange =>
      'Volume squatting and balanced quad/glute assistance are prioritised.',
    SquatStickingPoint.lockout =>
      'Hip and posterior-chain assistance are prioritised.',
    SquatStickingPoint.unknown =>
      'A balanced squat assistance plan is used until you identify a sticking point.',
  };
}
