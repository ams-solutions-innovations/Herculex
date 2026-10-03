import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/domain/causal_language_guard.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';

Map<String, dynamic> _valid({
  Object? summary = 'Your protein tended to go with higher training volume.',
  Object? suggestions = const ['Keep protein steady.', 'Add one easy walk.'],
}) => {'summary': summary, 'suggestions': suggestions};

void main() {
  group('CausalLanguageGuard.firstViolation', () {
    const rejected = <String, String>{
      'because you slept less': 'because',
      'This caused fatigue': 'caused',
      'it causes soreness': 'causes',
      'causing a dip': 'causing',
      'The cause is unclear': 'cause',
      'led to a drop': 'led to',
      'leads to gains': 'leads to',
      'leading to a plateau': 'leading to',
      'due to poor sleep': 'due to',
      'owing to stress': 'owing to',
      'As a result, you lifted less': 'as a result',
      'resulted in a dip': 'resulted in',
      'results in a dip': 'results in',
      'resulting in a dip': 'resulting in',
      'thanks to rest': 'thanks to',
      'which is why you improved': 'which is why',
      "that's why you improved": "that's why",
      'that’s why you improved': 'that’s why',
      'that is why you improved': 'that is why',
      'this is why you improved': 'this is why',
      'the reason you improved': 'the reason',
      'driven by sleep': 'driven by',
      'explains why you improved': 'explains why',
      'responsible for the gain': 'responsible for',
      'the cause is sleep': 'cause',
    };
    rejected.forEach((text, token) {
      test('rejects "$text"', () {
        expect(CausalLanguageGuard.firstViolation([text]), token);
      });
    });

    test('is case-insensitive and tolerant of extra whitespace', () {
      expect(
        CausalLanguageGuard.firstViolation(['DUE   TO sleep']),
        'due   to',
      );
      expect(CausalLanguageGuard.firstViolation(['BECAUSE of it']), 'because');
    });

    const accepted = <String>[
      'Your protein tended to go with higher training volume',
      'Take caution on heavy days',
      'Add a pause at the bottom',
      'Sleep tended to go with better sessions',
      'Causal inference is hard',
      'The reasoning is simple',
      'Volume rose while sleep dipped',
    ];
    for (final text in accepted) {
      test('accepts "$text"', () {
        expect(CausalLanguageGuard.firstViolation([text]), isNull);
      });
    }

    test('scans every text and returns the first hit', () {
      expect(
        CausalLanguageGuard.firstViolation(['fine', 'due to x', 'because y']),
        'due to',
      );
      expect(CausalLanguageGuard.firstViolation(const []), isNull);
    });

    test('pattern list is the single source of truth', () {
      expect(CausalLanguageGuard.patterns, isNotEmpty);
      expect(CausalLanguageGuard.patterns, contains('responsible for'));
    });
  });

  group('WeeklyNarrative.fromJson', () {
    test('accepts summary plus 2 or 3 suggestions and trims', () {
      final n = WeeklyNarrative.fromJson(
        _valid(summary: '  Good week.  ', suggestions: [' A ', 'B', ' C']),
      );
      expect(n.summary, 'Good week.');
      expect(n.suggestions, ['A', 'B', 'C']);
      expect(WeeklyNarrative.fromJson(_valid()).suggestions, hasLength(2));
    });

    final bad = <String, Map<String, dynamic>>{
      'missing summary': {
        'suggestions': ['a', 'b'],
      },
      'blank summary': _valid(summary: '   '),
      'non-string summary': _valid(summary: 5),
      'summary too long': _valid(summary: 'x' * 701),
      'suggestions not a list': _valid(suggestions: 'a'),
      'suggestions missing': {'summary': 'ok'},
      'one suggestion': _valid(suggestions: ['a']),
      'four suggestions': _valid(suggestions: ['a', 'b', 'c', 'd']),
      'non-string suggestion': _valid(suggestions: ['a', 3]),
      'blank suggestion': _valid(suggestions: ['a', '  ']),
      'suggestion too long': _valid(suggestions: ['a', 'x' * 301]),
    };
    bad.forEach((name, json) {
      test('throws FormatException: $name', () {
        expect(() => WeeklyNarrative.fromJson(json), throwsFormatException);
      });
    });

    test('accepts exactly the limits', () {
      final n = WeeklyNarrative.fromJson(
        _valid(summary: 'x' * 700, suggestions: ['y' * 300, 'z']),
      );
      expect(n.summary, hasLength(700));
    });

    test('rejects causal wording and names the token', () {
      expect(
        () => WeeklyNarrative.fromJson(
          _valid(summary: 'You lifted less because you slept less.'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('because'),
          ),
        ),
      );
      expect(
        () => WeeklyNarrative.fromJson(
          _valid(suggestions: ['Rest, due to fatigue.', 'ok']),
        ),
        throwsFormatException,
      );
    });

    test('checkCausalLanguage false skips only the guard', () {
      final causal = _valid(summary: 'Because sleep.');
      expect(
        WeeklyNarrative.fromJson(causal, checkCausalLanguage: false).summary,
        'Because sleep.',
      );
      expect(
        () => WeeklyNarrative.fromJson(
          _valid(suggestions: ['a']),
          checkCausalLanguage: false,
        ),
        throwsFormatException,
      );
    });
  });

  group('WeeklyNarrative.tryDecodeStored / toJson', () {
    test('round-trips', () {
      final n = WeeklyNarrative.fromJson(_valid());
      final back = WeeklyNarrative.tryDecodeStored(jsonEncode(n.toJson()));
      expect(back, isNotNull);
      expect(back!.summary, n.summary);
      expect(back.suggestions, n.suggestions);
    });

    test('returns null for null, malformed and structurally invalid', () {
      expect(WeeklyNarrative.tryDecodeStored(null), isNull);
      expect(WeeklyNarrative.tryDecodeStored('not json'), isNull);
      expect(WeeklyNarrative.tryDecodeStored('[1,2]'), isNull);
      expect(WeeklyNarrative.tryDecodeStored('{"summary":"x"}'), isNull);
    });

    test('does not apply the guard to stored text', () {
      final stored = jsonEncode(_valid(summary: 'Because of old wording.'));
      expect(WeeklyNarrative.tryDecodeStored(stored), isNotNull);
    });
  });
}
