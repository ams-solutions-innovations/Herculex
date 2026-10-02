import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/data/physique_checkin_service.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

class _FakeBackend implements PhysiqueCheckInBackend {
  _FakeBackend({this.result, this.error});

  Map<String, dynamic>? result;

  Object? error;
  int calls = 0;
  List<Map<String, dynamic>>? baselines;
  Map<String, dynamic>? current;
  Map<String, dynamic>? context;

  @override
  Future<(Map<String, dynamic>, Map<String, dynamic>)> analyzePhysiqueCheckIn({
    required List<Map<String, dynamic>> baselineImages,
    required Map<String, dynamic> currentImage,
    required Map<String, dynamic> context,
    String? userNote,
  }) async {
    calls++;
    baselines = baselineImages;
    current = currentImage;
    this.context = context;
    if (error != null) throw error!;
    return (
      result ??
          {
            'directionBand': {'low': 0.2, 'high': 0.6},
            'confidence': 'medium',
            'reason': 'Waist looks tighter.',
            'limitations': <String>[],
          },
      {'modelVersion': 'm1', 'knowledgeVersion': 'k1'},
    );
  }
}

Uint8List _img() => Uint8List.fromList([1, 2, 3]);

const _ctx = PhysiqueCheckInContext(
  phase: DietPhase.cut,
  weeksInPhase: 4,
  weightTrendKgPerWeek: -0.4,
);

Future<PhysiqueCheckInAnalysis> _run(
  _FakeBackend b, {
  bool consent = true,
  List<Uint8List>? baselines,
  Uint8List? current,
}) => PhysiqueCheckInService(b).analyze(
  baselineJpegs: baselines ?? [_img()],
  currentJpeg: current ?? _img(),
  context: _ctx,
  consentGranted: consent,
);

Matcher _failure(PhysiqueCheckInFailure kind) => throwsA(
  isA<PhysiqueCheckInException>().having((e) => e.kind, 'kind', kind),
);

void main() {
  group('PhysiqueCheckInService', () {
    test('refuses without consent before any backend call', () async {
      final b = _FakeBackend();
      await expectLater(
        _run(b, consent: false),
        _failure(PhysiqueCheckInFailure.consentRequired),
      );
      expect(b.calls, 0);
    });

    test('requires a baseline and a non-empty current image', () async {
      final b = _FakeBackend();
      await expectLater(
        _run(b, baselines: []),
        _failure(PhysiqueCheckInFailure.invalidInput),
      );
      await expectLater(
        _run(b, current: Uint8List(0)),
        _failure(PhysiqueCheckInFailure.invalidInput),
      );
      expect(b.calls, 0);
    });

    test(
      'returns evidence with provenance and sends minimal request',
      () async {
        final b = _FakeBackend();
        final out = await _run(b, baselines: [_img(), _img(), _img(), _img()]);
        expect(out.evidence.band.low, 0.2);
        expect(out.evidence.band.high, 0.6);
        expect(out.evidence.confidence, AssessmentConfidence.medium);
        expect(out.evidence.reason, 'Waist looks tighter.');
        expect(out.modelVersion, 'm1');
        expect(out.knowledgeVersion, 'k1');
        expect(b.baselines, hasLength(3));
        expect(b.current!['mimeType'], 'image/jpeg');
        expect(b.context!.keys.toSet(), {
          'phase',
          'weeksInPhase',
          'weightTrendKgPerWeek',
        });
        expect(b.context!['phase'], 'cut');
      },
    );

    test('absent or unrecognised confidence parses as unknown', () async {
      for (final conf in [null, 'certain']) {
        final out = await _run(
          _FakeBackend(
            result: {
              'directionBand': {'low': 0.1, 'high': 0.2},
              'confidence': ?conf,
              'reason': 'ok',
            },
          ),
        );
        expect(out.evidence.confidence, AssessmentConfidence.unknown);
      }
    });

    test('malformed band is rejected', () async {
      for (final band in [
        null,
        'x',
        {'low': 'a', 'high': 1},
        {'low': 0.1},
      ]) {
        await expectLater(
          _run(
            _FakeBackend(result: {'directionBand': band, 'confidence': 'high'}),
          ),
          _failure(PhysiqueCheckInFailure.malformedResponse),
        );
      }
    });

    test('strips percentages from the reason', () async {
      final out = await _run(
        _FakeBackend(
          result: {
            'directionBand': {'low': 0.1, 'high': 0.3},
            'confidence': 'high',
            'reason': 'Looks like 12% leaner, about 15 percent less bloat.',
          },
        ),
      );
      expect(out.evidence.reason.contains('%'), isFalse);
      expect(out.evidence.reason.contains('12'), isFalse);
      expect(out.evidence.reason.contains('percent'), isFalse);
    });

    test('empty reason after stripping uses the fallback', () async {
      final out = await _run(
        _FakeBackend(
          result: {
            'directionBand': {'low': 0.1, 'high': 0.3},
            'confidence': 'high',
            'reason': '12%',
          },
        ),
      );
      expect(
        out.evidence.reason,
        "Herculex AI couldn't describe this comparison.",
      );
    });

    test('limitations are trimmed, blanks dropped, capped at 3', () async {
      final out = await _run(
        _FakeBackend(
          result: {
            'directionBand': {'low': 0.1, 'high': 0.3},
            'confidence': 'high',
            'reason': 'ok',
            'limitations': [' a ', '', 'b', 'c', 'd'],
          },
        ),
      );
      expect(out.evidence.limitations, ['a', 'b', 'c']);

      final out2 = await _run(
        _FakeBackend(
          result: {
            'directionBand': {'low': 0.1, 'high': 0.3},
            'confidence': 'high',
            'reason': 'ok',
            'limitations': 'nope',
          },
        ),
      );
      expect(out2.evidence.limitations, isEmpty);
    });

    test('maps quota and other backend errors to typed failures', () async {
      await expectLater(
        _run(_FakeBackend(error: Exception('Daily AI checks are used up.'))),
        throwsA(
          isA<PhysiqueCheckInException>()
              .having(
                (e) => e.kind,
                'kind',
                PhysiqueCheckInFailure.quotaExhausted,
              )
              .having((e) => e.message, 'message', contains('tomorrow')),
        ),
      );
      await expectLater(
        _run(_FakeBackend(error: Exception('boom'))),
        _failure(PhysiqueCheckInFailure.unavailable),
      );
    });
  });
}
