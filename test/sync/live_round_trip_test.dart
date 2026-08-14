@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/env.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/supabase_sync_backend_service.dart';
import 'package:herculex/data/sync/sync_backend_service.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/data/sync/sync_table_specs.dart';
import 'package:herculex/features/gyms/data/gyms_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../support/test_database.dart';

/// The real round trip RB-02 is actually about.
///
/// `sync_service_test.dart` and `sync_payload_test.dart` run the whole local
/// layer against `FakeSyncBackendService`, which is the right shape for
/// logic — but the fake *reimplements* the semantics it is supposed to be
/// checking (the server `updated_at` clock, the tombstone triggers, the
/// inclusive/exclusive `deleted_at` boundary) and has no RLS policies at all,
/// because RLS is enforced server-side and cannot be faked. Until this file
/// ran, no byte had ever moved through the live project.
///
/// Two devices are two [SyncService]s over two in-memory Drift databases,
/// each with its own [SupabaseClient] signed in as the same account. A bare
/// `SupabaseClient` is pure Dart — http, a websocket, an isolate — so this
/// needs no Flutter plugin channels and runs under plain `flutter test`.
/// Only `supabase_flutter`'s `Supabase.initialize()` needs plugins, and it is
/// never called here.
///
/// Run it with:
///
/// ```
/// flutter test test/sync/live_round_trip_test.dart --dart-define-from-file=.secrets/live_sync.json
/// ```
///
/// See `docs/rb02-sync-verification.md` for the file's contents and for the
/// handful of steps that still need a real device.
const _email = String.fromEnvironment('SUPABASE_TEST_EMAIL');
const _password = String.fromEnvironment('SUPABASE_TEST_PASSWORD');
const _email2 = String.fromEnvironment('SUPABASE_TEST_EMAIL_2');
const _password2 = String.fromEnvironment('SUPABASE_TEST_PASSWORD_2');
const _testRealtime = bool.fromEnvironment('SUPABASE_TEST_REALTIME');

/// Delegates to the real backend but never emits a realtime hint.
///
/// `SyncService.start()` subscribes 37 channels and routes every hint into
/// `pullAll()`. With two live devices that is 74 subscriptions firing
/// unsolicited pulls in between assertion steps, advancing `sync_cursors`
/// under the test's feet. Realtime is worth proving, but on its own terms —
/// see the last test in this file.
class _NoRealtimeBackend implements SyncBackendService {
  _NoRealtimeBackend(this._inner);

  final SyncBackendService _inner;

  @override
  Stream<String> realtimeHints(List<String> tables, {required String userId}) =>
      const Stream.empty();

  @override
  bool get isConfigured => _inner.isConfigured;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) =>
      _inner.upsert(table, row);

  @override
  Future<void> delete(String table, String id) => _inner.delete(table, id);

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    required String userId,
    required DateTime since,
  }) => _inner.pull(table, userId: userId, since: since);

  @override
  Future<List<Map<String, dynamic>>> pullTombstones({
    required String userId,
    required DateTime since,
    bool inclusive = false,
    int limit = tombstonePageSize,
  }) => _inner.pullTombstones(
    userId: userId,
    since: since,
    inclusive: inclusive,
    limit: limit,
  );

  @override
  Future<Set<String>> pullExistingIds(String table, {required String userId}) =>
      _inner.pullExistingIds(table, userId: userId);

  @override
  void dispose() => _inner.dispose();
}

class _Device {
  _Device(this.label);

  final String label;
  late final SupabaseClient client;
  late final AppDatabase db;
  late final SyncService sync;
  late final String uid;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each device gets its own in-memory executor; drift's warning is about
  // two instances sharing one, which is not what happens here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // `flutter_test` installs an `HttpOverrides` that fails every real request
  // with a fake 400 by default, to keep widget tests from accidentally
  // hitting the network. This file's entire point is a real request, and the
  // override is only installed once at binding init (not reset per test), so
  // clearing it here is enough for the whole file.
  HttpOverrides.global = null;

