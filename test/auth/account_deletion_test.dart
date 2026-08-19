import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/local_data_wipe.dart';
import 'package:herculex/features/auth/data/account_deletion_service.dart';
import 'package:herculex/features/auth/data/auth_repository.dart';
import 'package:herculex/features/auth/data/local_auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_database.dart';
import 'fake_auth_provider_service.dart';

/// Account deletion is the one operation in the app that cannot be undone and
/// cannot be partially correct: leaving rows behind makes "delete my account"
/// untrue (GDPR Article 17, App Store 5.1.1(v)), and taking the bundled
/// catalogue with it would cost every deleting user a multi-second re-import
/// for no privacy gain.
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

  /// One row in every shape the wipe has to distinguish between.
  Future<void> seed() async {
    // A seeded catalogue exercise and a custom one, so the is_custom filter
    // has something to get wrong in both directions.
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
    // Children of the custom exercise: these must go by cascade, not by the
    // wipe naming their tables (which would take the seeded rows too).
    await db.customStatement(
      'INSERT INTO exercise_muscles (exercise_id, muscle, role) '
      "SELECT id, 'wipe-probe', 'primary' FROM exercise_catalog "
      "WHERE slug = 'bench-press' OR sync_uuid = 'ex-custom'",
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

    // Plain user data, including the GDPR Article 9 rows.
    await db.customStatement(
      'INSERT INTO workout_sessions (name, started_at, session_uuid, sync_uuid) '
      "VALUES ('Push A', 1000, 'sess-1', 'sess-sync-1')",
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
      'INSERT INTO health_samples (date_iso, kind, value) '
      "VALUES ('2026-08-19', 'steps', 8000)",
    );
    // Local-only feature state.
    await db.customStatement(
      'INSERT INTO rep_set_observations (exercise_slug, session_id, '
      'recorded_at, source, sensor_type, detected_reps, confirmed_reps, '
      'confidence, features_json) '
      "VALUES ('pull-up', 1, 1000, 'wrist', 'linear_acceleration', 8, 8, "
      "0.9, '{}')",
    );
  }

  group('wipeAllLocalUserData', () {
    test('removes user data but keeps the seeded catalogue', () async {
      // `openTestDatabase` already imports the bundled exercise catalogue, so
      // counts are asserted against that baseline rather than absolutely —
      // the catalogue surviving intact is half of what this test proves.
      final baseExercises = await countOf('exercise_catalog');
      final baseFoods = await countOf('foods');
      final baseMuscles = await countOf('exercise_muscles');
      expect(baseExercises, greaterThan(0));

      await seed();
      expect(await countOf('exercise_catalog'), baseExercises + 2);
      expect(await countOf('foods'), baseFoods + 2);

      await wipeAllLocalUserData(db);

      // The seeded rows survive, the custom ones do not.
      expect(await countOf('exercise_catalog'), baseExercises + 1);
      expect(await countOf('foods'), baseFoods + 1);
      final customs = await countOf('exercise_catalog WHERE is_custom = 1');
      expect(customs, 0);

      // The custom exercise's children went with it by cascade; the seeded
      // one's stayed, which is what keeps `exercise_muscles` off the clear
      // list in the first place.
      expect(await countOf('exercise_muscles'), baseMuscles + 1);

      // Everything that is user data end to end is gone.
      expect(await countOf('workout_sessions'), 0);
      expect(await countOf('body_measurements'), 0);
      expect(await countOf('cycle_logs'), 0);
      expect(await countOf('health_samples'), 0);
      expect(await countOf('rep_set_observations'), 0);
    });

    test('leaves no outbox rows behind for the deletes it just made', () async {
      await seed();
      // The outbox triggers fire on every write above, so there is real
      // content here before the wipe — the risk being guarded against is a
      // wipe that clears the outbox first and then refills it with its own
      // deletes, which would try to push into an account that no longer
      // exists on the next sign-in.
      expect(await countOf('pending_sync_ops'), greaterThan(0));

      await wipeAllLocalUserData(db);

      expect(await countOf('pending_sync_ops'), 0);
      expect(await countOf('sync_cursors'), 0);
    });

    test('leaves the database referentially intact', () async {
      await seed();
      await wipeAllLocalUserData(db);

      // `defer_foreign_keys` moves enforcement to commit rather than removing
      // it, so a commit that got here at all is already proof — but an
      // explicit check is what would catch a future table being added to the
      // clear list without its children.
      final violations = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violations, isEmpty);
    });
  });

  group('AccountDeletionService', () {
    late SharedPreferences prefs;
    late FakeAuthProviderService service;
    late AuthRepository auth;
    late AccountDeletionService deletion;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'profile': '{"name":"Martin"}'});
      prefs = await SharedPreferences.getInstance();
      service = FakeAuthProviderService();
      auth = AuthRepository(
        localRepository: LocalAuthRepository(prefs),
        authService: service,
      );
      deletion = AccountDeletionService(
        authRepository: auth,
        database: db,
        preferences: prefs,
      );
    });

    tearDown(() async {
      auth.dispose();
      await service.dispose();
    });

    test('deletes the account, the database and the preferences', () async {
      await seed();

      await deletion.deleteAccountAndWipeDevice();

      expect(service.deleteAccountCalls, 1);
      expect(await countOf('workout_sessions'), 0);
      expect(prefs.getKeys(), isEmpty);
    });

    test('a backend failure leaves the device untouched', () async {
      await seed();
      service.throwOnDeleteAccount = Exception('network down');

      await expectLater(
        deletion.deleteAccountAndWipeDevice(),
        throwsA(isA<Exception>()),
      );

      // The whole point of ordering the remote call first: nothing local may
      // be destroyed on a failure the user can retry.
      expect(await countOf('workout_sessions'), 1);
      expect(await countOf('body_measurements'), 1);
      expect(prefs.getKeys(), isNotEmpty);
    });
  });
}
