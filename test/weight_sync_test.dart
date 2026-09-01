import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SharedPreferences prefs;
  late LocalProfileRepository profileRepo;
  late MeasurementsRepository measurementsRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openTestDatabase();

    profileRepo = LocalProfileRepository(prefs);
    measurementsRepo = MeasurementsRepository(db, profileRepo);
    profileRepo.setMeasurementsRepository(measurementsRepo);
  });

  tearDown(() async {
    profileRepo.dispose();
    await db.close();
  });

  group('Weight Synchronization', () {
    test('logging bodyweight in repository updates profile weight', () async {
      final initialProfile = const Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.lightlyActive,
        weightKg: 70.0,
      );
      await profileRepo.save(initialProfile, syncToLog: false);

      await measurementsRepo.logMeasurement(
        dateIso: '2026-08-20',
        metric: 'bodyweight',
        value: 75.5,
      );

      expect(profileRepo.currentProfile?.weightKg, equals(75.5));
    });

    test(
      'saving profile weight creates today bodyweight measurement log',
      () async {
        final profile = const Profile(
          goal: FitnessGoal.maintenance,
          activityLevel: ActivityLevel.lightlyActive,
          weightKg: 82.0,
        );
        await profileRepo.save(profile, syncToLog: true);

        final latestLog = await measurementsRepo.latestBodyweightKg();
        expect(latestLog, equals(82.0));
      },
    );

    test(
      'deleting latest bodyweight measurement syncs profile weight to previous entry',
      () async {
        await measurementsRepo.logMeasurement(
          dateIso: '2026-08-10',
          metric: 'bodyweight',
          value: 80.0,
        );
        await measurementsRepo.logMeasurement(
          dateIso: '2026-08-15',
          metric: 'bodyweight',
          value: 81.5,
        );

        expect(profileRepo.currentProfile?.weightKg, equals(81.5));

        final rows = await measurementsRepo.watchMetric('bodyweight').first;
        final latestRow = rows.firstWhere((r) => r.dateIso == '2026-08-15');

        await measurementsRepo.deleteMeasurement(latestRow.id);

        expect(profileRepo.currentProfile?.weightKg, equals(80.0));
        expect(await measurementsRepo.latestBodyweightKg(), equals(80.0));
      },
    );
  });
}