  final skipReason = (!Env.hasSupabase || _email.isEmpty || _password.isEmpty)
      ? 'Live Supabase round trip. Provide SUPABASE_URL, SUPABASE_ANON_KEY, '
            'SUPABASE_TEST_EMAIL and SUPABASE_TEST_PASSWORD via '
            '--dart-define-from-file to run it.'
      : null;

  group('live cloud round trip', () {
    late _Device a;
    late _Device b;
    _Device? outsider;

    Future<_Device> signIn(
      String label,
      String email,
      String password, {
      bool withDatabase = true,
    }) async {
      final device = _Device(label);
      device.client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabaseAnonKey,
        // No background refresh ticker to outlive the test.
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final response = await device.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Sign-in returned no user for $label ($email)');
      }
      device.uid = user.id;
      if (withDatabase) {
        device.db = await openTestDatabase();
        device.sync = SyncService(
          db: device.db,
          backend: _NoRealtimeBackend(
            SupabaseSyncBackendService(device.client),
          ),
        );
      }
      return device;
    }

    /// Removes everything this account owns. Children first — several FKs are
    /// `on delete restrict`. Identity-independent on purpose: it needs no
    /// bookkeeping and so still works after a test died halfway through.
    Future<void> wipeRemote(SupabaseClient client, String uid) async {
      for (final table in syncTableOrder.reversed) {
        try {
          await client.from(table).delete().eq('user_id', uid);
        } catch (e) {
          printOnFailure('cleanup of $table failed: $e');
        }
      }
    }

    setUpAll(() async {
      a = await signIn('A', _email, _password);
      b = await signIn('B', _email, _password);
      if (_email2.isNotEmpty && _password2.isNotEmpty) {
        outsider = await signIn(
          'outsider',
          _email2,
          _password2,
          withDatabase: false,
        );
      }
      // Residue from a previous crashed run would poison the first pull.
      await wipeRemote(a.client, a.uid);
    });

    tearDownAll(() async {
      await wipeRemote(a.client, a.uid);
      for (final device in [a, b]) {
        await device.sync.dispose();
        await device.db.close();
        await device.client.dispose();
      }
      await outsider?.client.dispose();
      // `sync_tombstones` is deliberately not cleaned: 0005 revokes client
      // writes on it, and the 90-day `sync_tombstones_gc` job owns it. Left
      // behind it is inert — every run starts from fresh in-memory databases
      // whose tombstone cursor seeds to "now".
    });

    Future<String> syncUuid(AppDatabase db, String table, int id) async {
      final row = await db
          .customSelect(
            'SELECT sync_uuid FROM $table WHERE id = ?',
            variables: [Variable(id)],
          )
          .getSingle();
      return row.data['sync_uuid'] as String;
    }

    test('a row pushes, lands on the other device, and its delete follows',
        () async {
      await a.sync.start(a.uid);
      final name = 'Live RT ${DateTime.now().microsecondsSinceEpoch}';
      final gymId = await GymsRepository(a.db).createGym(name);
      final uuid = await syncUuid(a.db, 'gyms', gymId);

      await a.sync.pushOnce();

      // ── It reached Postgres, owned by the signed-in uid ────────────────
      // Read raw rather than via `backend.pull`, which filters on
      // `updated_at` — the very column under test.
      final remote =
          (await a.client.from('gyms').select().eq('id', uuid) as List).single
              as Map<String, dynamic>;
      expect(remote['user_id'], a.uid);
      expect(remote['name'], name);
      final firstStamp = DateTime.parse(remote['updated_at'] as String);

      // ── The server owns the clock ──────────────────────────────────────
      // Rename the row while forcing a nonsense local `updated_at`
      // (2001-01-01). If the client's value were passed through, the row
      // would go *backwards* in time and every delta pull would miss it.
      await a.db.customUpdate(
        'UPDATE gyms SET name = ?, updated_at = ? WHERE id = ?',
        variables: [Variable('$name renamed'), Variable(978307200), Variable(gymId)],
      );
      await a.sync.pushOnce();

      final restamped =
          (await a.client.from('gyms').select('name, updated_at').eq('id', uuid)
                  as List)
              .single as Map<String, dynamic>;
      final secondStamp = DateTime.parse(restamped['updated_at'] as String);
      expect(restamped['name'], '$name renamed');
      expect(
        secondStamp.isAfter(firstStamp),
        isTrue,
        reason: 't_set_updated_at_gyms must re-stamp, not accept the client value',
      );
      expect(secondStamp.year, greaterThan(2001));

      // ── It arrives on device B ─────────────────────────────────────────
      await b.sync.start(b.uid);
      final onB = await (b.db.select(
        b.db.gyms,
      )..where((t) => t.syncUuid.equals(uuid))).getSingle();
      expect(onB.name, '$name renamed');

      // Rewind B's tombstone cursor to a *server*-derived instant. It seeds
      // to the local clock on first pull but filters against server-authored
      // `deleted_at`, so even a second of positive client skew would swallow
      // the delete below and fail this test for the wrong reason.
      await b.db.customUpdate(
        'UPDATE sync_cursors SET cursor_iso = ? WHERE entity_type = ?',
        variables: [
          Variable(
            secondStamp
                .subtract(const Duration(seconds: 1))
                .toUtc()
                .toIso8601String(),
          ),
          // Must match `_tombstoneKey` in sync_service.dart.
          Variable('__tombstones__'),
        ],
      );

      // ── A hard delete propagates ───────────────────────────────────────
      // The case that was impossible before 0005: the row simply stopped
      // appearing in delta pulls, so B kept it forever.
      await (a.db.delete(a.db.gyms)..where((t) => t.id.equals(gymId))).go();
      await a.sync.pushOnce();
      expect(await a.client.from('gyms').select('id').eq('id', uuid), isEmpty);

      await b.sync.pullAll();
      expect(
        await (b.db.select(
          b.db.gyms,
        )..where((t) => t.syncUuid.equals(uuid))).getSingleOrNull(),
        isNull,
      );

      // ── …without ping-ponging ──────────────────────────────────────────
      // Applying the tombstone fired B's own `trg_outbox_del_gyms`.
      // `_purgeEchoedDeletes` must have swallowed it, or B would delete the
      // row again on its next push and resurrect the loop.
      final echoes = await b.db
          .customSelect(
            "SELECT id FROM pending_sync_ops WHERE operation = 'delete'",
          )
          .get();
      expect(echoes, isEmpty);
      expect(await b.db.select(b.db.pendingSyncOps).get(), isEmpty);
      expect(b.sync.state.phase, isNot(SyncPhase.error));
    });

    test('a custom exercise and the child referencing it survive the trip',
        () async {
      // The `CatalogueFk` path, and the regression for the defect found while
      // closing RB-02 (`0007_catalogue_is_custom.sql`): `is_custom` used to be
      // local-only, so a custom parent arrived on B as a seeded row and every
      // child B then created pushed a payload the Postgres `check` rejected.
      await a.sync.start(a.uid);
      await b.sync.start(b.uid);

      final exerciseId = await a.db
          .into(a.db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Live RT Zercher ${DateTime.now().microsecondsSinceEpoch}',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
              isCustom: const Value(true),
            ),
          );
      final exerciseUuid = await syncUuid(a.db, 'exercise_catalog', exerciseId);
      await a.db
          .into(a.db.microWorkouts)
          .insert(
            MicroWorkoutsCompanion.insert(
              name: 'Live RT micro',
              exerciseId: exerciseId,
              targetReps: 30,
            ),
          );
      await a.sync.pushOnce();
      expect(
        a.sync.state.phase,
        isNot(SyncPhase.error),
        reason: 'the parent must go up before the child, or the FK rejects it',
      );

      final remoteMicro =
          (await a.client
                      .from('micro_workouts')
                      .select('exercise_catalog_id, exercise_slug, target_reps, created_at')
                      .eq('exercise_catalog_id', exerciseUuid)
                  as List)
              .single as Map<String, dynamic>;
      // Exactly one arm of the `check` constraint, and the epoch→ISO
      // conversion for `dateTimeColumns`.
      expect(remoteMicro['exercise_slug'], isNull);
      expect(remoteMicro['target_reps'], 30);
      expect(remoteMicro['created_at'], isA<String>());

      await b.sync.pullAll();
      final onB = await b.db
          .customSelect(
            'SELECT id, is_custom FROM exercise_catalog WHERE sync_uuid = ?',
            variables: [Variable(exerciseUuid)],
          )
          .getSingle();
      expect(
        onB.data['is_custom'],
        1,
        reason: 'a user-created exercise must not arrive as a stock one',
      );

      final microOnB = await b.db
          .customSelect(
            "SELECT exercise_id FROM micro_workouts WHERE name = 'Live RT micro'",
          )
          .getSingle();
      // The resolved FK, not raw id equality, is the actual invariant: two
      // fresh devices seed the same bundled catalogue, so their first custom
      // insert can legitimately land on the same autoincrement id — that
      // would only diverge from A's id if the two databases' catalogue
      // tables had already drifted apart before this test ran.
      expect(microOnB.data['exercise_id'], onB.data['id']);
    });

