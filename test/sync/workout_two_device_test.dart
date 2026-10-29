import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_service.dart';

import '../support/test_database.dart';
import 'fake_sync_backend_service.dart';

/// A workout logged on one device has to look the same on the other: the
/// session, its exercises (stock and user-made), and every set. These run two
/// real databases and two real `SyncService`s against one fake cloud, so the
/// FK translation (a stock exercise travels as its slug, a custom one as its
/// uuid), the push/pull ordering and the cascade of a delete are all the real
/// code - only the network is fake.
///
/// The stock exercise has a *different local id* on each device on purpose:
/// that is what a phone and a browser look like after their asset imports.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const userId = 'user-1';

  late AppDatabase phone;
  late AppDatabase web;
  late FakeSyncBackendService cloud;
  late SyncService phoneSync;
  late SyncService webSync;

  setUp(() async {
    phone = await openTestDatabase();
    web = await openTestDatabase();
    cloud = FakeSyncBackendService();
    phoneSync = SyncService(db: phone, backend: cloud);
    webSync = SyncService(db: web, backend: cloud);
  });

  tearDown(() async {
    await phoneSync.dispose();
    await webSync.dispose();
    cloud.close();
    await phone.close();
    await web.close();
  });

  Future<int> exercise(
    AppDatabase into, {
    required String name,
    String? slug,
    bool custom = false,
  }) => into
      .into(into.exerciseCatalog)
      .insert(
        ExerciseCatalogCompanion.insert(
          name: name,
          primaryMuscle: 'Quads',
          equipment: 'Barbell',
          mechanics: 'compound',
          force: 'push',
          plane: 'axial',
          slug: Value(slug),
          isCustom: Value(custom),
        ),
      );

  /// The same stock exercise on both devices, under different local ids.
  Future<(int phoneId, int webId)> seedStockSquat() async {
    final onPhone = await exercise(phone, name: 'Squat', slug: 'squat');
    await exercise(web, name: 'Bench Press', slug: 'bench-press');
    final onWeb = await exercise(web, name: 'Squat', slug: 'squat');
    expect(onPhone, isNot(onWeb));
    return (onPhone, onWeb);
  }

  Future<int> setEntry(
    AppDatabase into, {
    required int workoutExerciseId,
    required int index,
    required double kg,
    required int reps,
  }) => into
      .into(into.setEntries)
      .insert(
        SetEntriesCompanion.insert(
          workoutExerciseId: workoutExerciseId,
          setIndex: index,
          weightKg: kg,
          reps: reps,
        ),
      );

  Future<int> workoutExercise(
    AppDatabase into, {
    required int sessionId,
    required int exerciseId,
    required int order,
  }) => into
      .into(into.workoutExercises)
      .insert(
        WorkoutExercisesCompanion.insert(
          sessionId: sessionId,
          exerciseId: exerciseId,
          orderIndex: order,
        ),
      );

  /// Logs a two-exercise session on [phone]: stock squat (two sets) and a
  /// user-made exercise (one set). Returns the session's local id.
  Future<int> logSession({required int squatId, required int customId}) async {
    final sessionId = await phone
        .into(phone.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 10, 27, 9)),
        );
    final squat = await workoutExercise(
      phone,
      sessionId: sessionId,
      exerciseId: squatId,
      order: 0,
    );
    final custom = await workoutExercise(
      phone,
      sessionId: sessionId,
      exerciseId: customId,
      order: 1,
    );
    await setEntry(phone, workoutExerciseId: squat, index: 0, kg: 100, reps: 5);
    await setEntry(phone, workoutExerciseId: squat, index: 1, kg: 110, reps: 3);
    await setEntry(phone, workoutExerciseId: custom, index: 0, kg: 60, reps: 8);
    return sessionId;
  }

  /// Every set in the database as `exercise | set | kg x reps`, in log order.
  Future<List<String>> sets(AppDatabase from) async {
    final rows = await from
        .customSelect(
          'SELECT ec.name AS name, ec.slug AS slug, ec.is_custom AS custom, '
          'se.set_index AS idx, se.weight_kg AS kg, se.reps AS reps '
          'FROM workout_exercises we '
          'JOIN exercise_catalog ec ON ec.id = we.exercise_id '
          'JOIN set_entries se ON se.workout_exercise_id = we.id '
          'ORDER BY we.order_index, se.set_index',
        )
        .get();
    return [
      for (final r in rows)
        '${r.data['name']} | ${r.data['idx']} | '
            '${r.data['kg']} x ${r.data['reps']}',
    ];
  }

  Future<int> count(AppDatabase from, String table) async {
    final row = await from
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return row.data['n'] as int;
  }

  Future<void> startBoth() async {
    await phoneSync.start(userId);
    await webSync.start(userId);
  }

  group('a workout logged on the phone', () {
    test('arrives on the web with its exercises and every set', () async {
      final (squatOnPhone, squatOnWeb) = await seedStockSquat();
      final zercher = await exercise(
        phone,
        name: 'Sandbag Shoulder Squat',
        custom: true,
      );
      await logSession(squatId: squatOnPhone, customId: zercher);

      await startBoth();
      await phoneSync.pushOnce();
      await webSync.pullAll();

      expect(await count(web, 'workout_sessions'), 1);
      expect(await sets(web), [
        'Squat | 0 | 100.0 x 5',
        'Squat | 1 | 110.0 x 3',
        'Sandbag Shoulder Squat | 0 | 60.0 x 8',
      ]);

      // The stock exercise resolved to the web's own row, not the phone's id.
      final stock = await web
          .customSelect(
            'SELECT we.exercise_id AS id FROM workout_exercises we '
            'WHERE we.order_index = 0',
          )
          .getSingle();
      expect(stock.data['id'], squatOnWeb);

      // The user-made exercise came along, still marked custom.
      final custom = await web
          .customSelect(
            'SELECT is_custom, slug FROM exercise_catalog '
            "WHERE name = 'Sandbag Shoulder Squat'",
          )
          .getSingle();
      expect(custom.data['is_custom'], 1);
      expect(custom.data['slug'], isNull);
    });

    test('an edit made on the web reaches the phone', () async {
      final (squatOnPhone, _) = await seedStockSquat();
      final zercher = await exercise(
        phone,
        name: 'Sandbag Shoulder Squat',
        custom: true,
      );
      await logSession(squatId: squatOnPhone, customId: zercher);
      await startBoth();
      await phoneSync.pushOnce();
      await webSync.pullAll();

      await web.customStatement(
        'UPDATE set_entries SET weight_kg = 120, reps = 2 '
        "WHERE weight_kg = 110 AND reps = 3",
      );
      await webSync.pushOnce();
      // The fake stamps updated_at on push; a pull only sees newer rows.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await phoneSync.pullAll();

      expect(await sets(phone), [
        'Squat | 0 | 100.0 x 5',
        'Squat | 1 | 120.0 x 2',
        'Sandbag Shoulder Squat | 0 | 60.0 x 8',
      ]);
    });

    test('deleting it on the phone removes it from the web, '
        'and keeps the exercises', () async {
      final (squatOnPhone, _) = await seedStockSquat();
      final zercher = await exercise(
        phone,
        name: 'Sandbag Shoulder Squat',
        custom: true,
      );
      final sessionId = await logSession(
        squatId: squatOnPhone,
        customId: zercher,
      );
      await startBoth();
      await phoneSync.pushOnce();
      await webSync.pullAll();
      expect(await count(web, 'workout_sessions'), 1);

      await phone.customStatement('DELETE FROM workout_sessions WHERE id = ?', [
        sessionId,
      ]);
      await phoneSync.pushOnce();
      await webSync.pullAll();

      expect(await count(web, 'workout_sessions'), 0);
      expect(await count(web, 'workout_exercises'), 0);
      expect(await count(web, 'set_entries'), 0);
      // The catalogue is not the session's to delete.
      expect(
        await count(
          web,
          "exercise_catalog WHERE name = 'Sandbag Shoulder Squat'",
        ),
        1,
      );
    });
  });

  group('a workout template made on the web', () {
    test('arrives on the phone with its exercises and sets', () async {
      final (squatOnPhone, squatOnWeb) = await seedStockSquat();
      final zercher = await exercise(
        web,
        name: 'Sandbag Shoulder Squat',
        custom: true,
      );

      final templateId = await web
          .into(web.workoutTemplates)
          .insert(WorkoutTemplatesCompanion.insert(name: 'Leg day'));
      final squatRow = await web
          .into(web.templateExercises)
          .insert(
            TemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: squatOnWeb,
              orderIndex: 0,
            ),
          );
      final zercherRow = await web
          .into(web.templateExercises)
          .insert(
            TemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: zercher,
              orderIndex: 1,
            ),
          );
      for (final (row, order, reps) in [
        (squatRow, 0, 5),
        (squatRow, 1, 5),
        (zercherRow, 0, 8),
      ]) {
        await web
            .into(web.templateSets)
            .insert(
              TemplateSetsCompanion.insert(
                templateExerciseId: row,
                setOrder: order,
                targetReps: Value(reps),
              ),
            );
      }

      await startBoth();
      await webSync.pushOnce();
      await phoneSync.pullAll();

      final rows = await phone
          .customSelect(
            'SELECT t.name AS template, ec.name AS exercise, '
            'ts.set_order AS ord, ts.target_reps AS reps, '
            'te.exercise_id AS exercise_id '
            'FROM workout_templates t '
            'JOIN template_exercises te ON te.template_id = t.id '
            'JOIN exercise_catalog ec ON ec.id = te.exercise_id '
            'JOIN template_sets ts ON ts.template_exercise_id = te.id '
            'ORDER BY te.order_index, ts.set_order',
          )
          .get();
      expect(
        [
          for (final r in rows)
            '${r.data['template']} | ${r.data['exercise']} | '
                '${r.data['ord']} | ${r.data['reps']}',
        ],
        [
          'Leg day | Squat | 0 | 5',
          'Leg day | Squat | 1 | 5',
          'Leg day | Sandbag Shoulder Squat | 0 | 8',
        ],
      );
      expect(rows.first.data['exercise_id'], squatOnPhone);
    });
  });
}
