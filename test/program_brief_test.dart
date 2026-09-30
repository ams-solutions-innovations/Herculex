import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/program_brief.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

Map<String, dynamic> _validBriefJson() => {
  'splitType': 'upper_lower',
  'periodizationModel': 'linear',
  'dayRoles': [
    {
      'dayIndex': 0,
      'role': 'intensity',
      'focus': 'Upper body heavy pressing',
      'rationale': 'Front-loads the week while recovery is freshest.',
    },
    {
      'dayIndex': 1,
      'role': 'volume',
      'focus': 'Lower body accumulation',
      'rationale': 'Builds volume before the next intensity day.',
    },
  ],
  'musclePriorities': [
    {
      'muscleId': 'chest',
      'priority': 'high',
      'confidence': 0.8,
      'rationale': 'Lagging relative to back.',
      'uncertainties': <String>[],
    },
    {
      'muscleId': 'back',
      'priority': 'medium',
      'confidence': 0.6,
      'rationale': 'Already proportionate.',
      'uncertainties': ['Limited pulling volume history'],
    },
  ],
  'phaseIntent': 'Build upper body symmetry ahead of the next block.',
};

/// A fresh deep copy of the valid fixture, so mutating tests never leak state
/// between cases.
Map<String, dynamic> _cloneValid() =>
    jsonDecode(jsonEncode(_validBriefJson())) as Map<String, dynamic>;

