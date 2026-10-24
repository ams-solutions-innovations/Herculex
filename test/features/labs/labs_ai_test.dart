import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/labs/data/labs_ai_service.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';

class _Backend implements LabsAiBackend {
  _Backend(this.summary);
  final String summary;
  @override
  Future<Map<String, dynamic>> explainLabs(Map<String, dynamic> facts) async =>
      {
        'summary': summary,
        'suggestions': [
          'Keep logging comparable sessions.',
          'Review your recorded context.',
        ],
      };
}

void main() {
  test('AI transport contains aggregates only from selected categories', () {
    final s = LabsSnapshot(
      period: LabsPeriod(DateTime(2026, 1), DateTime(2026, 2)),
      generatedAt: DateTime(2026, 2),
      events: [
        {'note': 'private note'},
      ],
      findings: [
        LabsFinding(
          id: 'private id',
          category: LabsCategory.sleep,
          title: 'private title',
          detail: 'private detail',
          support: 'Collecting data',
          points: const [],
          coverage: 0,
        ),
      ],
    );
    final facts = LabsAiService.facts(s, {LabsCategory.sleep});
    expect(facts.toString().contains('private'), false);
    expect((facts['findings'] as List).length, 1);
    expect(
      LabsAiService.facts(s, {LabsCategory.nutrition})['findings'],
      isEmpty,
    );
  });
  test(
    'unconfigured, invented numbers and causal claims never replace local findings',
    () async {
      final facts = {'findings': <dynamic>[]};
      await expectLater(LabsAiService(null).explain(facts), throwsStateError);
      await expectLater(
        LabsAiService(
          _Backend('Your strength improved by 99 percent.'),
        ).explain(facts),
        throwsFormatException,
      );
      await expectLater(
        LabsAiService(_Backend('Sleep caused your progress.')).explain(facts),
        throwsFormatException,
      );
      final good = await LabsAiService(
        _Backend('Your records are still building a baseline.'),
      ).explain(facts);
      expect(good.summary, contains('baseline'));
    },
  );
}
