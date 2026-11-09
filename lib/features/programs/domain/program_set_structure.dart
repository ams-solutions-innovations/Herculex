import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/prescription_resolver.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

/// The stored numbers of one program exercise, free of the drift row so review
/// screens and the workout resolver share one path.
class SlotTargets {
  const SlotTargets({
    required this.sets,
    this.repsMin,
    this.repsMax,
    this.rir,
    this.rpe,
    this.percentOf1Rm,
    this.restSeconds,
  });

  final int sets;
  final int? repsMin;
  final int? repsMax;
  final int? rir;
  final int? rpe;
  final double? percentOf1Rm;
  final int? restSeconds;
}

/// How load moves across a slot's working sets.
enum PyramidDirection {
  none,

  /// Load rises and reps fall, set by set.
  ascending,

  /// Heaviest work first, then lighter sets.
  descending,
}

/// What the program screens show for a slot before the workout exists.
class SetStructureSummary {
  const SetStructureSummary({
    required this.prescription,
    required this.setsLabel,
    required this.direction,
    required this.structureLabel,
  });

  final SlotPrescription prescription;

  /// `2 × 4–6 · RPE 9+` or `1 × 4–6 → 3 × 6–8`.
  final String setsLabel;
  final PyramidDirection direction;

  /// `Reverse pyramid`; null for plain straight sets.
  final String? structureLabel;

  int get workingSets => prescription.totalSets;
}

/// Turns a program slot's method and stored numbers into its working sets.
/// `PlannedSessionResolver` and the review screens both call this, so what is
/// shown when preparing a program is what the workout then contains.
abstract final class ProgramSetStructure {
  static ResolvedPrescription resolve({
    required SlotTrainingMethod method,
    required SlotTargets targets,
    required SlotRole role,
    required PeriodizationModel model,
    required WeekPrescription week,
    required String mechanics,
    required String modality,
  }) {
    final effectiveMethod =
        (method == SlotTrainingMethod.dynamicEffort &&
            model == PeriodizationModel.linear)
        ? SlotTrainingMethod.straightSets
        : method;
    final template = switch (effectiveMethod) {
      SlotTrainingMethod.maxEffort => SlotPrescription.builtIns.firstWhere(
        (p) => p.name == 'Westside ME',
      ),
      SlotTrainingMethod.dynamicEffort => SlotPrescription.builtIns.firstWhere(
        (p) => p.name.startsWith('Dynamic Effort'),
      ),
      SlotTrainingMethod.repetition => const SlotPrescription(
        name: 'Repetition method',
        segments: [
          WorkSegment(sets: 3, repsMin: 8, repsMax: 12, intent: Intent.rir1),
        ],
      ),
      SlotTrainingMethod.topSetBackoff => const SlotPrescription(
        name: 'Top set + back-off',
        segments: [
          WorkSegment(sets: 1, repsMin: 4, repsMax: 6, intent: Intent.rir1),
          WorkSegment(sets: 3, repsMin: 6, repsMax: 8, intent: Intent.rir2),
        ],
      ),
      SlotTrainingMethod.pyramidUp => const SlotPrescription(
        name: 'Pyramid up',
        note: 'Add load each set as the reps come down.',
        segments: [
          WorkSegment(
            sets: 1,
            repsMin: 10,
            repsMax: 12,
            intent: Intent.rir3,
            setType: SetType.pyramid,
          ),
          WorkSegment(
            sets: 1,
            repsMin: 8,
            repsMax: 10,
            intent: Intent.rir2,
            setType: SetType.pyramid,
          ),
          WorkSegment(
            sets: 1,
            repsMin: 6,
            repsMax: 8,
            intent: Intent.rir1,
            setType: SetType.pyramid,
          ),
        ],
      ),
      SlotTrainingMethod.reversePyramid => const SlotPrescription(
        name: 'Reverse pyramid',
        note: 'Heaviest set first, then less load and more reps.',
        segments: [
          WorkSegment(sets: 1, repsMin: 4, repsMax: 6, intent: Intent.rir1),
          WorkSegment(
            sets: 1,
            repsMin: 6,
            repsMax: 8,
            intent: Intent.rir1,
            setType: SetType.downSets,
            meta: {'relativeToTopSetMin': 0.9, 'relativeToTopSetMax': 0.9},
          ),
          WorkSegment(
            sets: 1,
            repsMin: 8,
            repsMax: 10,
            intent: Intent.rir1,
            setType: SetType.downSets,
            meta: {'relativeToTopSetMin': 0.8, 'relativeToTopSetMax': 0.8},
          ),
        ],
      ),
      SlotTrainingMethod.volumeWave => SlotPrescription(
        name: 'Volume wave',
        segments: [
          WorkSegment(
            sets: targets.sets,
            repsMin: targets.repsMin ?? 10,
            repsMax: targets.repsMax ?? 10,
            intent: Intent.rir2,
          ),
        ],
      ),
      SlotTrainingMethod.technique => const SlotPrescription(
        name: 'Technique / tempo',
        segments: [WorkSegment(sets: 3, repsMin: 5, intent: Intent.technical)],
      ),
      SlotTrainingMethod.straightSets ||
      SlotTrainingMethod.doubleProgression ||
      SlotTrainingMethod.intensityFocus => SlotPrescription(
        name: switch (effectiveMethod) {
          SlotTrainingMethod.doubleProgression => 'Double progression',
          SlotTrainingMethod.intensityFocus => 'Intensity focus',
          _ => 'Straight sets',
        },
        segments: [
          WorkSegment(
            sets: targets.sets,
            repsMin: targets.repsMin ?? 8,
            repsMax: targets.repsMax ?? targets.repsMin ?? 12,
            intent: _intentFromRir(
              targets.rir ?? (targets.rpe == null ? null : 10 - targets.rpe!),
            ),
            percentOf1Rm: targets.percentOf1Rm,
            restSeconds: targets.restSeconds,
          ),
        ],
      ),
      SlotTrainingMethod.auto => null,
    };
    return PrescriptionResolver.resolve(
      model: effectiveMethod == SlotTrainingMethod.maxEffort
          ? PeriodizationModel.maxEffort
          : model,
      role: role,
      // The point of an intensity program is its fixed set count: a volume
      // taper would turn two sets into one. Only a planned deload may cut it.
      week:
          effectiveMethod == SlotTrainingMethod.intensityFocus && !week.isDeload
          ? WeekPrescription(
              weekIndex: week.weekIndex,
              intensityFactor: week.intensityFactor,
              volumeFactor: 1,
              blockPhase: week.blockPhase,
            )
          : week,
      template: template,
      mechanics: mechanics,
      modality: modality,
    );
  }

