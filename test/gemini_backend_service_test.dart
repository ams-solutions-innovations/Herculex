import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

void main() {
  group('UnconfiguredGeminiBackend.generateProgramBrief', () {
    test(
      'throws the same not-configured message as every other method',
      () async {
        const backend = UnconfiguredGeminiBackend();

        Object? caughtFromGenerateProgramBrief;
        try {
          await backend.generateProgramBrief(
            profileInputs: {'goal': 'strength'},
          );
        } catch (error) {
          caughtFromGenerateProgramBrief = error;
        }

        Object? caughtFromSibling;
        try {
          await backend.analyzeRamblerText(text: 'chicken and rice');
        } catch (error) {
          caughtFromSibling = error;
        }

        expect(caughtFromGenerateProgramBrief, isA<Exception>());
        expect(caughtFromSibling, isA<Exception>());
        expect(
          caughtFromGenerateProgramBrief.toString(),
          caughtFromSibling.toString(),
        );
        expect(
          caughtFromGenerateProgramBrief.toString(),
          contains('AI analysis is not configured'),
        );
      },
    );
  });

  group('UnconfiguredGeminiBackend.generateWeeklyReportNarrative', () {
    test(
      'throws the same not-configured message as every other method',
      () async {
        const backend = UnconfiguredGeminiBackend();

        Object? caught;
        try {
          await backend.generateWeeklyReportNarrative(
            facts: {'week': '2026-W40'},
          );
        } catch (error) {
          caught = error;
        }

        Object? caughtFromSibling;
        try {
          await backend.analyzeRamblerText(text: 'chicken and rice');
        } catch (error) {
          caughtFromSibling = error;
        }

        expect(caught, isA<Exception>());
        expect(caught.toString(), caughtFromSibling.toString());
        expect(caught.toString(), contains('AI analysis is not configured'));
      },
    );

    test('is reachable through the WeeklyReportBackend interface', () {
      const WeeklyReportBackend backend = UnconfiguredGeminiBackend();
      expect(backend, isA<WeeklyReportBackend>());
    });
  });

  group('_resultWithProvenance extraction (via reflection helper)', () {
    test(
      'a successful response yields result and provenance as separate maps',
      () {
        final data = <String, dynamic>{
          'result': {'splitType': 'ppl'},
          'provenance': {
            'modelVersion': 'gemini-2.5-flash',
            'knowledgeVersion': 'kb-2026.10-1',
          },
        };

        final (result, provenance) = extractResultWithProvenance(data);

        expect(result, {'splitType': 'ppl'});
        expect(provenance, {
          'modelVersion': 'gemini-2.5-flash',
          'knowledgeVersion': 'kb-2026.10-1',
        });
      },
    );

    test('a response missing provenance yields an empty provenance map', () {
      final data = <String, dynamic>{
        'result': {'splitType': 'ppl'},
      };

      final (result, provenance) = extractResultWithProvenance(data);

      expect(result, {'splitType': 'ppl'});
      expect(provenance, <String, dynamic>{});
    });

    test(
      'a response with a plain (non-String-keyed) provenance Map is cast defensively',
      () {
        final data = <String, dynamic>{
          'result': {'splitType': 'ppl'},
          'provenance': {'modelVersion': 'gemini-2.5-flash'},
        };
        // Simulate the wire-decoded shape where nested maps may not already
        // be Map<String, dynamic> (mirrors how _resultMap tolerates this for
        // 'result').
        final looseData = <String, dynamic>{
          'result': data['result'],
          'provenance': Map<dynamic, dynamic>.from(data['provenance'] as Map),
        };

        final (result, provenance) = extractResultWithProvenance(looseData);

        expect(result, {'splitType': 'ppl'});
        expect(provenance, {'modelVersion': 'gemini-2.5-flash'});
      },
    );

    test('a response with an invalid result still throws via _resultMap', () {
      final data = <String, dynamic>{
        'result': 'not a map',
        'provenance': {'modelVersion': 'x'},
      };

      expect(() => extractResultWithProvenance(data), throwsException);
    });
  });
}

/// Standalone helper mirroring [SupabaseGeminiBackend]'s private
/// `_resultWithProvenance` logic, so the extraction behavior can be unit
/// tested without a live Supabase client. Kept in sync with the production
/// implementation's contract: reuses the same result-map validation and
/// tolerates a missing/malformed 'provenance' key by returning an empty map
/// rather than throwing.
(Map<String, dynamic> result, Map<String, dynamic> provenance)
extractResultWithProvenance(Map<String, dynamic> data) {
  final result = _resultMap(data);
  final provenance = data['provenance'];
  return (
    result,
    provenance is Map<String, dynamic>
        ? provenance
        : provenance is Map
        ? Map<String, dynamic>.from(provenance)
        : <String, dynamic>{},
  );
}

Map<String, dynamic> _resultMap(Map<String, dynamic> data) {
  final result = data['result'];
  if (result is Map<String, dynamic>) return result;
  if (result is Map) return Map<String, dynamic>.from(result);
  throw Exception('AI analysis returned an invalid JSON result.');

  test(
    'analyzePhysiqueCheckIn on Unconfigured throws not-configured',
    () async {
      const backend = UnconfiguredGeminiBackend();
      await expectLater(
        backend.analyzePhysiqueCheckIn(
          baselineImages: const [],
          currentImage: const {},
          context: const {},
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not configured'),
          ),
        ),
      );
    },
  );
}
