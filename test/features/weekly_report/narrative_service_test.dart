import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_narrative_service.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

class _FakeWeeklyReportBackend implements WeeklyReportBackend {
  _FakeWeeklyReportBackend({this.result, this.provenance, this.error});

  final Map<String, dynamic>? result;
  final Map<String, dynamic>? provenance;
  final Object? error;
  Map<String, dynamic>? receivedFacts;
  int calls = 0;

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateWeeklyReportNarrative({required Map<String, dynamic> facts}) async {
    calls++;
    receivedFacts = facts;
    if (error != null) throw error!;
    return (result ?? <String, dynamic>{}, provenance ?? <String, dynamic>{});
  }
}

const _facts = <String, dynamic>{
  'week': '2026-W40',
  'nutrition': {'avgProteinG': 142},
};

const _goodResult = <String, dynamic>{
  'summary': 'Protein averaged 142 g on days you trained.',
  'suggestions': ['Keep logging meals.', 'Aim for 7 hours of sleep.'],
};

Future<WeeklyReportNarrativeException> _failure(Object error) async {
  final service = WeeklyReportNarrativeService(
    _FakeWeeklyReportBackend(error: error),
  );
  try {
    await service.generate(_facts);
  } on WeeklyReportNarrativeException catch (e) {
    return e;
  }
  fail('expected WeeklyReportNarrativeException');
}

Future<WeeklyReportNarrativeException> _rejected(
  Map<String, dynamic> result,
) async {
  final service = WeeklyReportNarrativeService(
    _FakeWeeklyReportBackend(result: result),
  );
  try {
    await service.generate(_facts);
  } on WeeklyReportNarrativeException catch (e) {
    return e;
  }
  fail('expected WeeklyReportNarrativeException');
}

void main() {
  test('a number absent from the facts is rejected', () async {
    final e = await _rejected(const {
      'summary': 'Protein averaged 180 g on days you trained.',
      'suggestions': ['Keep logging meals.', 'Sleep a little more.'],
    });
    expect(e.kind, NarrativeFailureKind.rejected);
  });

  group('WeeklyReportNarrativeService.generate success', () {
    test(
      'returns a validated narrative with provenance passed through',
      () async {
        final backend = _FakeWeeklyReportBackend(
          result: _goodResult,
          provenance: {'modelVersion': 'm1', 'knowledgeVersion': 'k1'},
        );
        final (narrative, provenance) = await WeeklyReportNarrativeService(
          backend,
        ).generate(_facts);

        expect(narrative.summary, contains('142 g'));
        expect(narrative.suggestions, hasLength(2));
        expect(provenance, {'modelVersion': 'm1', 'knowledgeVersion': 'k1'});
      },
    );

    test('forwards the facts map to the backend unchanged', () async {
      final backend = _FakeWeeklyReportBackend(result: _goodResult);
      final facts = {
        'week': '2026-W40',
        'training': {'sessions': 4},
        'nutrition': {'avgProteinG': 142},
      };
      await WeeklyReportNarrativeService(backend).generate(facts);

      expect(backend.calls, 1);
      expect(identical(backend.receivedFacts, facts), isTrue);
    });
  });

  group('WeeklyReportNarrativeService.generate failure classification', () {
    test('daily quota text maps to quotaExhausted', () async {
      final e = await _failure(
        Exception(
          'Today\'s Weekly report summaries (5/day) are used up — try again '
          'tomorrow.',
        ),
      );
      expect(e.kind, NarrativeFailureKind.quotaExhausted);
    });

    test('connection failure maps to offline', () async {
      final e = await _failure(
        Exception(
          'Cannot connect to the server. Please check your internet '
          'connection.',
        ),
      );
      expect(e.kind, NarrativeFailureKind.offline);
    });

    test('timeout maps to offline', () async {
      final e = await _failure(
        Exception('AI analysis timed out. Please try again.'),
      );
      expect(e.kind, NarrativeFailureKind.offline);
    });

    test('not-configured maps to unconfigured', () async {
      final e = await _failure(
        Exception('AI analysis is not configured. Build with credentials.'),
      );
      expect(e.kind, NarrativeFailureKind.unconfigured);
    });

    test('the real Unconfigured backend maps to unconfigured', () async {
      final service = WeeklyReportNarrativeService(
        const UnconfiguredGeminiBackend(),
      );
      await expectLater(
        service.generate(const {}),
        throwsA(
          isA<WeeklyReportNarrativeException>().having(
            (e) => e.kind,
            'kind',
            NarrativeFailureKind.unconfigured,
          ),
        ),
      );
    });

    test('any other error maps to unavailable', () async {
      final e = await _failure(StateError('boom'));
      expect(e.kind, NarrativeFailureKind.unavailable);
    });

    test('one suggestion maps to rejected', () async {
      final e = await _rejected({
        'summary': 'A fine summary.',
        'suggestions': ['Only one.'],
      });
      expect(e.kind, NarrativeFailureKind.rejected);
    });

    test('missing summary maps to rejected', () async {
      final e = await _rejected({
        'suggestions': ['One.', 'Two.'],
      });
      expect(e.kind, NarrativeFailureKind.rejected);
    });

    test('causal wording (because) in the summary maps to rejected', () async {
      final e = await _rejected({
        'summary': 'Your weight rose because you slept less.',
        'suggestions': ['One.', 'Two.'],
      });
      expect(e.kind, NarrativeFailureKind.rejected);
    });

    test('causal wording in a suggestion maps to rejected', () async {
      final e = await _rejected({
        'summary': 'A fine summary.',
        'suggestions': ['Sleep more because it helps.', 'Two.'],
      });
      expect(e.kind, NarrativeFailureKind.rejected);
    });
  });

  group('WeeklyReportNarrativeException messages', () {
    test('are fixed user-safe sentences that never leak raw text', () async {
      const secret = 'SECRET_RAW_TEXT_XYZ';
      final errors = <Object>[
        Exception('Today\'s x are used up — try again tomorrow. $secret'),
        Exception('Cannot connect to the server. $secret'),
        Exception('AI analysis is not configured. $secret'),
        StateError(secret),
      ];
      for (final error in errors) {
        final e = await _failure(error);
        expect(e.message, isNotEmpty);
        expect(e.message, isNot(contains(secret)));
        expect(e.message, isNot(contains('Exception')));
        expect(e.toString(), e.message);
      }
      final rejected = await _rejected({
        'summary': 'It rose because of $secret.',
        'suggestions': ['One.', 'Two.'],
      });
      expect(rejected.message, isNot(contains(secret)));
      expect(rejected.message, isNot(contains('because')));
    });

    test('each kind has its own distinct message', () async {
      final messages = <String>{
        (await _failure(Exception('used up'))).message,
        (await _failure(Exception('Cannot connect'))).message,
        (await _failure(Exception('not configured'))).message,
        (await _failure(StateError('x'))).message,
        (await _rejected({'summary': ''})).message,
      };
      expect(messages, hasLength(5));
    });
  });

  group('house rule: the AI never writes', () {
    test('the service source has no database dependency', () {
      final source = File(
        'lib/features/weekly_report/data/weekly_report_narrative_service.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('AppDatabase')));
      expect(source, isNot(contains('appDatabaseProvider')));
      expect(source, isNot(contains('package:drift')));
    });
  });
}
