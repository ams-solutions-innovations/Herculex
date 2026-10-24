import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herculex/features/labs/data/labs_repository.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late LabsRepository labs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    labs = LabsRepository(prefs);
  });
  tearDown(() async => labs.changes.close());
  Future<void> enable() => labs.saveConsent(
    LabsConsent(
      enabled: true,
      categories: LabsCategory.values.toSet(),
      since: DateTime(2026, 1),
    ),
  );
  test('disabled Labs captures no supplement data', () async {
    await SupplementRepository.markTakenInPrefs(
      prefs,
      'creatine',
      true,
      date: DateTime(2026, 1),
    );
    expect(labs.records('intake'), isEmpty);
  });
  test(
    'historical dose snapshot survives product edits and confirmed skip differs from unknown',
    () async {
      await enable();
      final supplements = SupplementRepository(prefs);
      addTearDown(supplements.dispose);
      await supplements.saveSupplements([
        const Supplement(
          id: 'c',
          name: 'Creatine',
          doseAmount: 3,
          doseUnit: 'g',
          schedule: SupplementSchedule.none,
        ),
      ]);
      await LabsRepository.recordIntake(
        prefs,
        'c',
        true,
        DateTime(2026, 1, 2),
        recordedAt: DateTime(2026, 1, 2),
      );
      await supplements.saveSupplements([
        const Supplement(
          id: 'c',
          name: 'Creatine',
          doseAmount: 5,
          doseUnit: 'g',
          schedule: SupplementSchedule.none,
        ),
      ]);
      await LabsRepository.recordIntake(
        prefs,
        'c',
        false,
        DateTime(2026, 1, 3),
        recordedAt: DateTime(2026, 1, 3),
      );
      final records = labs.records('intake');
      expect(records.length, 2);
      expect(records.first['product']['doseAmount'], 3);
      expect(records.last['status'], 'confirmed_skipped');
      expect(records.where((r) => r['at'].startsWith('2026-01-04')), isEmpty);
      expect(labs.records('definitions').length, 2);
      await LabsRepository.recordIntake(
        prefs,
        'c',
        true,
        DateTime(2026, 1, 2),
        recordedAt: DateTime(2026, 2),
      );
      expect(labs.records('intake').first['product']['doseAmount'], 3);
      await LabsRepository.recordIntake(
        prefs,
        'c',
        true,
        DateTime(2026, 1, 1),
        recordedAt: DateTime(2026, 2),
      );
      expect(labs.records('intake').first['product']['doseAmount'], isNull);
    },
  );
  test(
    'revoking consent blocks further checkins and supplement events',
    () async {
      await enable();
      await labs.checkIn(DateTime(2026, 1, 2), {'energy': 0});
      await labs.saveConsent(const LabsConsent());
      await LabsRepository.recordIntake(prefs, 'c', true, DateTime(2026, 1, 3));
      expect(labs.records('intake'), isEmpty);
      expect(
        () => labs.checkIn(DateTime(2026, 1, 3), {'energy': 4}),
        throwsStateError,
      );
    },
  );
  test('selective deletion leaves original trackers intact', () async {
    await enable();
    await prefs.setString('supplements_config_v1', '[]');
    await labs.put('report', '1', {'at': '2026-01-01'});
    await labs.checkIn(DateTime(2026, 1), {'energy': 0});
    await labs.deleteReports();
    expect(labs.records('checkin').length, 1);
    await labs.deleteAnalysis();
    expect(labs.consent.enabled, false);
    expect(prefs.getString('supplements_config_v1'), '[]');
  });
  test(
    'experiment protocol freezes goal and baseline before intervention',
    () async {
      await enable();
      await labs.startExperiment('rest', DateTime(2026, 1), 2);
      final e = labs.records('experiment').single;
      expect(e['baselineEnd'], '2026-01-15T00:00:00.000');
      expect(e['end'], '2026-01-29T00:00:00.000');
      expect(e['target'], 2);
      await labs.stopExperiment(e);
      expect(labs.records('experiment').single['status'], 'stopped');
    },
  );
}
