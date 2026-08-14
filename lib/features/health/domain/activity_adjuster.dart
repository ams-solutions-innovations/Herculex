class ActivityAdjustmentResult {
  final double volumeFactor;
  final String statusLabel;
  final String message;

  const ActivityAdjustmentResult({
    required this.volumeFactor,
    required this.statusLabel,
    required this.message,
  });

  static const normal = ActivityAdjustmentResult(
    volumeFactor: 1.0,
    statusLabel: "NO CHANGE",
    message:
        "Training volume is normal. Step counts within healthy thresholds.",
  );

  static const unavailable = ActivityAdjustmentResult(
    volumeFactor: 1.0,
    statusLabel: "HEALTH DATA UNAVAILABLE",
    message:
        "Training volume is unchanged because trusted step data is not available.",
  );
}

class ActivityBasedAdjuster {
  static ActivityAdjustmentResult suggest({
    required double todaySteps,
    required double baselineSteps,
    double? sleepHours,
    double? restingHr,
  }) {
    if (todaySteps >= 25000) {
      return const ActivityAdjustmentResult(
        volumeFactor: 0.0,
        statusLabel: "SKIP / REST RECOMMENDED",
        message:
            "Step counts reached exhausting levels today (25k+). We highly recommend skipping training and prioritizing recovery.",
      );
    } else if (todaySteps >= 18000) {
      return const ActivityAdjustmentResult(
        volumeFactor: 0.8,
        statusLabel: "VOLUME REDUCED 20%",
        message:
            "High activity levels detected today (18k+ steps). Gym training sets scaled down by 20% to prevent overtraining.",
      );
    } else if (todaySteps >= 14000) {
      return const ActivityAdjustmentResult(
        volumeFactor: 0.9,
        statusLabel: "VOLUME REDUCED 10%",
        message:
            "Active day detected today (14k+ steps). Training sets slightly scaled down by 10%.",
      );
    }

    if (sleepHours != null && sleepHours > 0) {
      if (sleepHours < 5.0) {
        return const ActivityAdjustmentResult(
          volumeFactor: 0.8,
          statusLabel: "SLEEP DEFICIT (VOLUME -20%)",
          message:
              "Very low sleep recorded (<5h). Training volume scaled down to protect CNS recovery and joint health.",
        );
      } else if (sleepHours < 6.0) {
        return const ActivityAdjustmentResult(
          volumeFactor: 0.9,
          statusLabel: "LOW RECOVERY (VOLUME -10%)",
          message:
              "Sub-optimal sleep recorded (<6h). Training sets slightly reduced by 10% to prevent cumulative fatigue.",
        );
      }
    }

    return ActivityAdjustmentResult.normal;
  }
}