  static SetStructureSummary describe({
    required SlotTrainingMethod method,
    required SlotTargets targets,
    required SlotRole role,
    required PeriodizationModel model,
    required WeekPrescription week,
    required String mechanics,
    required String modality,
    SlotPrescription? override,
  }) {
    final prescription =
        override ??
        // The workout always runs Max Effort as its full sequence.
        (method == SlotTrainingMethod.maxEffort
            ? SlotPrescription.builtIns.firstWhere(
                (p) => p.name == 'Westside ME',
              )
            : resolve(
                method: method,
                targets: targets,
                role: role,
                model: model,
                week: week,
                mechanics: mechanics,
                modality: modality,
              ).prescription);
    final direction = switch (method) {
      SlotTrainingMethod.pyramidUp => PyramidDirection.ascending,
      SlotTrainingMethod.topSetBackoff ||
      SlotTrainingMethod.reversePyramid ||
      SlotTrainingMethod.maxEffort => PyramidDirection.descending,
      _ => _directionOf(prescription.segments),
    };
    final effort = method == SlotTrainingMethod.intensityFocus
        ? _focusEffort(prescription)
        : '';
    return SetStructureSummary(
      prescription: prescription,
      setsLabel:
          '${prescription.segments.map(_segmentLabel).join(' → ')}$effort',
      direction: direction,
      structureLabel: switch (method) {
        SlotTrainingMethod.pyramidUp => 'Pyramid up',
        SlotTrainingMethod.reversePyramid => 'Reverse pyramid',
        SlotTrainingMethod.topSetBackoff => 'Top set, then back-off sets',
        SlotTrainingMethod.maxEffort => 'Heavy top set, then back-off sets',
        SlotTrainingMethod.intensityFocus => 'Intensity focus',
        _ => switch (direction) {
          PyramidDirection.ascending => 'Pyramid up',
          PyramidDirection.descending => 'Reverse pyramid',
          PyramidDirection.none => null,
        },
      },
    );
  }

  /// A template carries its own set types. Falling reps across pyramid sets
  /// mean rising load, and the other way round.
  static PyramidDirection _directionOf(List<WorkSegment> segments) {
    if (segments.any((s) => s.setType == SetType.downSets)) {
      return PyramidDirection.descending;
    }
    if (!segments.any((s) => s.setType == SetType.pyramid)) {
      return PyramidDirection.none;
    }
    return segments.first.repsMin < segments.last.repsMin
        ? PyramidDirection.descending
        : PyramidDirection.ascending;
  }

  static String _segmentLabel(WorkSegment segment) {
    final reps = segment.isRange
        ? '${segment.repsMin}–${segment.repsMax}'
        : '${segment.repsMin}';
    return '${segment.sets} × $reps';
  }

  static String _focusEffort(SlotPrescription prescription) {
    final rir = prescription.segments.firstOrNull?.intent.rir;
    return rir == null ? '' : ' · RPE ${10 - rir}${rir <= 1 ? '+' : ''}';
  }

  static Intent _intentFromRir(int? rir) => switch (rir) {
    0 => Intent.toFailure,
    1 => Intent.rir1,
    2 => Intent.rir2,
    3 => Intent.rir3,
    4 => Intent.rir4,
    5 => Intent.technical,
    _ => Intent.rir2,
  };
}
