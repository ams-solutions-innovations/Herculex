import '../../workouts/domain/set_type.dart';
import 'periodization.dart';
import 'slot_prescription.dart';
import 'slot_role.dart';

/// A prescription resolved for one slot in one week, plus the sentence that
/// explains every number in it.
class ResolvedPrescription {
  const ResolvedPrescription({
    required this.prescription,
    required this.restSeconds,
    required this.why,
    this.perSide = false,
  });

  final SlotPrescription prescription;
  final int restSeconds;

  /// Shown on tap. Built only from the factors that actually moved a number.
  final String why;

  /// True for unilateral work — the set count is per side.
  final bool perSide;

  String format() =>
      '${prescription.format()}${perSide ? ' per side' : ''}';
}

/// The one place a prescribed set is turned into numbers.
///
/// ```
/// resolve = archetype(model, role, phase)
///         × WeekPrescription(intensity, volume)
///         × exerciseAdjust(mechanics, modality, unilateral)
///         × overlay(user template)
/// ```
///
/// Keeping it a single pure function is what lets every cell in the preview
/// answer "why this?".
abstract final class PrescriptionResolver {
  /// Default rest by role, in seconds. A segment may override it.
  static const restByRole = <SlotRole, int>{
    SlotRole.main: 240,
    SlotRole.supplemental: 180,
    SlotRole.accessory: 120,
    SlotRole.isolation: 75,
    SlotRole.conditioning: 60,
  };

  /// Modalities where a percentage of 1RM is not a meaningful prescription —
  /// the stack numbers are not comparable and the strength curve is different.
  static const _percentUnfriendly = {
    'machine_selectorized',
    'cable',
    'band',
    'bodyweight',
  };

  static ResolvedPrescription resolve({
    required PeriodizationModel model,
    required SlotRole role,
    required WeekPrescription week,
    SlotPrescription? template,
    String mechanics = 'compound',
    String modality = 'barbell',
    bool unilateral = false,
  }) {
    final base = template ?? archetype(model: model, role: role, week: week);

    // Week factors. A ramp is never scaled — "work up to a heavy single" does
    // not become "work up to 1.1 heavy singles".
    var out = base.scaled(
      intensityFactor: week.intensityFactor,
      volumeFactor: week.volumeFactor,
    );

    // Exercise-specific adjustment.
    out = _adjustForExercise(
      out,
      role: role,
      mechanics: mechanics,
      modality: modality,
    );

    return ResolvedPrescription(
      prescription: out,
      restSeconds: _rest(out, role),
      perSide: unilateral,
      why: _why(
        model: model,
        role: role,
        week: week,
        modality: modality,
        mechanics: mechanics,
        usedTemplate: template != null,
        templateName: template?.name,
      ),
    );
  }

  /// The default prescription for a `(model, role, phase)` combination, before
  /// any week scaling.
  static SlotPrescription archetype({
    required PeriodizationModel model,
    required SlotRole role,
    required WeekPrescription week,
  }) {
    switch (role) {
      case SlotRole.main:
        return switch (model) {
          PeriodizationModel.maxEffort => SlotPrescription.builtIns
              .firstWhere((p) => p.name == 'Westside ME'),
          PeriodizationModel.block => _blockMain(week.blockPhase),
          PeriodizationModel.concurrent => const SlotPrescription(
              name: 'Concurrent main',
              segments: [
                WorkSegment(
                  sets: 5,
                  repsMin: 5,
                  intent: Intent.rir2,
                  percentOf1Rm: 0.8,
                ),
              ],
            ),
          PeriodizationModel.linear || PeriodizationModel.none =>
            const SlotPrescription(
              name: 'Linear main',
              segments: [
                WorkSegment(
                  sets: 3,
                  repsMin: 5,
                  intent: Intent.rir2,
                  percentOf1Rm: 0.8,
                ),
              ],
            ),
        };

      case SlotRole.supplemental:
        // Under max effort the supplemental lift carries the volume the ME
        // single cannot.
        return model == PeriodizationModel.maxEffort
            ? const SlotPrescription(
                name: 'Repetition method',
                segments: [
                  WorkSegment(
                    sets: 3,
                    repsMin: 8,
                    repsMax: 12,
                    intent: Intent.toFailure,
                  ),
                ],
              )
            : const SlotPrescription(
                name: 'Supplemental',
                segments: [
                  WorkSegment(
                    sets: 4,
                    repsMin: 6,
                    repsMax: 8,
                    intent: Intent.rir2,
                  ),
                ],
              );

      case SlotRole.accessory:
        return const SlotPrescription(
          name: 'Accessory',
          segments: [
            WorkSegment(
              sets: 3,
              repsMin: 8,
              repsMax: 12,
              intent: Intent.rir2,
            ),
          ],
        );

      case SlotRole.isolation:
        return const SlotPrescription(
          name: 'Isolation',
          segments: [
            WorkSegment(
              sets: 3,
              repsMin: 12,
              repsMax: 15,
              intent: Intent.rir1,
            ),
          ],
        );

      case SlotRole.conditioning:
        return const SlotPrescription(
          name: 'Conditioning',
          segments: [
            WorkSegment(
              sets: 1,
              repsMin: 1,
              intent: Intent.amrap,
              setType: SetType.amrap,
              restSeconds: 0,
              meta: {'capSeconds': 600},
            ),
          ],
        );
    }
  }

