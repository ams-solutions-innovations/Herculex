import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/labs/data/labs_pdf_service.dart';
import 'package:herculex/features/labs/domain/labs_engine.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local PDF renders long labels, charts, empty categories and accented text',
    () async {
      final period = LabsPeriod(DateTime(2026, 10), DateTime(2026, 10, 16));
      final observations = [
        for (var day = 0; day < 15; day++)
          LabsObservation(
            id: '$day',
            category: LabsCategory.strength,
            metric: 'e1rm',
            at: DateTime(2026, 10, 1 + day),
            value: 70 + day * .4,
            unit: 'kg',
            source: 'fixture',
            stratum: 'Potisk s prsi · Športna oprema · Čvrst prijem · Železo',
            quality: 'estimated',
          ),
      ];
      final snapshot = LabsSnapshot(
        period: period,
        generatedAt: DateTime(2026, 10, 16),
        partial: true,
        findings: LabsEngine.analyze(
          observations,
          period,
          LabsCategory.values.toSet(),
        ),
        events: [
          {
            'at': '2026-10-04T00:00:00.000',
            'title': 'Začetek jemanja kreatina · 3 g',
          },
        ],
      );
      final bytes = await LabsPdfService().render(snapshot);
      expect(bytes.length, greaterThan(5000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final output = File('outputs/labs-qa-report.pdf');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes);
    },
  );
}
