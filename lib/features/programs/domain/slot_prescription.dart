import '../../workouts/domain/set_type.dart';

/// How close to failure a segment is meant to be taken.
///
/// Failure is an *intent*, not a structure — it has to compose with any
/// [SetType] (you can run myo-reps to failure), so it is deliberately not
/// another member of that enum.
enum Intent {
  technical('technical', 'Technical', rir: 5),
  rir3('rir3', '3 RIR', rir: 3),
  rir2('rir2', '2 RIR', rir: 2),
  rir1('rir1', '1 RIR', rir: 1),
  toFailure('to_failure', 'To failure', rir: 0),

  /// As many reps as possible — the rep target is a floor, not a cap.
  amrap('amrap', 'AMRAP', rir: 0),

  /// Work up to a heavy single/double/triple. The rep target describes the top
  /// set; load is discovered, not prescribed.
  rampToMax('ramp_to_max', 'Work up to a max', rir: 0);

  const Intent(this.id, this.label, {required this.rir});

  final String id;
  final String label;

  /// Reps in reserve. 0 means the set ends at failure.
  final int rir;

  /// The RPE that matches this intent, for users who think in RPE.
  double get rpe => (10 - rir).clamp(1, 10).toDouble();

  static Intent fromId(String? id) =>
      values.firstWhere((i) => i.id == id, orElse: () => Intent.rir2);
}

/// One continuous block of work inside a slot: "3×8 @RPE8", "2 sets to
/// failure", "work up to a heavy triple".
class WorkSegment {
  const WorkSegment({
    required this.sets,
    required this.repsMin,
    int? repsMax,
    this.intent = Intent.rir2,
    this.percentOf1Rm,
    this.setType = SetType.standard,
    this.restSeconds,
    this.meta = const {},
  }) : repsMax = repsMax ?? repsMin;

  final int sets;
  final int repsMin;
  final int repsMax;
  final Intent intent;

  /// Prescribed load as a fraction of 1RM. Null when the load comes from RPE
  /// or from ramping.
  final double? percentOf1Rm;

  final SetType setType;
  final int? restSeconds;

  /// Values for [SetType.metaKeys].
  final Map<String, Object?> meta;

  bool get isRange => repsMax != repsMin;

  bool get isRamp => intent == Intent.rampToMax;

  /// Working sets that count toward weekly volume. A ramp's back-off work is
  /// counted by its own segment, so the ramp itself contributes one set.
  int get countedSets => isRamp ? 1 : sets;

  /// Set-type-adjusted CNS cost multiplier for this segment.
  double get cnsMultiplier =>
      setType.cnsFactor * (intent == Intent.toFailure ? 1.15 : 1.0);

  WorkSegment copyWith({
    int? sets,
    int? repsMin,
    int? repsMax,
    Intent? intent,
    double? percentOf1Rm,
    SetType? setType,
    int? restSeconds,
    Map<String, Object?>? meta,
  }) {
    return WorkSegment(
      sets: sets ?? this.sets,
      repsMin: repsMin ?? this.repsMin,
      repsMax: repsMax ?? this.repsMax,
      intent: intent ?? this.intent,
      percentOf1Rm: percentOf1Rm ?? this.percentOf1Rm,
      setType: setType ?? this.setType,
      restSeconds: restSeconds ?? this.restSeconds,
      meta: meta ?? this.meta,
    );
  }

  String format() {
    if (isRamp) {
      if (isRange) return 'Work up to a heavy $repsMin-$repsMax';
      final noun = switch (repsMin) {
        1 => 'single',
        2 => 'double',
        3 => 'triple',
        _ => '$repsMin-rep max',
      };
      return 'Work up to a heavy $noun';
    }

    final reps = switch (intent) {
      Intent.amrap => 'AMRAP',
      _ when isRange => '$repsMin-$repsMax',
      _ => '$repsMin',
    };
    final buffer = StringBuffer('${sets}x$reps');

    if (percentOf1Rm != null) {
      buffer.write(' @${(percentOf1Rm! * 100).round()}%');
    } else if (intent != Intent.amrap && intent != Intent.toFailure) {
      buffer.write(' @RIR${intent.rir}');
    }
    // "to failure" is the load prescription; an RIR of 0 next to it is noise.
    if (intent == Intent.toFailure) buffer.write('→F');
    if (setType != SetType.standard) buffer.write(' ${setType.label}');
    return buffer.toString();
  }
}

