/// Periodization models (V2 §12). A model prescribes, for each week of a
/// program, an intensity factor (multiplier on prescribed load / %1RM) and a
/// volume factor (multiplier on prescribed sets), plus the block phase label
/// where applicable.
enum PeriodizationModel {
  none('none', 'None'),
  linear('linear', 'Linear'),
  concurrent('concurrent', 'Concurrent'),
  block('block', 'Block'),
  maxEffort('max_effort', 'Max Effort (Westside)');

  const PeriodizationModel(this.id, this.label);
  final String id;
  final String label;

  static PeriodizationModel fromId(String? id) => values.firstWhere(
    (m) => m.id == id,
    orElse: () => PeriodizationModel.none,
  );
}

class WeekPrescription {
  final int weekIndex;
  final double intensityFactor;
  final double volumeFactor;

  /// accumulation | transmutation | realization — only for [PeriodizationModel.block].
  final String? blockPhase;

  /// True on planned deload weeks (volume cut, intensity eased).
  final bool isDeload;

  const WeekPrescription({
    required this.weekIndex,
    required this.intensityFactor,
    required this.volumeFactor,
    this.blockPhase,
    this.isDeload = false,
  });
}

class Periodization {
  /// Week-by-week prescription for a [weeks]-long program under [model].
  static List<WeekPrescription> plan(PeriodizationModel model, int weeks) {
    assert(weeks > 0);
    return switch (model) {
      PeriodizationModel.none => [
        for (var w = 0; w < weeks; w++)
          WeekPrescription(weekIndex: w, intensityFactor: 1, volumeFactor: 1),
      ],
      PeriodizationModel.linear => _linear(weeks),
      PeriodizationModel.concurrent => _concurrent(weeks),
      PeriodizationModel.block => _block(weeks),
      PeriodizationModel.maxEffort => _maxEffort(weeks),
    };
  }

  /// Linear: intensity ramps weekly while volume tapers; every 4th week is a
  /// deload.
  static List<WeekPrescription> _linear(int weeks) {
    final result = <WeekPrescription>[];
    var ramp = 0;
    for (var w = 0; w < weeks; w++) {
      final deload = (w + 1) % 4 == 0;
      if (deload) {
        result.add(
          WeekPrescription(
            weekIndex: w,
            intensityFactor: 0.85,
            volumeFactor: 0.6,
            isDeload: true,
          ),
        );
      } else {
        result.add(
          WeekPrescription(
            weekIndex: w,
            intensityFactor: 1.0 + 0.025 * ramp,
            volumeFactor: (1.0 - 0.05 * ramp).clamp(0.7, 1.0),
          ),
        );
        ramp++;
      }
    }
    return result;
  }

  /// Concurrent: all qualities trained simultaneously — steady prescription
  /// with a gentle wave (heavy/medium/light) so weekly stress still varies.
  static List<WeekPrescription> _concurrent(int weeks) {
    const wave = [1.0, 0.93, 1.05];
    return [
      for (var w = 0; w < weeks; w++)
        WeekPrescription(
          weekIndex: w,
          intensityFactor: wave[w % wave.length],
          volumeFactor: 1.0,
        ),
    ];
  }

  /// Block: accumulation (high volume / lower intensity) → transmutation →
  /// realization (low volume / peak intensity). Phases split the program
  /// roughly 40/40/20.
  static List<WeekPrescription> _block(int weeks) {
    final accWeeks = (weeks * 0.4).ceil().clamp(1, weeks);
    // Realization always gets at least one week (when the program has ≥3).
    final transCap = weeks - accWeeks - (weeks >= 3 ? 1 : 0);
    final transWeeks = (weeks * 0.4).ceil().clamp(
      0,
      transCap < 0 ? 0 : transCap,
    );
    return [
      for (var w = 0; w < weeks; w++)
        () {
          if (w < accWeeks) {
            return WeekPrescription(
              weekIndex: w,
              intensityFactor: 0.85,
              volumeFactor: 1.2,
              blockPhase: 'accumulation',
            );
          }
          if (w < accWeeks + transWeeks) {
            return WeekPrescription(
              weekIndex: w,
              intensityFactor: 1.0,
              volumeFactor: 1.0,
              blockPhase: 'transmutation',
            );
          }
          return WeekPrescription(
            weekIndex: w,
            intensityFactor: 1.1,
            volumeFactor: 0.7,
            blockPhase: 'realization',
          );
        }(),
    ];
  }

  /// Max effort (Westside-style): intensity lives at the top every week
  /// (work up to a heavy single/triple); accommodation comes from rotating
  /// the max-effort lift (see ExerciseRotation), not waving intensity.
  /// Every 4th week eases off to protect the CNS.
  static List<WeekPrescription> _maxEffort(int weeks) {
    return [
      for (var w = 0; w < weeks; w++)
        (w + 1) % 4 == 0
            ? WeekPrescription(
                weekIndex: w,
                intensityFactor: 0.8,
                volumeFactor: 0.7,
                isDeload: true,
              )
            : WeekPrescription(
                weekIndex: w,
                intensityFactor: 1.0,
                volumeFactor: 1.0,
              ),
    ];
  }
}
