import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/settings/data/user_data_export_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_database.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.fixed);
  final DateTime fixed;
  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  test(
    'exportAndShare writes complete user JSON archive while excluding seeded catalogue and auth keys',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('hx_export_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues({
        'herculex.auth_session': '{"uid":"secret-uid"}',
        'supabase.auth.token': 'secret-bearer-token',
        'herculex.theme_mode': 'dark',
      });
      final prefs = await SharedPreferences.getInstance();
      final profileRepo = LocalProfileRepository(prefs);
      addTearDown(profileRepo.dispose);

      await profileRepo.save(
        const Profile(
          name: 'Alex',
          goal: FitnessGoal.maintenance,
          activityLevel: ActivityLevel.lightlyActive,
          heightCm: 178,
          weightKg: 76.5,
        ),
        syncToLog: false,
      );

      // Seeded row (is_custom = 0) vs custom row (is_custom = 1)
      await db.customStatement(
        'INSERT INTO foods (name, catalogue_id, is_custom, kcal_per100g, '
        'protein_per100g, carbs_per100g, fat_per100g) '
        "VALUES ('Seeded Apple', 'cat-apple', 0, 52, 0.3, 14, 0.2)",
      );
      await db.customStatement(
        'INSERT INTO foods (name, is_custom, sync_uuid, kcal_per100g, '
        'protein_per100g, carbs_per100g, fat_per100g) '
        "VALUES ('My Custom Whey', 1, 'custom-whey-1', 390, 80, 6, 5)",
      );
      await db.customStatement(
        'INSERT INTO workout_sessions (name, started_at, session_uuid, sync_uuid) '
        "VALUES ('Upper Hypertrophy', 1700000000, 'sess-u1', 'sync-u1')",
      );
      await db.customStatement(
        'INSERT INTO joint_pain_logs (date_iso, joint, severity, sync_uuid) '
        "VALUES ('2026-10-20', 'right_knee', 2, 'jp-export-1')",
      );

      XFile? sharedXFile;
      final service = UserDataExportService(
        database: db,
        profileRepository: profileRepo,
        preferences: prefs,
        clock: _FixedClock(DateTime.utc(2026, 10, 26, 10, 30)),
        tempDirectoryProvider: () async => tempDir,
        shareFile: (file) async {
          sharedXFile = file;
          return const ShareResult('', ShareResultStatus.success);
        },
      );

      final exportedFile = await service.exportAndShare();

      expect(await exportedFile.exists(), isTrue);
      expect(exportedFile.path, endsWith('herculex_export_2026-10-26.json'));
      expect(sharedXFile, isNotNull);
      expect(sharedXFile!.path, exportedFile.path);

      final decoded =
          jsonDecode(await exportedFile.readAsString()) as Map<String, dynamic>;
      expect(decoded['format'], 'herculex_user_data_export_v1');
      expect((decoded['profile'] as Map<String, dynamic>)['name'], 'Alex');

      final exportedPrefs = decoded['preferences'] as Map<String, dynamic>;
      expect(exportedPrefs['herculex.theme_mode'], 'dark');
      expect(exportedPrefs.containsKey('herculex.auth_session'), isFalse);
      expect(exportedPrefs.containsKey('supabase.auth.token'), isFalse);

      final tables = decoded['tables'] as Map<String, dynamic>;
      final sessions = tables['workout_sessions'] as List<dynamic>;
      expect(sessions, hasLength(1));
      expect(
        (sessions.single as Map<String, dynamic>)['name'],
        'Upper Hypertrophy',
      );
      final jointLogs = tables['joint_pain_logs'] as List<dynamic>;
      expect(jointLogs, hasLength(1));

      final customCat = decoded['customCatalogue'] as Map<String, dynamic>;
      final customFoods = customCat['foods'] as List<dynamic>;
      expect(customFoods, hasLength(1));
      expect(
        (customFoods.single as Map<String, dynamic>)['name'],
        'My Custom Whey',
      );
    },
  );
}