    test('another account cannot see or forge this account\'s rows', () async {
      final other = outsider;
      final name = 'Live RT rls ${DateTime.now().microsecondsSinceEpoch}';
      await a.sync.start(a.uid);
      final gymId = await GymsRepository(a.db).createGym(name);
      final uuid = await syncUuid(a.db, 'gyms', gymId);
      await a.sync.pushOnce();
      expect(await a.client.from('gyms').select('id').eq('id', uuid), isNotEmpty);

      // RLS returns an empty set rather than a 403 — the row is invisible,
      // not merely forbidden.
      expect(await other!.client.from('gyms').select().eq('id', uuid), isEmpty);
      expect(await other.client.from('gyms').select(), isEmpty);
      expect(
        await other.client.from('sync_tombstones').select().eq('user_id', a.uid),
        isEmpty,
      );

      // `with check (user_id = auth.uid())` rejects a forged owner.
      await expectLater(
        other.client.from('gyms').upsert({
          'id': const Uuid().v4(),
          'user_id': a.uid,
          'name': 'forged',
        }),
        throwsA(isA<PostgrestException>()),
      );
    }, skip: outsiderSkip());

    test('realtime delivers a hint for a remote write', () async {
      // Opt-in: the only genuinely timing-dependent assertion here, kept
      // apart so its flakiness cannot take the rest of the file down. Before
      // 0005 added the tables to `supabase_realtime`, every subscription the
      // client opened was silently dead, so this is worth having at all.
      final backend = SupabaseSyncBackendService(b.client);
      addTearDown(backend.dispose);

      final hint = backend
          .realtimeHints(['gyms'], userId: b.uid)
          .first
          .timeout(const Duration(seconds: 30));
      // A fresh client's first websocket handshake plus Realtime's own RLS
      // authorization round trip can take a few seconds — this is the
      // channel actually reaching SUBSCRIBED, not an arbitrary pause.
      await Future<void>.delayed(const Duration(seconds: 5));

      await a.sync.start(a.uid);
      await GymsRepository(a.db).createGym('Live RT realtime probe');
      await a.sync.pushOnce();

      expect(await hint, 'gyms');
    }, skip: _testRealtime ? null : 'Opt in with SUPABASE_TEST_REALTIME=true.');
  }, skip: skipReason);
}

String? outsiderSkip() => (_email2.isEmpty || _password2.isEmpty)
    ? 'Cross-user RLS needs a second account: set SUPABASE_TEST_EMAIL_2 and '
          'SUPABASE_TEST_PASSWORD_2. It cannot be faked — user_id has an FK to '
          'auth.users, so there is no synthetic foreign owner to test against.'
    : null;