void main() {
  group('ProgramBrief.fromJson — valid payload', () {
    test('parses every field successfully', () {
      final brief = ProgramBrief.fromJson(_cloneValid());

      expect(brief.splitType, SplitType.upperLower);
      expect(brief.periodizationModel, PeriodizationModel.linear);
      expect(brief.phaseIntent, 'Build upper body symmetry ahead of the next block.');

      expect(brief.dayRoles, hasLength(2));
      expect(brief.dayRoles[0].dayIndex, 0);
      expect(brief.dayRoles[0].role, DayStressRole.intensity);
      expect(brief.dayRoles[0].focus, 'Upper body heavy pressing');
      expect(
        brief.dayRoles[0].rationale,
        'Front-loads the week while recovery is freshest.',
      );
      expect(brief.dayRoles[1].role, DayStressRole.volume);

      expect(brief.musclePriorities, hasLength(2));
      expect(brief.musclePriorities[0].muscleId, 'chest');
      expect(brief.musclePriorities[0].priority, ProgrammingPriorityLevel.high);
      expect(brief.musclePriorities[1].muscleId, 'back');
      expect(
        brief.musclePriorities[1].uncertainties,
        ['Limited pulling volume history'],
      );
    });
  });

  group('ProgramBrief.fromJson — strict enum rejection (D-02)', () {
    test('unknown splitType rejects the whole brief', () {
      final json = _cloneValid();
      json['splitType'] = 'push_pull_legs_v2';

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });

    test('unknown periodizationModel rejects the whole brief', () {
      final json = _cloneValid();
      json['periodizationModel'] = 'undulating';

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });

    test('unknown dayRoles[].role rejects the whole brief', () {
      final json = _cloneValid();
      (json['dayRoles'] as List)[0]['role'] = 'peak';

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });

    test(
      'unknown musclePriorities[].muscleId rejects the whole brief '
      '(reuses ProgrammingMusclePriority.fromJson verbatim — D-01)',
      () {
        final json = _cloneValid();
        (json['musclePriorities'] as List)[0]['muscleId'] = 'forearm';

        expect(() => ProgramBrief.fromJson(json), throwsFormatException);
      },
    );
  });

  group(
    'ProgramBrief.fromJson — exercise-shaped field prohibition (AIP-02)',
    () {
      for (final key in [
        'exerciseId',
        'sets',
        'reps',
        'load',
        'rpe',
        'tempo',
        'timeCap',
      ]) {
        test('rejects "$key" present at the top level', () {
          final json = _cloneValid();
          json[key] = 5;

          expect(() => ProgramBrief.fromJson(json), throwsFormatException);
        });

        test('rejects "$key" present inside a dayRoles entry', () {
          final json = _cloneValid();
          (json['dayRoles'] as List)[0][key] = 5;

          expect(() => ProgramBrief.fromJson(json), throwsFormatException);
        });

        test('rejects "$key" present inside a musclePriorities entry', () {
          final json = _cloneValid();
          (json['musclePriorities'] as List)[0][key] = 5;

          expect(() => ProgramBrief.fromJson(json), throwsFormatException);
        });
      }
    },
  );

  group('ProgramBrief.fromJson — missing required fields', () {
    test('missing phaseIntent throws', () {
      final json = _cloneValid();
      json.remove('phaseIntent');

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });

    test('absent dayRoles throws', () {
      final json = _cloneValid();
      json.remove('dayRoles');

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });

    test('empty dayRoles throws', () {
      final json = _cloneValid();
      json['dayRoles'] = <Map<String, dynamic>>[];

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });

    test('absent musclePriorities throws', () {
      final json = _cloneValid();
      json.remove('musclePriorities');

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });

    test('empty musclePriorities throws', () {
      final json = _cloneValid();
      json['musclePriorities'] = <Map<String, dynamic>>[];

      expect(() => ProgramBrief.fromJson(json), throwsFormatException);
    });
  });

  group('DayRoleBrief.fromJson — required fields', () {
    Map<String, dynamic> validDayRole() => {
      'dayIndex': 0,
      'role': 'intensity',
      'focus': 'Upper body heavy pressing',
      'rationale': 'Front-loads the week while recovery is freshest.',
    };

    test('parses a valid day role', () {
      final role = DayRoleBrief.fromJson(validDayRole());
      expect(role.dayIndex, 0);
      expect(role.role, DayStressRole.intensity);
      expect(role.focus, 'Upper body heavy pressing');
    });

    test('missing dayIndex throws', () {
      final json = validDayRole()..remove('dayIndex');
      expect(() => DayRoleBrief.fromJson(json), throwsFormatException);
    });

    test('negative dayIndex throws', () {
      final json = validDayRole()..['dayIndex'] = -1;
      expect(() => DayRoleBrief.fromJson(json), throwsFormatException);
    });

    test('missing role throws', () {
      final json = validDayRole()..remove('role');
      expect(() => DayRoleBrief.fromJson(json), throwsFormatException);
    });

    test('invalid role throws', () {
      final json = validDayRole()..['role'] = 'peak';
      expect(() => DayRoleBrief.fromJson(json), throwsFormatException);
    });

    test('missing focus throws', () {
      final json = validDayRole()..remove('focus');
      expect(() => DayRoleBrief.fromJson(json), throwsFormatException);
    });

    test('missing rationale throws (D-09 per-day rationale is required)', () {
      final json = validDayRole()..remove('rationale');
      expect(() => DayRoleBrief.fromJson(json), throwsFormatException);
    });
  });

  group('ProgramBrief round-trip (toJson -> fromJson) — lossless', () {
    test('produces a deep-equal object field by field', () {
      final original = ProgramBrief.fromJson(_cloneValid());

      final roundTripped = ProgramBrief.fromJson(original.toJson());

      expect(roundTripped.splitType, original.splitType);
      expect(roundTripped.periodizationModel, original.periodizationModel);
      expect(roundTripped.phaseIntent, original.phaseIntent);

      expect(roundTripped.dayRoles, hasLength(original.dayRoles.length));
      for (var i = 0; i < original.dayRoles.length; i++) {
        expect(roundTripped.dayRoles[i].dayIndex, original.dayRoles[i].dayIndex);
        expect(roundTripped.dayRoles[i].role, original.dayRoles[i].role);
        expect(roundTripped.dayRoles[i].focus, original.dayRoles[i].focus);
        expect(
          roundTripped.dayRoles[i].rationale,
          original.dayRoles[i].rationale,
        );
      }

      expect(
        roundTripped.musclePriorities,
        hasLength(original.musclePriorities.length),
      );
      for (var i = 0; i < original.musclePriorities.length; i++) {
        expect(
          roundTripped.musclePriorities[i].muscleId,
          original.musclePriorities[i].muscleId,
        );
        expect(
          roundTripped.musclePriorities[i].priority,
          original.musclePriorities[i].priority,
        );
        expect(
          roundTripped.musclePriorities[i].confidence,
          original.musclePriorities[i].confidence,
        );
        expect(
          roundTripped.musclePriorities[i].rationale,
          original.musclePriorities[i].rationale,
        );
        expect(
          roundTripped.musclePriorities[i].uncertainties,
          original.musclePriorities[i].uncertainties,
        );
      }
    });
  });
}
