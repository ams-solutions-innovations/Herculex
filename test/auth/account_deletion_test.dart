import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/local_data_wipe.dart';
import 'package:herculex/features/auth/data/account_deletion_service.dart';
import 'package:herculex/features/auth/data/auth_repository.dart';
import 'package:herculex/features/auth/data/local_auth_repository.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_database.dart';
import 'fake_auth_provider_service.dart';

/// Account deletion and local data wipe are the operations in the app that
/// cannot be partially correct: leaving rows behind makes "delete my account"
/// or "clear all data" untrue (GDPR Article 17, App Store 5.1.1(v)), and
/// taking the bundled catalogue with it would cost every user a multi-second
/// re-import for no privacy gain.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  Future<int> countOf(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  /// One row in every shape the wipe has to distinguish between, including
  /// `KeyAction.restrict` FK edges (`circuit_exercises -> exercise_catalog`),
  /// GDPR Art. 9 `joint_pain_logs`, and raw `WatchCommandInbox` tables.
  Future<void> seed({Directory? docsDir}) async {
    await db.customStatement(
      'INSERT INTO exercise_catalog (name, slug, is_custom, primary_muscle, '
      'equipment, mechanics, force, plane) '
      "VALUES ('Bench Press', 'bench-press', 0, 'Chest', 'barbell', "
      "'compound', 'push', 'horizontal')",
    );
    await db.customStatement(
      'INSERT INTO exercise_catalog (name, is_custom, sync_uuid, primary_muscle, '
      'equipment, mechanics, force, plane) '
      "VALUES ('My Cable Thing', 1, 'ex-custom', 'Chest', 'cable', "
      "'isolation', 'push', 'horizontal')",
    );
    await db.customStatement(
      'INSERT INTO exercise_muscles (exercise_id, muscle, role) '
      "SELECT id, 'wipe-probe', 'primary' FROM exercise_catalog "
      "WHERE slug = 'bench-press' OR sync_uuid = 'ex-custom'",
    );

    final customExerciseIdRow = await db
        .customSelect(
          "SELECT id FROM exercise_catalog WHERE sync_uuid = 'ex-custom'",
        )
        .getSingle();
    final customExerciseId = customExerciseIdRow.read<int>('id');

    // `circuit_exercises.exercise_id` has `KeyAction.restrict` onto
    // `exercise_catalog.id` — previously missing from `local_data_wipe.dart`,
    // which caused transaction commit rollback when deleting custom exercises!
    await db.customStatement(
      'INSERT INTO workout_circuits (id, name, rounds, rest_seconds, sync_uuid) '
      "VALUES (1, 'Metcon A', 4, 60, 'wc-1')",
    );
    await db.customStatement(
      'INSERT INTO circuit_exercises (circuit_id, exercise_id, order_index, sync_uuid) '
      "VALUES (1, $customExerciseId, 0, 'ce-1')",
    );

    await db.customStatement(
      'INSERT INTO foods (name, catalogue_id, is_custom, kcal_per100g, '
      'protein_per100g, carbs_per100g, fat_per100g) '
      "VALUES ('Seeded Oats', 'cat-1', 0, 380, 13, 60, 7)",
    );
    await db.customStatement(
      'INSERT INTO foods (name, is_custom, sync_uuid, kcal_per100g, '
      'protein_per100g, carbs_per100g, fat_per100g) '
      "VALUES ('My Protein Shake', 1, 'food-custom', 120, 24, 3, 1)",
    );

    String? workoutPhotoRelPath;
    if (docsDir != null) {
      final workoutPhotoDir = Directory(
        p.join(docsDir.path, workoutPhotoFolderName),
      )..createSync(recursive: true);
      workoutPhotoRelPath = '$workoutPhotoFolderName/sess-1.jpg';
      File(p.join(workoutPhotoDir.path, 'sess-1.jpg')).writeAsBytesSync([1, 2]);
    }

    await db.customStatement(
      'INSERT INTO workout_sessions (name, started_at, session_uuid, sync_uuid, photo_path) '
      "VALUES ('Push A', 1000, 'sess-1', 'sess-sync-1', "
      "${workoutPhotoRelPath == null ? 'NULL' : "'$workoutPhotoRelPath'"})",
    );
    await db.customStatement(
      'INSERT INTO body_measurements (date_iso, metric, value, sync_uuid) '
      "VALUES ('2026-08-19', 'weight', 82.5, 'bm-1')",
    );
    await db.customStatement(
      'INSERT INTO cycle_logs (date_iso, phase, sync_uuid) '
      "VALUES ('2026-08-19', 'menstrual', 'cl-1')",
    );
    await db.customStatement(
      'INSERT INTO joint_pain_logs (date_iso, joint, severity, sync_uuid) '
      "VALUES ('2026-08-19', 'left_shoulder', 2, 'jp-1')",
    );
    await db.customStatement(
      'INSERT INTO health_samples (date_iso, kind, value) '
      "VALUES ('2026-08-19', 'steps', 8000)",
    );
    await db.customStatement(
      'INSERT INTO buddy_choreography_slots '
      '(buddy_session_id, slot_id, order_index) '
      "VALUES ('buddy-sess-1', 'slot-1', 0)",
    );
    await db.customStatement(
      "INSERT INTO achievements (id, unlocked_at, sync_uuid) VALUES ('first_workout', 1700000000, 'ach-1')",
    );
    await db.customStatement(
      "INSERT INTO processed_watch_commands (kind, command_id, applied_at) "
      "VALUES ('water', 'cmd-1', 1700000000)",
    );
    await db.customStatement(
      "INSERT INTO physique_goals (id, sync_uuid) VALUES (1, 'pg-1')",
    );
    await db.customStatement(
      'INSERT INTO physique_assessments (goal_id, kind, date_iso, sync_uuid) '
      "VALUES (1, 'analysis', '2026-08-19', 'pa-1')",
    );
    await db.customStatement(
      'INSERT INTO physique_roadmap_phases '
      '(goal_id, order_index, phase_type, planned_weeks, sync_uuid) '
      "VALUES (1, 0, 'maintain', 4, 'pr-1')",
    );
    await db.customStatement(
      'INSERT INTO physique_photos '
      '(goal_id, role, pose, date_iso, relative_path, sync_uuid) '
      "VALUES (1, 'baseline', 'front', '2026-08-19', 'physique/pg-1/a.jpg', "
      "'pp-1')",
    );
  }

  group('wipeAllLocalUserData', () {
    test('classifies every single Drift table in AppDatabase', () {
      final driftTables = db.allTables.map((t) => t.actualTableName).toSet();
      final classified = <String>{
        ...catalogueTables,
        ...fullyClearedTables,
        ...syncMetadataTables,
        ...preservedReferenceTables,
      };
      expect(
        classified,
        equals(driftTables),
        reason:
            'Every Drift table must be explicitly classified in local_data_wipe.dart',
      );
    });

    test('removes user data, custom FK-referenced rows, raw watch tables, and photo files while keeping seeded catalogue', () async {
      final docsDir = await Directory.systemTemp.createTemp('hx_wipe_test_');
      addTearDown(() async {
        if (await docsDir.exists()) {
          await docsDir.delete(recursive: true);
        }
      });

      final baseExercises = await countOf('exercise_catalog');
      final baseFoods = await countOf('foods');
      final baseMuscles = await countOf('exercise_muscles');
      expect(baseExercises, greaterThan(0));

      await seed(docsDir: docsDir);
      expect(await countOf('exercise_catalog'), baseExercises + 2);
      expect(await countOf('foods'), baseFoods + 2);
      expect(
        File(p.join(docsDir.path, workoutPhotoFolderName, 'sess-1.jpg'))
            .existsSync(),
        isTrue,
      );

      await wipeAllLocalUserData(db, documentsDirectory: docsDir);

      // The seeded rows survive, the custom ones (even with circuit_exercises FK!) do not.
      expect(await countOf('exercise_catalog'), baseExercises + 1);
      expect(await countOf('foods'), baseFoods + 1);
      expect(await countOf('exercise_catalog WHERE is_custom = 1'), 0);
      expect(await countOf('exercise_muscles'), baseMuscles + 1);

      for (final t in [
        'workout_sessions',
        'workout_circuits',
        'circuit_exercises',
        'body_measurements',
        'cycle_logs',
        'joint_pain_logs',
        'health_samples',
        'buddy_choreography_slots',
        'achievements',
        'processed_watch_commands',
        'physique_goals',
        'physique_assessments',
        'physique_roadmap_phases',
        'physique_photos',
      ]) {
        expect(await countOf(t), 0, reason: t);
      }

      expect(
        Directory(p.join(docsDir.path, workoutPhotoFolderName)).existsSync(),
        isFalse,
      );
    });

    test('leaves no outbox rows behind for the deletes it just made', () async {
      await seed();
      expect(await countOf('pending_sync_ops'), greaterThan(0));

      await wipeAllLocalUserData(db);

      expect(await countOf('pending_sync_ops'), 0);
      expect(await countOf('sync_cursors'), 0);
    });

    test('leaves the database referentially intact', () async {
      await seed();
      await wipeAllLocalUserData(db);

      final violations = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(violations, isEmpty);
    });
  });

  group('AccountDeletionService', () {
    late SharedPreferences prefs;
    late FakeAuthProviderService service;
    late AuthRepository auth;
    late LocalProfileRepository profileRepo;
    late AccountDeletionService deletion;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = FakeAuthProviderService();
      auth = AuthRepository(
        localRepository: LocalAuthRepository(prefs),
        authService: service,
      );
      profileRepo = LocalProfileRepository(prefs);
      await profileRepo.save(
        const Profile(
          name: 'Martin',
          goal: FitnessGoal.maintenance,
          activityLevel: ActivityLevel.lightlyActive,
          heightCm: 180,
          weightKg: 82,
        ),
        syncToLog: false,
      );
      deletion = AccountDeletionService(
        authRepository: auth,
        database: db,
        preferences: prefs,
        localProfileRepository: profileRepo,
      );
    });

    tearDown(() async {
      profileRepo.dispose();
      auth.dispose();
      await service.dispose();
    });

    test('deletes the account, the database, preferences, and emits null profile', () async {
      await seed();
      final emittedProfiles = <Profile?>[];
      final sub = profileRepo.watch().listen(emittedProfiles.add);
      await Future<void>.delayed(Duration.zero);

      await deletion.deleteAccountAndWipeDevice();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(service.deleteAccountCalls, 1);
      expect(await countOf('workout_sessions'), 0);
      expect(prefs.getKeys(), isEmpty);
      expect(profileRepo.currentProfile, isNull);
      expect(emittedProfiles.last, isNull);
    });

    test('clearAllLocalDataOnly wipes SQLite, preferences, and profile without deleting cloud account', () async {
      await seed();

      await deletion.clearAllLocalDataOnly();

      expect(service.deleteAccountCalls, 0);
      expect(await countOf('workout_sessions'), 0);
      expect(await countOf('joint_pain_logs'), 0);
      expect(prefs.getKeys(), isEmpty);
      expect(profileRepo.currentProfile, isNull);
    });

    test('a backend failure leaves the device untouched', () async {
      await seed();
      service.throwOnDeleteAccount = Exception('network down');

      await expectLater(
        deletion.deleteAccountAndWipeDevice(),
        throwsA(isA<Exception>()),
      );

      expect(await countOf('workout_sessions'), 1);
      expect(await countOf('body_measurements'), 1);
      expect(prefs.getKeys(), isNotEmpty);
      expect(profileRepo.currentProfile, isNotNull);
    });
  });
}
