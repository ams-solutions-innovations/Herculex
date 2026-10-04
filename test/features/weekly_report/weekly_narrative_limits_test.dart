import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_facts.dart';

int _tsConst(String source, String name) {
  final m = RegExp(
    'const $name = '
    r'(\d+);',
  ).firstMatch(source);
  if (m == null) fail('$name not found in index.ts');
  return int.parse(m.group(1)!);
}

void main() {
  group('limits match the Edge Function (IN-03)', () {
    final source = File(
      'supabase/functions/gemini-analyze/index.ts',
    ).readAsStringSync();

    test('character limits', () {
      expect(
        _tsConst(source, 'maxWeeklyReportSummaryChars'),
        WeeklyNarrativeLimits.summaryChars,
      );
      expect(
        _tsConst(source, 'maxWeeklyReportSuggestionChars'),
        WeeklyNarrativeLimits.suggestionChars,
      );
      expect(
        _tsConst(source, 'maxWeeklyReportFactsChars'),
        WeeklyNarrativeLimits.factsChars,
      );
      expect(WeeklyReportFacts.maxJsonLength, WeeklyNarrativeLimits.factsChars);
    });

    test('suggestion count bounds', () {
      final m = RegExp(
        r'raw\.suggestions\.length < (\d+) \|\|\s*raw\.suggestions\.length > (\d+)',
      ).firstMatch(source);
      expect(m, isNotNull);
      expect(int.parse(m!.group(1)!), WeeklyNarrativeLimits.minSuggestions);
      expect(int.parse(m.group(2)!), WeeklyNarrativeLimits.maxSuggestions);
    });
  });

  group('number-in-facts fixture shared with the server (WR-05)', () {
    final cases =
        jsonDecode(
              File(
                'test/fixtures/weekly_report_number_cases.json',
              ).readAsStringSync(),
            )
            as List;

    test('fixture is substantial', () => expect(cases.length >= 20, isTrue));

    for (final raw in cases) {
      final tc = raw as Map<String, dynamic>;
      test(tc['name'] as String, () {
        final text = tc['text'] as String;
        final expected = (tc['expectedNumbers'] as List)
            .map((n) => (n as num).toDouble())
            .toList();
        expect(extractNarrativeNumbers(text), expected);
        final stray = firstNumberNotInFacts([text], tc['facts']);
        expect(stray == null, tc['ok'] as bool);
      });
    }
  });

  group('WeeklyNarrative.fromJson with facts', () {
    const json = {
      'summary': 'You trained 4 times and ate 2,150 kcal.',
      'suggestions': ['Keep going.', 'Sleep well.'],
    };

    test('accepts numbers present in facts', () {
      final n = WeeklyNarrative.fromJson(json, facts: {'kcal': 2150});
      expect(n.suggestions, hasLength(2));
    });

    test('rejects a number absent from facts', () {
      expect(
        () => WeeklyNarrative.fromJson(json, facts: {'kcal': 1900}),
        throwsA(isA<FormatException>()),
      );
    });

    test('no facts means no number check; stored decode never orphans', () {
      expect(() => WeeklyNarrative.fromJson(json), returnsNormally);
      expect(WeeklyNarrative.tryDecodeStored(jsonEncode(json)), isNotNull);
    });
  });
}
