import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_backend_service.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/features/gyms/data/gyms_repository.dart';

import 'fake_sync_backend_service.dart';

/// Covers the core Phase 10 sync behaviors end to end against a real Drift
/// database (in-memory) and a [FakeSyncBackendService] — mirrors the "fake
/// the network seam, run the real local layer" pattern from
/// `test/auth/auth_repository_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeSyncBackendService backend;
  late SyncService sync;
  late GymsRepository gyms;
  const userId = 'user-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeSyncBackendService();
    sync = SyncService(db: db, backend: backend);
  });

  tearDown(() async {
    await sync.dispose();
    backend.close();
    await db.close();
  });

  /// The uuid the sync layer knows a locally-created gym by.
  Future<String> gymUuid(int id) async {
    final row = await (db.select(db.gyms)..where((t) => t.id.equals(id)))
        .getSingle();
    return row.syncUuid!;
  }

  group('push', () {
    test('inserting a row via the repository enqueues and pushes it', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      final id = await gyms.createGym('Iron Temple');

      final pending = await db.select(db.pendingSyncOps).get();
      expect(pending, hasLength(1));
      expect(pending.single.entityType, 'gyms');
      expect(pending.single.operation, 'upsert');

      await sync.pushOnce();

      expect(backend.upsertCalls, hasLength(1));
      final (table, row) = backend.upsertCalls.single;
      expect(table, 'gyms');
      expect(row['name'], 'Iron Temple');
      expect(row['id'], isNotNull); // sync_uuid, not the local int id

      final remaining = await db.select(db.pendingSyncOps).get();
      expect(remaining, isEmpty);

      final gym = await (db.select(db.gyms)..where((t) => t.id.equals(id))).getSingle();
      expect(gym.syncedAt, isNotNull);
    });

    test('a failed push increments attempts and schedules a retry', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      await gyms.createGym('Iron Temple');
      backend.upsertFailuresRemaining = 1;

      await sync.pushOnce();

      final pending = await db.select(db.pendingSyncOps).get();
      expect(pending, hasLength(1));
      expect(pending.single.attempts, 1);
      expect(pending.single.lastError, isNotNull);
      expect(pending.single.nextRetryAt, isNotNull);
      expect(backend.upsertCalls, isEmpty);

      // Retrying immediately does nothing — nextRetryAt is in the future.
      await sync.pushOnce();
      expect(backend.upsertCalls, isEmpty);
    });

    test('the retry delay doubles and then flattens at the 300s ceiling',
        () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      await gyms.createGym('Iron Temple');
      backend.upsertFailuresRemaining = maxPushAttempts;

      // `min(300, 5 * (1 << min(attempts, 6)))`. Note it flattens at attempt
      // *6* — 5 * 2^6 is 320, already over the cap — not at 7. The doc
      // comment on the constant says `5 * 2^attempts`, which diverges here;
      // this pins the behaviour the code actually ships.
      const expectedDelays = [10, 20, 40, 80, 160, 300, 300, 300];

      for (var attempt = 1; attempt <= maxPushAttempts; attempt++) {
        final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await sync.pushOnce();

        final op = (await db.select(db.pendingSyncOps).get()).single;
        expect(op.attempts, attempt, reason: 'attempt $attempt was not counted');
        final delay =
            (op.nextRetryAt!.millisecondsSinceEpoch ~/ 1000) - before;
        expect(
          delay,
          inInclusiveRange(
            expectedDelays[attempt - 1] - 1,
            expectedDelays[attempt - 1] + 1,
          ),
          reason: 'attempt $attempt scheduled the wrong retry delay',
        );

        // Open the gate so the next pushOnce actually picks the op up,
        // instead of measuring the backoff we just asserted.
        await db.customUpdate(
          'UPDATE pending_sync_ops SET next_retry_at = ?',
          variables: [Variable(before - 1)],
        );
      }

      expect(backend.upsertCalls, isEmpty);
    });

    test('next_retry_at gates the op: skipped while future, picked up once past',
        () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      await gyms.createGym('Iron Temple');

      // A never-attempted op has a null next_retry_at and goes immediately —
      // the `next_retry_at IS NULL` arm of the filter.
      expect((await db.select(db.pendingSyncOps).get()).single.nextRetryAt, isNull);

      backend.upsertFailuresRemaining = 1;
      await sync.pushOnce();
      expect(backend.upsertCalls, isEmpty);
      expect((await db.select(db.pendingSyncOps).get()).single.nextRetryAt,
          isNotNull);

      // Still gated.
      await sync.pushOnce();
      expect(backend.upsertCalls, isEmpty);

      await db.customUpdate(
        'UPDATE pending_sync_ops SET next_retry_at = ?',
        variables: [
          Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1),
        ],
      );
      await sync.pushOnce();
      expect(backend.upsertCalls, hasLength(1));
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
    });

    test('a soft delete pushes as an upsert of a tombstoned row', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      final id = await gyms.createGym('Iron Temple');
      await sync.pushOnce();
      backend.upsertCalls.clear();

      // Gyms has no soft-delete API of its own; simulate the shape a synced
      // table's tombstone write takes.
      await db.customUpdate(
        'UPDATE gyms SET deleted_at = ? WHERE id = ?',
        variables: [Variable(1750000000), Variable(id)],
      );
      await sync.pushOnce();

      expect(backend.upsertCalls, hasLength(1));
      final (_, row) = backend.upsertCalls.single;
      expect(row['deleted_at'], isNotNull);
      expect(backend.deleteCalls, isEmpty);
    });

    test('a hard DELETE still reaches the backend via the fallback trigger', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      final id = await gyms.createGym('Iron Temple');
      await sync.pushOnce();
      backend.upsertCalls.clear();

      final gym = await (db.select(db.gyms)..where((t) => t.id.equals(id))).getSingle();
      await (db.delete(db.gyms)..where((t) => t.id.equals(id))).go();

      await sync.pushOnce();

      expect(backend.deleteCalls, hasLength(1));
      expect(backend.deleteCalls.single.$2, gym.syncUuid);
    });
  });

  group('pull', () {
    test('a remote row lands locally, keyed by sync_uuid', () async {
      backend.seedRemoteRow('gyms', {
        'id': 'remote-uuid-1',
        'user_id': userId,
        'name': 'Remote Gym',
        'is_default': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': null,
      });

      await sync.start(userId);

      final local = await db.select(db.gyms).get();
      expect(local, hasLength(1));
      expect(local.single.name, 'Remote Gym');
      expect(local.single.syncUuid, 'remote-uuid-1');
    });

    test(
      'a local edit still pending in the outbox is not clobbered by a pull',
      () async {
        gyms = GymsRepository(db);
        final id = await gyms.createGym('Local Name');
        final row = await (db.select(db.gyms)..where((t) => t.id.equals(id))).getSingle();

        // Remote has a newer-looking row for the same sync_uuid — but the
        // local edit hasn't been pushed yet, so local must win.
        backend.seedRemoteRow('gyms', {
          'id': row.syncUuid,
          'user_id': userId,
          'name': 'Remote Overwrite',
          'is_default': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
          'deleted_at': null,
        });

        await sync.start(userId);

        final after = await (db.select(db.gyms)..where((t) => t.id.equals(id))).getSingle();
        expect(after.name, 'Local Name');
      },
    );
  });

  group('tombstones', () {
    /// Gets a pushed gym into the state a remote hard delete acts on.
    Future<String> pushedGym([String name = 'Iron Temple']) async {
      gyms = GymsRepository(db);
      final id = await gyms.createGym(name);
      await sync.pushOnce();
      return gymUuid(id);
    }

    test('a remote hard delete removes the local row on the next pull', () async {
      await sync.start(userId);
      final uuid = await pushedGym();

      // Another device deleted it; the server trigger left a tombstone.
      await backend.delete('gyms', uuid);
      await sync.pullAll();

      expect(await db.select(db.gyms).get(), isEmpty);
    });

    test('applying a tombstone does not enqueue an outbox delete', () async {
      await sync.start(userId);
      final uuid = await pushedGym();
      await backend.delete('gyms', uuid);
      backend.deleteCalls.clear();

      await sync.pullAll();

      // The local trg_outbox_del_* fired, but the echo is purged: pushing it
      // would hard-delete the row again remotely, which destroys a copy
      // another device may have legitimately resurrected in the meantime.
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
      await sync.pushOnce();
      expect(backend.deleteCalls, isEmpty);
    });

    test('a row re-created after its tombstone survives the pull', () async {
      await sync.start(userId);

      // Tombstone first, then a newer remote row under the same uuid — the
      // shape produced when another device had a pending edit and resurrected
      // the row. Row pulls must be applied after tombstones, so "exists" wins.
      backend.seedTombstone('gyms', 'resurrected-uuid');
      backend.seedRemoteRow('gyms', {
        'id': 'resurrected-uuid',
        'user_id': userId,
        'name': 'Back From The Dead',
        'is_default': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'deleted_at': null,
      });

      await sync.pullAll();

      final local = await db.select(db.gyms).get();
      expect(local, hasLength(1));
      expect(local.single.name, 'Back From The Dead');
    });

    test(
      'a row does not leave an outbox echo behind after its first pull',
      () async {
        await sync.start(userId);
        backend.seedRemoteRow('gyms', {
          'id': 'fresh-pull-uuid',
          'user_id': userId,
          'name': 'Freshly Arrived',
          'is_default': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'deleted_at': null,
        });
        await sync.pullAll();
        expect(await db.select(db.gyms).get(), hasLength(1));

        // Applying a pulled row is a plain SQLite INSERT like any other,
        // so it fires `trg_outbox_ins_gyms` the same as a local write would.
        // Nothing has pushed since, so a phantom `pending_sync_ops` row would
        // still be here if `_applyPulledRow` didn't clean up after itself.
        expect(await db.select(db.pendingSyncOps).get(), isEmpty);
      },
    );

    test(
      'a row just pulled for the first time can still be deleted by a '
      "same-cycle tombstone",
      () async {
        // Regression: found while proving the round trip against the live
        // backend. Without the purge above, the outbox echo left behind by
        // this row's first pull made `_applyTombstoneBatch`'s local-wins
        // check treat it as a genuine unpushed edit, so a delete from
        // another device landing in the same pull cycle — or any time before
        // the next 20s push timer happened to clear the echo — was silently
        // ignored.
        await sync.start(userId);
        const uuid = 'fresh-pull-uuid-2';
        backend.seedRemoteRow('gyms', {
          'id': uuid,
          'user_id': userId,
          'name': 'Freshly Arrived',
          'is_default': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'deleted_at': null,
        });
        await sync.pullAll();
        expect(await db.select(db.gyms).get(), hasLength(1));

        // `backend.delete`, not `seedTombstone` directly — this also removes
        // the row from the fake's remote store, matching a real hard delete.
        // Leaving it in place would make the *next* pull re-fetch the row at
        // its own cursor timestamp (the fake's `pull` filter is inclusive at
        // the boundary; Postgres's `gt()` is not), which is a fake-backend
        // artifact unrelated to the echo bug this test is about.
        await backend.delete('gyms', uuid);
        await sync.pullAll();

        expect(await db.select(db.gyms).get(), isEmpty);
      },
    );

    test('a tombstone is skipped while a local edit is pending', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      final id = await gyms.createGym('Unpushed');
      final uuid = await gymUuid(id);

      backend.seedTombstone('gyms', uuid);
      await sync.pullAll();

      // Local wins while unpushed; the pending upsert then resurrects it.
      expect(await db.select(db.gyms).get(), hasLength(1));
      await sync.pushOnce();
      expect(backend.upsertCalls.map((c) => c.$2['id']), contains(uuid));
    });

    test('an applied tombstone is not applied a second time', () async {
      await sync.start(userId);
      final uuid = await pushedGym();
      await backend.delete('gyms', uuid);
      await sync.pullAll();
      expect(await db.select(db.gyms).get(), isEmpty);

      // Same uuid comes back — from a resurrection push on another device.
      backend.seedRemoteRow('gyms', {
        'id': uuid,
        'user_id': userId,
        'name': 'Second Life',
        'is_default': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'deleted_at': null,
      });
      await sync.pullAll();

      expect(await db.select(db.gyms).get(), hasLength(1));
    });

    test('a tombstone for an unknown entity_type is ignored', () async {
      await sync.start(userId);
      await pushedGym();

      backend.seedTombstone("gyms'; DROP TABLE gyms; --", 'whatever-uuid');
      await sync.pullAll();

      expect(await db.select(db.gyms).get(), hasLength(1));
    });

    test('the first pull initializes the cursor without applying', () async {
      gyms = GymsRepository(db);
      await gyms.createGym('Pre-existing');
      final id = await gyms.createGym('Second');
      backend.seedTombstone(
        'gyms',
        await gymUuid(id),
        deletedAt: DateTime.now().subtract(const Duration(days: 30)),
      );

      await sync.start(userId);

      // Nothing on this device can be meaningfully described by a tombstone
      // written before it ever synced, so the window is skipped entirely.
      expect(await db.select(db.gyms).get(), hasLength(2));
      final cursor = await (db.select(
        db.syncCursors,
      )..where((t) => t.entityType.equals('__tombstones__'))).getSingle();
      expect(
        DateTime.parse(cursor.cursorIso).isAfter(
          DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });

    test('a parent tombstone cascades locally without outbox churn', () async {
      await sync.start(userId);

      final exercise = await db.select(db.exerciseCatalog).get().then((r) => r.first);
      final sessionId = await db.into(db.workoutSessions).insert(
            WorkoutSessionsCompanion.insert(startedAt: DateTime.now()),
          );
      await db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exercise.id,
              orderIndex: 0,
            ),
          );
      await sync.pushOnce();
      backend.deleteCalls.clear();

      final session = await (db.select(db.workoutSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingle();
      final child = (await db.select(db.workoutExercises).get()).single;
      // Postgres cascades the delete and fires the tombstone trigger for each
      // row, so both rows are gone remotely and both leave a tombstone.
      await backend.delete('workout_exercises', child.syncUuid!);
      await backend.delete('workout_sessions', session.syncUuid!);
      backend.deleteCalls.clear();

      await sync.pullAll();

      // The local FK cascade removed the child, and the delete ops both rows'
      // triggers enqueued were purged as echoes of our own apply.
      expect(await db.select(db.workoutSessions).get(), isEmpty);
      expect(await db.select(db.workoutExercises).get(), isEmpty);
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
      await sync.pushOnce();
      expect(backend.deleteCalls, isEmpty);
    });

    test('a cursor older than retention triggers a full reconcile', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      final keptId = await gyms.createGym('Still Remote');
      final goneId = await gyms.createGym('Deleted Elsewhere');
      await sync.pushOnce();

      // A never-pushed row must survive: its absence remotely means "not
      // uploaded yet", not "deleted elsewhere".
      final unsyncedId = await gyms.createGym('Never Uploaded');

      // Drop one row from the remote set without leaving a tombstone, the way
      // a delete older than the GC window looks, and age the cursor past it.
      final goneUuid = await gymUuid(goneId);
      backend.remoteRows['gyms']!.removeWhere((r) => r['id'] == goneUuid);
      await db.customUpdate(
        'UPDATE sync_cursors SET cursor_iso = ? WHERE entity_type = ?',
        variables: [
          Variable(
            DateTime.now().toUtc().subtract(const Duration(days: 120)).toIso8601String(),
          ),
          Variable('__tombstones__'),
        ],
      );

      await sync.pullAll();

      final remaining = (await db.select(db.gyms).get()).map((g) => g.id).toSet();
      expect(remaining, contains(keptId));
      expect(remaining, contains(unsyncedId));
      expect(remaining, isNot(contains(goneId)));
    });
  });

  group('quarantine', () {
    test('an op past the attempt cap stops retrying and stops blocking pulls', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      final id = await gyms.createGym('Poison');
      final uuid = await gymUuid(id);

      // Fail every attempt, clearing the backoff each round so the cap is what
      // ends it rather than the retry clock.
      for (var i = 0; i < maxPushAttempts; i++) {
        backend.upsertFailuresRemaining = 1;
        await db.customUpdate('UPDATE pending_sync_ops SET next_retry_at = NULL');
        await sync.pushOnce();
      }

      final op = (await db.select(db.pendingSyncOps).get()).single;
      expect(op.attempts, maxPushAttempts);

      // Quarantined: no longer attempted at all.
      backend.upsertCalls.clear();
      await db.customUpdate('UPDATE pending_sync_ops SET next_retry_at = NULL');
      await sync.pushOnce();
      expect(backend.upsertCalls, isEmpty);
      expect(sync.state.phase, SyncPhase.error);

      // ...and no longer freezes the row's inbound sync, which would otherwise
      // leave it stuck in both directions forever.
      backend.seedRemoteRow('gyms', {
        'id': uuid,
        'user_id': userId,
        'name': 'Server Wins',
        'is_default': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'deleted_at': null,
      });
      await sync.pullAll();

      final row = await (db.select(db.gyms)..where((t) => t.id.equals(id))).getSingle();
      expect(row.name, 'Server Wins');
    });
  });

  group('state', () {
    test('reports disabled when no backend is configured', () async {
      final noopSync = SyncService(
        db: db,
        backend: const NoopSyncBackendService(),
      );
      addTearDown(noopSync.dispose);

      await noopSync.start(userId);

      expect(noopSync.state.phase, SyncPhase.disabled);
    });

    test('a clean cycle ends in synced, having passed through syncing', () async {
      final phases = <SyncPhase>[];
      final sub = sync.stateStream.listen((s) => phases.add(s.phase));

      await sync.start(userId);
      await Future<void>.delayed(Duration.zero); // let the stream drain
      await sub.cancel();

      expect(phases.first, SyncPhase.disabled);
      expect(phases, contains(SyncPhase.syncing));
      expect(phases.last, SyncPhase.synced);
      expect(sync.state.lastSyncedAt, isNotNull);
    });

    test('a pull failure surfaces as error rather than being swallowed', () async {
      await sync.start(userId);
      expect(sync.state.phase, SyncPhase.synced);

      backend.failPulls = true;
      await sync.pullAll();

      expect(sync.state.phase, SyncPhase.error);
      expect(sync.state.lastError, isNotNull);
    });

    test('unpushed local work reads as pending, never synced', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      backend.upsertFailuresRemaining = 1;
      await gyms.createGym('Not Yet Uploaded');

      await sync.pushOnce();

      expect(sync.state.phase, SyncPhase.pending);
      expect(sync.state.pendingCount, 1);
    });
  });

  group('account switch', () {
    test("a second account does not inherit the first's outbox", () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      backend.upsertFailuresRemaining = 1;
      await gyms.createGym("First User's Gym");
      await sync.pushOnce();
      expect(await db.select(db.pendingSyncOps).get(), hasLength(1));

      await sync.stop();
      backend.upsertCalls.clear();
      await sync.start('user-2');

      // The outbox and every cursor were cleared on the uid change, so nothing
      // of user-1's is uploaded under user-2's id.
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
      expect(backend.upsertCalls, isEmpty);
    });

    test('the same account keeps its outbox across a restart', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      backend.upsertFailuresRemaining = 1;
      await gyms.createGym('Survives');
      await sync.pushOnce();

      await sync.stop();
      await sync.start(userId);

      // Same uid, so nothing is cleared — the op is merely waiting out its
      // backoff, and pushes as soon as that expires.
      expect(await db.select(db.pendingSyncOps).get(), hasLength(1));
      await db.customUpdate('UPDATE pending_sync_ops SET next_retry_at = NULL');
      await sync.pushOnce();
      expect(backend.upsertCalls.map((c) => c.$2['name']), contains('Survives'));
    });
  });

  group('push regressions', () {
    test('stamping synced_at does not re-enqueue the row it just pushed', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      await gyms.createGym('Iron Temple');

      await sync.pushOnce();

      // The `UPDATE ... SET synced_at` after a successful upsert fires
      // trg_outbox_upd_*; if that landed as a new outbox row the layer would
      // push forever in a loop.
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
      await sync.pushOnce();
      expect(backend.upsertCalls, hasLength(1));
    });
  });

  group('re-upload', () {
    test('re-pushes rows already marked synced', () async {
      await sync.start(userId);
      gyms = GymsRepository(db);
      final id = await gyms.createGym('Iron Temple');
      await sync.pushOnce();

      // Steady state: the row is up, the outbox is empty, and nothing in the
      // normal path would ever send it again.
      expect(backend.upsertCalls, hasLength(1));
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
      final before = await (db.select(db.gyms)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(before.syncedAt, isNotNull);

      // This is the repoint-to-a-new-backend case: the row's synced_at refers
      // to a project that no longer holds it.
      final enqueued = await sync.reuploadAllLocalData();

      expect(enqueued, greaterThanOrEqualTo(1));
      expect(backend.upsertCalls, hasLength(2));
      expect(backend.upsertCalls.last.$1, 'gyms');
      expect(backend.upsertCalls.last.$2['name'], 'Iron Temple');
      // Drained, not left behind to re-push on every later cycle.
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
    });

    test('skips seeded catalogue rows', () async {
      await sync.start(userId);
      // Seeded catalogue rows never leave the device: their natural key is
      // what identifies them, and pushing one sends both catalogue columns
      // null, which Postgres rejects (0007_catalogue_is_custom.sql).
      await db.customStatement(
        'INSERT INTO exercise_catalog '
        '(name, primary_muscle, equipment, mechanics, force, plane, '
        'is_custom, sync_uuid) '
        "VALUES ('Back Squat', 'Quads', 'Barbell', 'compound', 'push', "
        "'axial', 0, 'seeded-uuid')",
      );

      await sync.reuploadAllLocalData();

      expect(
        backend.upsertCalls.where((c) => c.$1 == 'exercise_catalog'),
        isEmpty,
      );
    });
  });
}
