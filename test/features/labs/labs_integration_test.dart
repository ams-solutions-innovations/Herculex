import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/labs/application/labs_providers.dart';
import 'package:herculex/features/labs/data/labs_data_source.dart';
import 'package:herculex/features/labs/data/labs_pdf_service.dart';
import 'package:herculex/features/labs/data/labs_repository.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import '../../support/test_database.dart';

class _Pdf extends LabsPdfService {
  _Pdf(this.dir);
  final Directory dir;
  int calls = 0;
  Future<void> Function()? beforeSave;
  @override
  Future<File> save(LabsSnapshot snapshot) async {
    calls++;
    await beforeSave?.call();
    return File(
      '${dir.path}/${snapshot.period.id}-${snapshot.revision}.pdf',
    ).writeAsString('fixture');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late LabsRepository repo;
  late LabsDataSource source;
  late OpenFoodFactsClient off;
  late Directory dir;
  late _Pdf pdf;
  setUp(() async {
    db = await openTestDatabase();
    SharedPreferences.setMockInitialValues({});
    repo = LabsRepository(await SharedPreferences.getInstance());
    off = OpenFoodFactsClient();
    source = LabsDataSource(
      db,
      NutritionRepository(db, off, const SystemClock()),
      repo,
    );
    dir = await Directory.systemTemp.createTemp('herculex-labs-test-');
    pdf = _Pdf(dir);
    await repo.saveConsent(
      LabsConsent(
        enabled: true,
        history: true,
        categories: {LabsCategory.sleep},
        since: DateTime(2026, 1, 3),
      ),
    );
    for (var day = 1; day <= 30; day++) {
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: labsDate(DateTime(2026, 1, day)),
              kind: 'sleep_hours',
              value: 7 + day / 100,
            ),
          );
    }
  });
  tearDown(() async {
    off.dispose();
    await repo.changes.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'adapter deduplicates daily device readings and respects category/history choices',
    () async {
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-01-04',
              kind: 'sleep_hours',
              value: 8,
            ),
          );
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-01-04',
              kind: 'steps',
              value: 8000,
            ),
          );
      var rows = await source.load(DateTime(2026, 2));
      expect(rows.length, 30);
      expect(rows.singleWhere((o) => labsDate(o.at) == '2026-01-04').value, 8);
      await repo.saveConsent(
        LabsConsent(
          enabled: true,
          history: false,
          categories: {LabsCategory.sleep},
          since: DateTime(2026, 1, 16),
        ),
      );
      rows = await source.load(DateTime(2026, 2));
      expect(rows.every((o) => !o.at.isBefore(DateTime(2026, 1, 16))), true);
    },
  );
  test(
    'report catchup is idempotent, partial and revisions reflect historical corrections',
    () async {
      final runner = LabsReportRunner(repo, source, pdf);
      await runner.catchUp(DateTime(2026, 2));
      expect(repo.records('report').length, 2);
      expect(pdf.calls, 2);
      final first = repo
          .records('report')
          .firstWhere((r) => r['start'].startsWith('2026-01-01'));
      expect(first['partial'], true);
      await runner.catchUp(DateTime(2026, 2));
      expect(pdf.calls, 2);
      await (db.update(db.healthSamples)
            ..where((t) => t.dateIso.equals('2026-01-04')))
          .write(const HealthSamplesCompanion(value: Value(9)));
      await runner.catchUp(DateTime(2026, 2));
      expect(repo.records('report').length, 3);
      expect(pdf.calls, 3);
      expect(repo.records('report').any((r) => r['revision'] == 2), true);
    },
  );
  test(
    'revocation during PDF generation removes pending export and persists no report',
    () async {
      pdf.beforeSave = () => repo.saveConsent(const LabsConsent());
      await LabsReportRunner(repo, source, pdf).catchUp(DateTime(2026, 2));
      expect(repo.records('report'), isEmpty);
      expect(await dir.list().toList(), isEmpty);
    },
  );
}
