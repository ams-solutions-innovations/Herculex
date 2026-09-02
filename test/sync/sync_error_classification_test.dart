import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_backend_service.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/features/gyms/data/gyms_repository.dart';

import 'fake_sync_backend_service.dart';

/// Covers the push-failure branches added when `SupabaseSyncBackendService`
/// started classifying its errors. Before that, every failure was one
/// `catch (e)` with one backoff, so an expired JWT and a missing Postgres
/// column both burned eight attempts and then went quiet — the first is
/// fixed by a token refresh, the second by applying a migration, and neither
/// is fixed by retrying.
///
/// Same harness as `sync_service_test.dart`: a real in-memory Drift database
/// with only the network seam faked.
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

  Future<void> enqueueOneGym() async {
    await sync.start(userId);
    gyms = GymsRepository(db);
    await gyms.createGym('Iron Temple');
  }

  group('error classification', () {
    test('an auth failure does not consume a push attempt', () async {
      await enqueueOneGym();
      backend
        ..upsertFailureKind = SyncErrorKind.auth
        ..upsertFailuresRemaining = 1;

      await sync.pushOnce();

      final op = (await db.select(db.pendingSyncOps).get()).single;
      // The whole point: attempts stays at 0, so a token that expires while
      // the outbox is deep cannot quarantine every row in it.
      expect(op.attempts, 0);
      expect(op.lastError, contains('auth'));
      expect(op.nextRetryAt, isNotNull);
    });

    test('a schema failure quarantines immediately', () async {
      await enqueueOneGym();
      backend
        ..upsertFailureKind = SyncErrorKind.schema
        ..upsertFailuresRemaining = 1;

      await sync.pushOnce();

      final op = (await db.select(db.pendingSyncOps).get()).single;
      // PGRST204 means a migration has not been applied. Eight quiet retries
      // is exactly how the v33/v34/v37 regressions stayed invisible.
      expect(op.attempts, maxPushAttempts);
      expect(op.lastError, contains('schema'));
    });

    test('a foreign-key failure keeps the ordinary backoff', () async {
      await enqueueOneGym();
      backend
        ..upsertFailureKind = SyncErrorKind.foreignKey
        ..upsertFailuresRemaining = 1;

      await sync.pushOnce();

      final op = (await db.select(db.pendingSyncOps).get()).single;
      // A missing parent self-heals on the next cycle, so this is the one
      // kind where retry-with-backoff was always the right answer.
      expect(op.attempts, 1);
    });

    test('a duplicate key is acknowledged, not retried', () async {
      await enqueueOneGym();
      backend
        ..upsertFailureKind = SyncErrorKind.conflict
        ..upsertFailuresRemaining = 1;

      await sync.pushOnce();

      // Under last-write-wins the row already being there is success.
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
    });

    test('an unclassified failure still gets the old behaviour', () async {
      await enqueueOneGym();
      backend.upsertFailuresRemaining = 1; // no kind — bare Exception

      await sync.pushOnce();

      final op = (await db.select(db.pendingSyncOps).get()).single;
      expect(op.attempts, 1);
      expect(op.nextRetryAt, isNotNull);
    });
  });

  group('retryQuarantined', () {
    test('releases quarantined ops and pushes them', () async {
      await enqueueOneGym();
      backend
        ..upsertFailureKind = SyncErrorKind.schema
        ..upsertFailuresRemaining = 1;
      await sync.pushOnce();
      expect(
        (await db.select(db.pendingSyncOps).get()).single.attempts,
        maxPushAttempts,
      );

      // Stands in for "the migration has now been applied".
      backend.upsertFailureKind = null;
      final released = await sync.retryQuarantined();
      expect(released, 1);

      await sync.pushOnce();
      expect(backend.upsertCalls, hasLength(1));
      expect(await db.select(db.pendingSyncOps).get(), isEmpty);
    });

    test('is a no-op when nothing is quarantined', () async {
      await enqueueOneGym();
      expect(await sync.retryQuarantined(), 0);
    });
  });
}