  static SlotPrescription _blockMain(String? phase) => switch (phase) {
        'accumulation' => const SlotPrescription(
            name: 'Accumulation main',
            segments: [
              WorkSegment(
                sets: 4,
                repsMin: 8,
                intent: Intent.rir3,
                percentOf1Rm: 0.7,
              ),
            ],
          ),
        'realization' => const SlotPrescription(
            name: 'Realization main',
            segments: [
              WorkSegment(
                sets: 3,
                repsMin: 2,
                intent: Intent.rir1,
                percentOf1Rm: 0.92,
              ),
            ],
          ),
        // transmutation and anything unlabelled
        _ => const SlotPrescription(
            name: 'Transmutation main',
            segments: [
              WorkSegment(
                sets: 5,
                repsMin: 5,
                intent: Intent.rir2,
                percentOf1Rm: 0.82,
              ),
            ],
          ),
      };

  /// Machines and isolation work do not take a percentage prescription well,
  /// and single-joint work belongs at higher reps.
  static SlotPrescription _adjustForExercise(
    SlotPrescription p, {
    required SlotRole role,
    required String mechanics,
    required String modality,
  }) {
    final dropPercent = _percentUnfriendly.contains(modality);
    final addReps = mechanics == 'isolation' && !role.isHeavy;
    if (!dropPercent && !addReps) return p;

    return SlotPrescription(
      name: p.name,
      note: p.note,
      segments: [
        for (final s in p.segments)
          // Built directly rather than via copyWith: dropping the percentage
          // means setting it to null, which copyWith's `??` cannot express.
          WorkSegment(
            sets: s.sets,
            repsMin: addReps && !s.isRamp ? s.repsMin + 2 : s.repsMin,
            repsMax: addReps && !s.isRamp ? s.repsMax + 3 : s.repsMax,
            intent: s.intent,
            percentOf1Rm: dropPercent ? null : s.percentOf1Rm,
            setType: s.setType,
            restSeconds: s.restSeconds,
            meta: s.meta,
          ),
      ],
    );
  }

  static int _rest(SlotPrescription p, SlotRole role) {
    for (final s in p.segments) {
      final r = s.restSeconds;
      if (r != null) return r;
    }
    return restByRole[role] ?? 120;
  }

  static String _why({
    required PeriodizationModel model,
    required SlotRole role,
    required WeekPrescription week,
    required String modality,
    required String mechanics,
    required bool usedTemplate,
    String? templateName,
  }) {
    final parts = <String>[];

    if (usedTemplate && templateName != null) {
      parts.add('Your "$templateName" template');
    } else {
      parts.add('${model.label} · ${role.label.toLowerCase()} slot');
    }

    if (week.blockPhase != null) {
      parts.add('${week.blockPhase} week');
    }
    if (week.isDeload) {
      parts.add('planned deload');
    }

    final volumeShift = ((week.volumeFactor - 1) * 100).round();
    final intensityShift = ((week.intensityFactor - 1) * 100).round();
    if (volumeShift != 0) {
      parts.add('volume ${volumeShift > 0 ? '+' : ''}$volumeShift%');
    }
    if (intensityShift != 0) {
      parts.add('intensity ${intensityShift > 0 ? '+' : ''}$intensityShift%');
    }

    if (_percentUnfriendly.contains(modality)) {
      parts.add('load by feel — percentages do not transfer on this equipment');
    } else if (mechanics == 'isolation' && !role.isHeavy) {
      parts.add('reps raised for single-joint work');
    }

    return '${parts.join(' · ')}.';
  }
}
