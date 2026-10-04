/// Client-side parser for Herculex AI's program design brief.
///
/// This is the authoritative gate on AI-sourced program design output. The
/// server-side `normalizeProgramBriefResult` (Edge Function) is a first-pass
/// shape guard; this Dart parser is the gate the app actually trusts before
/// a brief is allowed to pre-fill the builder or be persisted (D-02, AIP-02,
/// AIP-03). Every enum field is checked against a closed, canonical
/// vocabulary before being resolved — never the lenient
/// `fromId(id, orElse: () => default)` pattern used elsewhere for user
/// input — because a silent default is exactly the failure mode an
/// AI-sourced value must never get.
///
/// Pure Dart — no Flutter, no Riverpod imports. `domain/` stays plain Dart.
library;

import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

/// Keys that must never appear anywhere in a Herculex AI program brief, at
/// any nesting depth. Their presence would mean the model attempted to
/// prescribe exercise-level specifics — the one hard prohibition Herculex AI
/// can never cross (AIP-02): `SmartProgramPlanner` remains the sole selector
/// of exercises, sets, reps, load, RPE, tempo and metcon time caps, always.
/// This scan is the proof that boundary holds even for AI-generated input,
/// and it runs before any field-by-field parsing begins.
const _prohibitedExerciseKeys = <String>{
  'exerciseId',
  'sets',
  'reps',
  'load',
  'rpe',
  'tempo',
  'timeCap',
};

void _rejectProhibitedExerciseFields(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String && _prohibitedExerciseKeys.contains(key)) {
        throw FormatException(
          'Herculex AI program brief contains a prohibited exercise-shaped '
          'field "$key". Herculex AI never prescribes exercises, sets, '
          'reps, load, RPE, tempo or metcon time caps — that stays with '
          'SmartProgramPlanner.',
        );
      }
      _rejectProhibitedExerciseFields(entry.value);
    }
  } else if (value is List) {
    for (final item in value) {
      _rejectProhibitedExerciseFields(item);
    }
  }
}

SplitType _strictSplitType(Object? value) {
  if (value is String) {
    for (final candidate in SplitType.values) {
      if (candidate.id == value) return candidate;
    }
  }
  throw FormatException(
    'Unknown splitType in Herculex AI program brief: $value',
  );
}

PeriodizationModel _strictPeriodizationModel(Object? value) {
  if (value is String) {
    for (final candidate in PeriodizationModel.values) {
      if (candidate.id == value) return candidate;
    }
  }
  throw FormatException(
    'Unknown periodizationModel in Herculex AI program brief: $value',
  );
}

DayStressRole _strictDayStressRole(Object? value) {
  if (value is String) {
    for (final candidate in DayStressRole.values) {
      if (candidate.id == value) return candidate;
    }
  }
  throw FormatException(
    'Unknown dayRoles[].role in Herculex AI program brief: $value',
  );
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Herculex AI program brief is missing $key.');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('Herculex AI program brief is missing $key.');
}

/// One day's role assignment within a [ProgramBrief], with its own per-day
/// rationale (D-09 — a structured array, not one paragraph for the whole
/// brief).
class DayRoleBrief {
  const DayRoleBrief({
    required this.dayIndex,
    required this.role,
    required this.focus,
    required this.rationale,
  });

  final int dayIndex;
  final DayStressRole role;
  final String focus;
  final String rationale;

  factory DayRoleBrief.fromJson(Map<String, dynamic> json) {
    final dayIndex = _requiredInt(json, 'dayIndex');
    if (dayIndex < 0) {
      throw const FormatException(
        'Herculex AI program brief day role has a negative dayIndex.',
      );
    }
    return DayRoleBrief(
      dayIndex: dayIndex,
      role: _strictDayStressRole(json['role']),
      focus: _requiredString(json, 'focus'),
      rationale: _requiredString(json, 'rationale'),
    );
  }

  Map<String, dynamic> toJson() => {
    'dayIndex': dayIndex,
    'role': role.id,
    'focus': focus,
    'rationale': rationale,
  };
}

/// Herculex AI's program design brief: split, periodization model, per-day
/// roles with rationale, muscle priorities, and phase intent — never an
/// exercise list, set/rep scheme, load, RPE, tempo or metcon time cap
/// (AIP-02). [musclePriorities] reuses Dream Physique's existing
/// [ProgrammingMusclePriority] shape verbatim (D-01), so
/// `block_builder_view.dart`'s `_applyDreamPhysiqueTuning()` needs zero new
/// apply logic to consume it. Any unknown enum value anywhere in the payload
/// rejects the whole brief (D-02) — never a silent per-field default.
class ProgramBrief {
  const ProgramBrief({
    required this.splitType,
    required this.periodizationModel,
    required this.dayRoles,
    required this.musclePriorities,
    required this.phaseIntent,
  });

  final SplitType splitType;
  final PeriodizationModel periodizationModel;
  final List<DayRoleBrief> dayRoles;
  final List<ProgrammingMusclePriority> musclePriorities;
  final String phaseIntent;

  factory ProgramBrief.fromJson(Map<String, dynamic> json) {
    // Must run before any field-by-field parsing: a whole-brief rejection on
    // the first prohibited key found, never a partial/silent strip.
    _rejectProhibitedExerciseFields(json);

    final splitType = _strictSplitType(json['splitType']);
    final periodizationModel = _strictPeriodizationModel(
      json['periodizationModel'],
    );

    final rawDayRoles = json['dayRoles'];
    if (rawDayRoles is! List || rawDayRoles.isEmpty) {
      throw const FormatException('Herculex AI program brief has no dayRoles.');
    }
    final dayRoles = rawDayRoles
        .map((value) {
          if (value is! Map) {
            throw const FormatException(
              'Invalid day role in Herculex AI program brief.',
            );
          }
          return DayRoleBrief.fromJson(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);

    final rawMusclePriorities = json['musclePriorities'];
    if (rawMusclePriorities is! List || rawMusclePriorities.isEmpty) {
      throw const FormatException(
        'Herculex AI program brief has no musclePriorities.',
      );
    }
    final musclePriorities = rawMusclePriorities
        .map((value) {
          if (value is! Map) {
            throw const FormatException(
              'Invalid muscle priority in Herculex AI program brief.',
            );
          }
          return ProgrammingMusclePriority.fromJson(
            Map<String, dynamic>.from(value),
          );
        })
        .toList(growable: false);

    return ProgramBrief(
      splitType: splitType,
      periodizationModel: periodizationModel,
      dayRoles: dayRoles,
      musclePriorities: musclePriorities,
      phaseIntent: _requiredString(json, 'phaseIntent'),
    );
  }

  /// The canonical persisted shape — plan 27-09's `HerculexAiBriefService`
  /// writes exactly this JSON into the new `HerculexAiProgramBriefs` table,
  /// and later reads it back through [fromJson].
  Map<String, dynamic> toJson() => {
    'splitType': splitType.id,
    'periodizationModel': periodizationModel.id,
    'dayRoles': [for (final role in dayRoles) role.toJson()],
    'musclePriorities': [
      for (final priority in musclePriorities)
        {
          'muscleId': priority.muscleId,
          'priority': priority.priority.wireValue,
          'confidence': priority.confidence,
          'rationale': priority.rationale,
          'uncertainties': priority.uncertainties,
        },
    ],
    'phaseIntent': phaseIntent,
  };
}