/// A named, reusable prescription — the chip the user drops on a slot.
///
/// This is what makes the builder customizable without being exhausting:
/// configure "my 2-to-failure" once, then it is one tap on any slot forever.
class SlotPrescription {
  const SlotPrescription({
    required this.name,
    required this.segments,
    this.note,
  });

  final String name;
  final List<WorkSegment> segments;
  final String? note;

  int get totalSets =>
      segments.fold(0, (sum, s) => sum + s.countedSets);

  bool get hasFailureWork =>
      segments.any((s) => s.intent == Intent.toFailure);

  /// Σ(sets × set-type CNS multiplier) — the input to the weekly CNS guardrail.
  double get cnsUnits => segments.fold(
        0.0,
        (sum, s) => sum + s.countedSets * s.cnsMultiplier,
      );

  String format() => segments.map((s) => s.format()).join(' + ');

  SlotPrescription scaled({
    double intensityFactor = 1.0,
    double volumeFactor = 1.0,
  }) {
    return SlotPrescription(
      name: name,
      note: note,
      segments: [
        for (final s in segments)
          s.copyWith(
            sets: s.isRamp
                ? s.sets
                : (s.sets * volumeFactor).round().clamp(1, 20),
            percentOf1Rm: s.percentOf1Rm == null
                ? null
                : (s.percentOf1Rm! * intensityFactor).clamp(0.3, 1.05),
          ),
      ],
    );
  }

  /// The presets that ship with the app.
  static const builtIns = <SlotPrescription>[
    SlotPrescription(
      name: 'Westside ME',
      note: 'Work up to a heavy single, then back off.',
      segments: [
        WorkSegment(sets: 1, repsMin: 1, intent: Intent.rampToMax),
        WorkSegment(
          sets: 2,
          repsMin: 3,
          repsMax: 5,
          intent: Intent.rir2,
          percentOf1Rm: 0.85,
        ),
      ],
    ),
    SlotPrescription(
      name: 'Dynamic Effort 8x3',
      note: 'Speed work — every rep moved as fast as possible.',
      segments: [
        WorkSegment(
          sets: 8,
          repsMin: 3,
          intent: Intent.technical,
          percentOf1Rm: 0.55,
          restSeconds: 60,
        ),
      ],
    ),
    SlotPrescription(
      name: '2 to failure',
      note: 'One primer set, then two all-out sets.',
      segments: [
        WorkSegment(sets: 1, repsMin: 6, repsMax: 8, intent: Intent.rir2),
        WorkSegment(
          sets: 2,
          repsMin: 6,
          repsMax: 12,
          intent: Intent.toFailure,
        ),
      ],
    ),
    SlotPrescription(
      name: 'Straight 3x8 RPE8',
      segments: [
        WorkSegment(sets: 3, repsMin: 8, intent: Intent.rir2),
      ],
    ),
    SlotPrescription(
      name: 'Myo 1+3',
      note: 'Activation set to failure, then three mini-sets.',
      segments: [
        WorkSegment(
          sets: 1,
          repsMin: 12,
          repsMax: 20,
          intent: Intent.toFailure,
          setType: SetType.myoReps,
          meta: {'activationReps': 15, 'miniSets': 3},
        ),
      ],
    ),
    SlotPrescription(
      name: '20x3 @60%',
      note: 'High-frequency volume block.',
      segments: [
        WorkSegment(
          sets: 20,
          repsMin: 3,
          intent: Intent.technical,
          percentOf1Rm: 0.6,
          restSeconds: 45,
        ),
      ],
    ),
  ];
}
