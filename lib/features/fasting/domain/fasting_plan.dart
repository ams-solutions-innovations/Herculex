enum FastingPlan {
  // Declared first so it renders first among the intermittent-plan tiles,
  // which iterate FastingPlan.values in declaration order.
  quickFast,
  h12,
  h14,
  h16,
  h18,
  h20,
  // Prolonged / extended fasts (multi-day).
  d1,
  d2,
  d3,
  custom,
}

/// A fast started with no real target keeps `targetSeconds` filled with this
/// sentinel rather than a nullable column — 200h is unreachable through any
/// preset or the custom-hours slider (capped at 168h), so it's unambiguous.
/// A migration to a genuinely nullable target is tracked for whenever the
/// fasting schema is next touched (e.g. the Phase 6 auto-schedule table).
const kQuickFastSentinelSeconds = 200 * 3600;

/// Whether a session (by its stored target) was started as a Quick Fast —
/// elapsed-only, no ring, no target-end time.
bool isQuickFastTarget(int targetSeconds) =>
    targetSeconds == kQuickFastSentinelSeconds;

extension FastingPlanExtension on FastingPlan {
  String get nameString {
    switch (this) {
      case FastingPlan.quickFast:
        return 'Quick Fast';
      case FastingPlan.h12:
        return '12:12';
      case FastingPlan.h14:
        return '14:10';
      case FastingPlan.h16:
        return '16:8';
      case FastingPlan.h18:
        return '18:6';
      case FastingPlan.h20:
        return '20:4';
      case FastingPlan.d1:
        return '24h';
      case FastingPlan.d2:
        return '48h';
      case FastingPlan.d3:
        return '72h';
      case FastingPlan.custom:
        return 'Custom';
    }
  }

  /// True for multi-day extended fasts, which get a distinct visual treatment.
  bool get isProlonged =>
      this == FastingPlan.d1 ||
      this == FastingPlan.d2 ||
      this == FastingPlan.d3;

  int get targetSeconds {
    switch (this) {
      case FastingPlan.quickFast:
        return kQuickFastSentinelSeconds;
      case FastingPlan.h12:
        return 12 * 3600;
      case FastingPlan.h14:
        return 14 * 3600;
      case FastingPlan.h16:
        return 16 * 3600;
      case FastingPlan.h18:
        return 18 * 3600;
      case FastingPlan.h20:
        return 20 * 3600;
      case FastingPlan.d1:
        return 24 * 3600;
      case FastingPlan.d2:
        return 48 * 3600;
      case FastingPlan.d3:
        return 72 * 3600;
      case FastingPlan.custom:
        return 0;
    }
  }

  String get description {
    switch (this) {
      case FastingPlan.quickFast:
        return 'No target — just watch the clock run';
      case FastingPlan.h12:
        return 'Simple fasting for beginners';
      case FastingPlan.h14:
        return 'Gentle fast for daily balance';
      case FastingPlan.h16:
        return 'Popular lean gains method';
      case FastingPlan.h18:
        return 'Advanced fat-loss window';
      case FastingPlan.h20:
        return 'Warrior diet fast';
      case FastingPlan.d1:
        return 'Full-day fast for autophagy';
      case FastingPlan.d2:
        return 'Extended 2-day metabolic reset';
      case FastingPlan.d3:
        return 'Prolonged 3-day deep fast';
      case FastingPlan.custom:
        return 'Set your own target hours';
    }
  }
}
