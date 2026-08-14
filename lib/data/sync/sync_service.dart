import 'dart:async';
import 'dart:developer' show log;
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';

import 'sync_backend_service.dart';
import 'sync_id_resolver.dart';
import 'sync_table_specs.dart';

/// After this many consecutive failures an outbox op is quarantined: it stops
/// being retried, stops blocking inbound pulls for its row, and is surfaced
/// as [SyncPhase.error] instead of retrying invisibly forever. With the
/// `min(300, 5 * 2^attempts)` backoff below this is roughly 20 minutes of
/// trying before the user is told something is wrong.
const int maxPushAttempts = 8;

/// Reserved `sync_cursors.entity_type` keys. Every real entry is a plain
/// snake_case table name from [syncTableOrder], so these can't collide, and
/// [SyncService.pullAll] only ever iterates that list — the reserved rows are
/// inert to the rest of the sync path.
const String _ownerKey = '__owner_uid__';
const String _lastSyncedKey = '__last_synced__';
const String _tombstoneKey = '__tombstones__';

/// The Postgres table `record_sync_tombstone()` writes to
/// (`0005_sync_tombstones.sql`). Never pulled as a normal entity — it has no
/// [SyncTableSpec] and no local counterpart.
const String tombstoneTable = 'sync_tombstones';

/// Must match the retention window of the `sync_tombstones_gc` job in
/// `0006_sync_tombstone_retention.sql`. Past this, delta pull can no longer
/// be trusted to have seen every delete, and the client falls back to a full
/// existence reconcile.
const Duration kTombstoneRetention = Duration(days: 90);

/// Slack for clock skew between device and server, and for GC lag.
const Duration _tombstoneSafetyMargin = Duration(days: 7);

/// Orchestrates Phase 10 cloud sync: drains the `pending_sync_ops` outbox
/// (populated by the triggers in `sync_triggers.dart`, no repository code
/// touched) to Postgres, and pulls remote deltas back into Drift.
///
/// Conflict resolution is last-write-wins on the *server's* `updated_at`
/// (set by a Postgres trigger, never trusted from the client) — see
/// `_pullTable`'s local-wins-while-pending check. Realtime is treated only
/// as a hint to re-run a delta pull, per HANDOFF.md, never applied directly.
class SyncService {
  SyncService({
    required GeneratedDatabase db,
    required SyncBackendService backend,
    Connectivity? connectivity,
  }) : _db = db,
       _backend = backend,
       _resolver = SyncIdResolver(db),
       _connectivity = connectivity ?? Connectivity();

  final GeneratedDatabase _db;
  final SyncBackendService _backend;
  final SyncIdResolver _resolver;
  final Connectivity _connectivity;

  String? _userId;
  Timer? _pushTimer;
  Timer? _pullTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<String>? _realtimeSub;
  bool _pushing = false;
  bool _pulling = false;

  final _stateController = StreamController<SyncState>.broadcast();
  SyncState _state = const SyncState(phase: SyncPhase.disabled);
  String? _lastRunError;

  /// The last error from a push or pull attempt, and whether a cycle has
  /// completed cleanly — this is the only thing the UI is allowed to derive a
  /// "synced" claim from (RB-02: never report success without the backend
  /// having actually acknowledged the write).
  SyncState get state => _state;

  /// Seeded with the current [state], so a late listener (the Riverpod
  /// `StreamProvider` in `providers.dart`, for instance) doesn't sit blank
  /// until the next sync tick.
  Stream<SyncState> get stateStream async* {
    yield _state;
    yield* _stateController.stream;
  }

  void _emit(SyncState next) {
    if (next == _state) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  /// Recomputes [state] from the outbox plus the outcome of whatever just
  /// ran. [syncing] marks work in flight; [error] is a failure from this
  /// cycle; [cleanCycle] means a push or pull round-trip completed without
  /// throwing (which is what lets the phase reach [SyncPhase.synced]).
  Future<void> _refreshState({
    bool syncing = false,
    String? error,
    bool cleanCycle = false,
  }) async {
    if (_userId == null || !_backend.isConfigured) {
      _emit(const SyncState(phase: SyncPhase.disabled));
      return;
    }

    if (error != null) _lastRunError = error;

    final counts = await _db
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM pending_sync_ops) AS total, '
          '(SELECT COUNT(*) FROM pending_sync_ops WHERE attempts >= ?) AS quarantined, '
          '(SELECT last_error FROM pending_sync_ops WHERE attempts >= ? '
          'ORDER BY attempts DESC LIMIT 1) AS quarantined_error',
          variables: [Variable(maxPushAttempts), Variable(maxPushAttempts)],
        )
        .getSingle();
    final total = counts.data['total'] as int;
    final quarantined = counts.data['quarantined'] as int;
    final quarantinedError = counts.data['quarantined_error'] as String?;

    if (cleanCycle && quarantined == 0) _lastRunError = null;

    final SyncPhase phase;
    if (quarantined > 0) {
      phase = SyncPhase.error;
    } else if (syncing) {
      phase = SyncPhase.syncing;
    } else if (total > 0) {
      // Queued work already says "not synced yet" without crying wolf: a push
      // that failed once is still going to be retried, and [lastError] carries
      // the detail for anyone who wants it.
      phase = SyncPhase.pending;
    } else if (!cleanCycle && _lastRunError != null) {
      // Nothing queued, yet the cycle still failed — a pull error. An empty
      // outbox must not be allowed to read as "synced" here; that inference is
      // the whole of RB-02.
      phase = SyncPhase.error;
    } else if (cleanCycle || _lastSyncedAt != null) {
      phase = SyncPhase.synced;
    } else {
      phase = SyncPhase.pending;
    }

    if (cleanCycle && total == 0 && quarantined == 0) {
      _lastSyncedAt = DateTime.now();
      await _writeCursor(_lastSyncedKey, _lastSyncedAt!.toIso8601String());
    }

    _emit(
      SyncState(
        phase: phase,
        pendingCount: total,
        quarantinedCount: quarantined,
        lastSyncedAt: _lastSyncedAt,
        lastError: quarantinedError ?? _lastRunError,
      ),
    );
  }

  DateTime? _lastSyncedAt;

  /// Callers that don't need to wait (e.g. the `ref.listen` sign-in hook in
  /// `providers.dart`) can call this without awaiting — it's still safe to
  /// await when the caller needs the initial sync to actually finish first
  /// (tests, in particular: awaiting removes the race that otherwise exists
  /// between an unawaited kick-off here and an explicit `pushOnce()`/
  /// `pullAll()` call made right after `start()` returns).
  Future<void> start(String userId) async {
    if (_userId == userId) return;
    // A different uid arriving while one is active would otherwise install a
    // second set of timers and subscriptions on top of the first.
    if (_userId != null) await stop();

    if (!_backend.isConfigured) {
      // No backend in this build — stay honest rather than idling in a state
      // the UI would render as "synced".
      _emit(const SyncState(phase: SyncPhase.disabled));
      return;
    }

    await _claimLocalDatabaseFor(userId);
    _userId = userId;
    _lastSyncedAt = await _readLastSyncedAt();

    _pushTimer = Timer.periodic(const Duration(seconds: 20), (_) => pushOnce());
    _pullTimer = Timer.periodic(const Duration(minutes: 5), (_) => pullAll());
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        pushOnce();
        pullAll();
      }
    });
    _realtimeSub = _backend
        .realtimeHints([...syncTableOrder, tombstoneTable], userId: userId)
        // Routed through [pullAll] rather than straight into [_pullTable] so
        // a hint landing mid-cycle can't interleave writes with the running
        // pull and race its cursor upsert — the `_pulling` guard makes the
        // hint a no-op while a pull is already in flight, and the 5-minute
        // timer picks up anything that hint would have covered.
        .listen((_) => pullAll());

    await pushOnce();
    await pullAll();
  }

  Future<void> stop() async {
    _userId = null;
    _pushTimer?.cancel();
    _pullTimer?.cancel();
    _pushTimer = null;
    _pullTimer = null;
    await _connectivitySub?.cancel();
    await _realtimeSub?.cancel();
    _connectivitySub = null;
    _realtimeSub = null;
    _lastSyncedAt = null;
    _lastRunError = null;
    _backend.dispose();
    _emit(const SyncState(phase: SyncPhase.disabled));
  }

  /// Releases the state stream. Separate from [stop] because
  /// `syncServiceProvider` stops the service on every sign-out but only
  /// disposes it when the provider itself goes away.
  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }

  // ── Local-database ownership ───────────────────────────────────────────

  /// The local database is shared by whoever signs in on this device, and the
  /// SQLite outbox triggers have no auth context — so an outbox drained after
  /// an account switch would push the previous user's rows into the new
  /// user's cloud account under the new `user_id`. Ownership is recorded in
  /// `sync_cursors` under a reserved key (no real table is named this, and
  /// [pullAll] only ever iterates [syncTableOrder], so the row is inert to
  /// the rest of the sync path).
  ///
  /// On a uid change the outbox and every cursor are cleared: the previous
  /// user's unpushed local edits are deliberately dropped rather than
  /// uploaded to the wrong account.
  Future<void> _claimLocalDatabaseFor(String userId) async {
    final owner = await _readCursor(_ownerKey);
    if (owner == userId) return;

    if (owner != null) {
      log('SyncService: local database owner changed ($owner -> $userId); '
          'clearing outbox and cursors');
      await _db.customUpdate('DELETE FROM pending_sync_ops');
      await _db.customUpdate('DELETE FROM sync_cursors');
      _lastSyncedAt = null;
      _lastRunError = null;
    }
    await _writeCursor(_ownerKey, userId);
  }

  Future<DateTime?> _readLastSyncedAt() async {
    final raw = await _readCursor(_lastSyncedKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<String?> _readCursor(String key) async {
    final row = await _db
        .customSelect(
          'SELECT cursor_iso FROM sync_cursors WHERE entity_type = ?',
          variables: [Variable(key)],
        )
        .getSingleOrNull();
    return row?.data['cursor_iso'] as String?;
  }

  Future<void> _writeCursor(String key, String value) async {
    await _db.customUpdate(
      'INSERT INTO sync_cursors (entity_type, cursor_iso) VALUES (?, ?) '
      'ON CONFLICT(entity_type) DO UPDATE SET cursor_iso = excluded.cursor_iso',
      variables: [Variable(key), Variable(value)],
    );
  }

  // ── Push ───────────────────────────────────────────────────────────────

  Future<void> pushOnce() async {
    final userId = _userId;
    if (userId == null || _pushing) return;
    _pushing = true;
    try {
      await _refreshState(syncing: true);
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final ops = await _db
          .customSelect(
            // `id ASC` is not decoration: the outbox triggers stamp
            // `created_at` with `strftime('%s','now')`, so a parent and its
            // child enqueued in the same second tie. Postgres FKs require the
            // parent row first, and ordering within a tie is otherwise
            // whatever the query plan happens to produce.
            //
            // This orders by *enqueue* order, which is not the same as
            // dependency order: re-editing an already-pending parent moves
            // its `created_at` past its child's (the trigger's `ON CONFLICT
            // … SET created_at = excluded.created_at`), so the child can
            // still be attempted first. That case self-heals — the child's
            // FK violation is a normal push failure, the parent goes up in
            // the same cycle, and the retry succeeds — but it does mean a
            // brief `pending` blip rather than a clean cycle.
            'SELECT * FROM pending_sync_ops '
            'WHERE attempts < ? '
            'AND (next_retry_at IS NULL OR next_retry_at <= ?) '
            'ORDER BY created_at ASC, id ASC',
            variables: [Variable(maxPushAttempts), Variable(nowSeconds)],
          )
          .get();
      var clean = true;
      for (final op in ops) {
        if (!await _pushOne(op.data, userId)) clean = false;
      }
      await _refreshState(cleanCycle: clean);
    } finally {
      _pushing = false;
    }
  }

  /// Returns whether the op was acknowledged by the backend and removed from
  /// the outbox.
  Future<bool> _pushOne(Map<String, dynamic> op, String userId) async {
    final table = op['entity_type'] as String;
    final entityId = op['entity_id'] as String;
    final operation = op['operation'] as String;
    final opId = op['id'] as int;

    try {
      if (operation == 'delete') {
        await _backend.delete(table, entityId);
      } else {
        final row = await _db
            .customSelect(
              'SELECT * FROM $table WHERE sync_uuid = ?',
              variables: [Variable(entityId)],
            )
            .getSingleOrNull();
        if (row != null) {
          final payload = await _buildRemotePayload(table, row.data, userId);
          await _backend.upsert(table, payload);
          final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          await _db.customUpdate(
            'UPDATE $table SET synced_at = ? WHERE sync_uuid = ?',
            variables: [Variable(nowSeconds), Variable(entityId)],
            updates: {},
          );
        }
        // else: row is gone locally (e.g. hard-deleted after enqueue but
        // before push) — nothing left to push; fall through to ack removal.
      }
      await _db.customUpdate(
        'DELETE FROM pending_sync_ops WHERE id = ?',
        variables: [Variable(opId)],
      );
      return true;
    } catch (e) {
      final attempts = (op['attempts'] as int? ?? 0) + 1;
      final delaySeconds = math.min(300, 5 * (1 << math.min(attempts, 6)));
      final nextRetry =
          DateTime.now().add(Duration(seconds: delaySeconds)).millisecondsSinceEpoch ~/
          1000;
      // `user_id` is stamped here rather than by the SQLite trigger, which
      // has no auth context — it is forensic only (ownership is enforced by
      // `_claimLocalDatabaseFor`), so a quarantined op can be traced to the
      // account that produced it.
      await _db.customUpdate(
        'UPDATE pending_sync_ops '
        'SET attempts = ?, last_error = ?, next_retry_at = ?, user_id = ? '
        'WHERE id = ?',
        variables: [
          Variable(attempts),
          Variable(e.toString()),
          Variable(nextRetry),
          Variable(userId),
          Variable(opId),
        ],
        updates: {},
      );
      _lastRunError = e.toString();
      if (attempts >= maxPushAttempts) {
        log('SyncService quarantined $table/$entityId after $attempts attempts: $e');
      } else {
        log('SyncService push failed for $table/$entityId (attempt $attempts): $e');
      }
      return false;
    }
  }

  /// Builds the Postgres-shaped payload for one local row: renames columns
  /// that need it, resolves FK fields via [SyncIdResolver], converts
  /// DateTime columns from local epoch-seconds to ISO 8601, and drops
  /// columns with no remote counterpart. Every remaining column is assumed
  /// to already match its remote name 1:1 (true by construction — the
  /// Postgres schema was generated directly from `tables.dart`).
  Future<Map<String, dynamic>> _buildRemotePayload(
    String table,
    Map<String, dynamic> row,
    String userId,
  ) async {
    final spec = syncTableSpecsByName[table]!;
    final remote = <String, dynamic>{'id': row['sync_uuid'], 'user_id': userId};
    final consumed = <String>{
      'id',
      'sync_uuid',
      'updated_at',
      'synced_at',
      ...spec.localOnlyColumns,
    };

    for (final entry in spec.columnRenames.entries) {
      remote[entry.value] = row[entry.key];
      consumed.add(entry.key);
    }

    for (final fk in spec.fkFields) {
      if (fk is SimpleFk) {
        consumed.add(fk.localColumn);
        final localId = row[fk.localColumn] as int?;
        remote[fk.remoteColumn] = localId == null
            ? null
            : await _resolver.localIdToSyncUuid(fk.parentTable, localId);
      } else if (fk is CatalogueFk) {
        consumed.add(fk.localColumn);
        final localId = row[fk.localColumn] as int?;
        if (localId == null) {
          remote[fk.remoteUuidColumn] = null;
          remote[fk.remoteNaturalKeyColumn] = null;
        } else {
          final (uuid, naturalKey) = await _resolver.resolveCatalogueRefForPush(
            localTable: fk.parentTable,
            localId: localId,
            naturalKeyColumn: fk.naturalKeyColumn,
            isCustomColumn: fk.isCustomColumn,
          );
          remote[fk.remoteUuidColumn] = uuid;
          remote[fk.remoteNaturalKeyColumn] = naturalKey;
        }
      } else if (fk is BandFk) {
        consumed.add(fk.localColumn);
        final localId = row[fk.localColumn] as int?;
        if (localId == null) {
          remote['band_id'] = null;
          remote['band_color'] = null;
          remote['band_tension_kg'] = null;
        } else {
          final (uuid, color, tension) = await _resolver.resolveBandRefForPush(
            localId,
          );
          remote['band_id'] = uuid;
          remote['band_color'] = color;
          remote['band_tension_kg'] = tension;
        }
      }
    }

    for (final entry in row.entries) {
      if (consumed.contains(entry.key)) continue;
      remote[entry.key] = entry.value;
    }

    for (final dtCol in [...spec.dateTimeColumns, 'deleted_at']) {
      if (remote.containsKey(dtCol)) {
        remote[dtCol] = _epochToIso(remote[dtCol]);
      }
    }

    return remote;
  }

  // ── Pull ───────────────────────────────────────────────────────────────

  Future<void> pullAll() async {
    final userId = _userId;
    if (userId == null || _pulling) return;
    _pulling = true;
    try {
      await _refreshState(syncing: true);
      // Tombstones FIRST. A hard-deleted row cannot appear in any row pull, so
      // every row [_pullTable] returns exists remotely *right now* — row pulls
      // are therefore always fresher than any tombstone and have to be applied
      // last, where they win. Reversing this order deletes rows that were
      // re-created after the tombstone was written.
      var clean = await _pullTombstones(userId);
      for (final table in syncTableOrder) {
        if (!await _pullTable(table, userId)) clean = false;
      }
      await _refreshState(cleanCycle: clean);
    } finally {
      _pulling = false;
    }
  }

  /// Returns whether the table's delta pull completed without error.
  Future<bool> _pullTable(String table, String userId) async {
    final spec = syncTableSpecsByName[table];
    if (spec == null) return true;

    final cursorRow = await _db
        .customSelect(
          'SELECT cursor_iso FROM sync_cursors WHERE entity_type = ?',
          variables: [Variable(table)],
        )
        .getSingleOrNull();
    final since = cursorRow == null
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.parse(cursorRow.data['cursor_iso'] as String);

    List<Map<String, dynamic>> remoteRows;
    try {
      remoteRows = await _backend.pull(table, userId: userId, since: since);
    } catch (e) {
      // Surfaced through [state] as well as the log — a silently swallowed
      // pull failure is exactly the "looks synced, isn't" behavior RB-02 is
      // about.
      _lastRunError = e.toString();
      log('SyncService pull failed for $table: $e');
      return false;
    }
    if (remoteRows.isEmpty) return true;

    var latest = since;
    for (final remoteRow in remoteRows) {
      await _applyPulledRow(table, spec, remoteRow);
      final updatedAt = DateTime.tryParse(remoteRow['updated_at'] as String? ?? '');
      if (updatedAt != null && updatedAt.isAfter(latest)) latest = updatedAt;
    }

    await _writeCursor(table, latest.toIso8601String());
    return true;
  }

  // ── Tombstones (hard deletes made on another device) ───────────────────

  /// Drains new tombstones and applies them as local deletes. Returns whether
  /// the pass completed without error.
  Future<bool> _pullTombstones(String userId) async {
    final cursorIso = await _readCursor(_tombstoneKey);

    if (cursorIso == null) {
      // First sync on this device: nothing local can predate the account's
      // tombstones in a way that matters, so start the cursor at now rather
      // than replaying the whole retention window as no-op deletes.
      await _writeCursor(_tombstoneKey, DateTime.now().toUtc().toIso8601String());
      return true;
    }

    final since = DateTime.parse(cursorIso);
    if (DateTime.now().toUtc().difference(since) >
        kTombstoneRetention - _tombstoneSafetyMargin) {
      return _fullReconcile(userId);
    }

    final seen = <String>{};
    final batch = <Map<String, dynamic>>[];
    try {
      var page = await _backend.pullTombstones(userId: userId, since: since);
      while (page.isNotEmpty) {
        for (final tombstone in page) {
          final key = '${tombstone['entity_type']}/${tombstone['entity_id']}';
          if (seen.add(key)) batch.add(tombstone);
        }
        if (page.length < tombstonePageSize) break;
        // Re-request the last page's final timestamp inclusively and dedupe in
        // memory, so a group of tombstones sharing one `deleted_at` (every
        // cascading delete produces one) is never cut in half by the page
        // boundary. The *persisted* cursor stays strict — an inclusive
        // persisted cursor would re-apply the boundary tombstone on every pull
        // forever, killing any row later resurrected under the same uuid.
        page = await _backend.pullTombstones(
          userId: userId,
          since: DateTime.parse(page.last['deleted_at'] as String),
          inclusive: true,
        );
      }
    } catch (e) {
      _lastRunError = e.toString();
      log('SyncService tombstone pull failed: $e');
      return false;
    }

    if (batch.isEmpty) return true;

    final appliedThrough = await _applyTombstoneBatch(batch);
    if (appliedThrough != null) {
      await _writeCursor(_tombstoneKey, appliedThrough.toUtc().toIso8601String());
    }
    // A batch that stopped early left the cursor behind the failure, so the
    // blocked tombstone is retried on the next pull rather than lost.
    return appliedThrough != null &&
        appliedThrough ==
            DateTime.parse(batch.last['deleted_at'] as String).toUtc();
  }

  /// Applies a tombstone batch inside one transaction and returns the newest
  /// `deleted_at` that was fully applied (null if none were).
  Future<DateTime?> _applyTombstoneBatch(
    List<Map<String, dynamic>> batch,
  ) async {
    final rank = {
      for (var i = 0; i < syncTableOrder.length; i++) syncTableOrder[i]: i,
    };
    final ordered =
        batch
            // `entity_type` is network input about to be interpolated into
            // `DELETE FROM $table`. Whitelisting it against the known table
            // list is what keeps that safe — and it also makes this build
            // forward-compatible with a server that starts tombstoning a table
            // this version has never heard of.
            .where((t) => rank.containsKey(t['entity_type']))
            .toList()
          ..sort((a, b) {
            final byTime = (a['deleted_at'] as String).compareTo(
              b['deleted_at'] as String,
            );
            if (byTime != 0) return byTime;
            // Children before parents within one delete transaction: local FKs
            // include RESTRICT edges (set_bands -> bands, food_entries ->
            // foods, ...) where deleting the parent first throws.
            return rank[b['entity_type']]!.compareTo(rank[a['entity_type']]!);
          });

    DateTime? appliedThrough;
    await _db.transaction(() async {
      // Drift serializes every query on the executor for the duration of a
      // transaction, so no unrelated repository write can land between this
      // read and the purge below — every outbox row created inside this window
      // is, by construction, an echo of a delete we just applied.
      final watermark =
          (await _db
                  .customSelect(
                    'SELECT COALESCE(MAX(id), 0) AS max_id FROM pending_sync_ops',
                  )
                  .getSingle())
              .data['max_id']
              as int;

      for (final tombstone in ordered) {
        final table = tombstone['entity_type'] as String;
        final id = tombstone['entity_id'] as String;

        // Same local-wins-while-pending rule as [_applyPulledRow]: an unpushed
        // local edit outranks a remote delete. It pushes as an upsert and
        // re-creates the row remotely, and because tombstones are applied
        // before row pulls, every other device converges on "exists".
        final pending = await _db
            .customSelect(
              'SELECT 1 FROM pending_sync_ops '
              'WHERE entity_type = ? AND entity_id = ? AND attempts < ?',
              variables: [
                Variable(table),
                Variable(id),
                Variable(maxPushAttempts),
              ],
            )
            .getSingleOrNull();
        if (pending != null) continue;

        try {
          await _db.customUpdate(
            'DELETE FROM $table WHERE sync_uuid = ?',
            variables: [Variable(id)],
            updates: {},
          );
          appliedThrough = DateTime.parse(
            tombstone['deleted_at'] as String,
          ).toUtc();
        } catch (e) {
          _lastRunError = e.toString();
          log('SyncService tombstone apply failed for $table/$id: $e');
          break;
        }
      }

      await _purgeEchoedDeletes(watermark);
    });
    return appliedThrough;
  }

  /// `trg_outbox_del_*` fired for every row the tombstone pass just deleted
  /// (and for every FK-cascaded child), enqueueing outbound `delete` ops for
  /// rows that are already gone remotely. Those are not harmless: if another
  /// device resurrected the row in the meantime — by pushing an edit it had
  /// pending when the delete happened — pushing this echo would hard-delete
  /// the newer row for everyone. A stale local tombstone would reach through
  /// the outbox and override a newer write.
  ///
  /// Only `delete` ops are purged. An `ON DELETE SET NULL` cascade fires
  /// `trg_outbox_upd_*` instead, and that upsert is a legitimate local state
  /// change worth pushing.
  Future<void> _purgeEchoedDeletes(int watermark) async {
    await _db.customUpdate(
      "DELETE FROM pending_sync_ops WHERE id > ? AND operation = 'delete'",
      variables: [Variable(watermark)],
      updates: {},
    );
  }

  /// Fallback for a device that has been offline longer than the tombstone
  /// retention window, where delta pull can no longer prove it has seen every
  /// delete. Compares local rows against the remote id set per table and
  /// removes the ones that are provably gone.
  Future<bool> _fullReconcile(String userId) async {
    log('SyncService: tombstone cursor older than retention; full reconcile');
    var clean = true;

    for (final table in syncTableOrder.reversed) {
      Set<String> remoteIds;
      try {
        remoteIds = await _backend.pullExistingIds(table, userId: userId);
      } catch (e) {
        _lastRunError = e.toString();
        log('SyncService reconcile failed for $table: $e');
        clean = false;
        continue;
      }
      // Empty is ambiguous — a genuinely empty remote table looks exactly like
      // a failed request. Skipping leaves stale rows, which is recoverable;
      // the alternative wipes the table, which is not.
      if (remoteIds.isEmpty) continue;

      await _db.transaction(() async {
        final watermark =
            (await _db
                    .customSelect(
                      'SELECT COALESCE(MAX(id), 0) AS max_id FROM pending_sync_ops',
                    )
                    .getSingle())
                .data['max_id']
                as int;

        final pendingIds = (await _db
                .customSelect(
                  'SELECT entity_id FROM pending_sync_ops WHERE entity_type = ?',
                  variables: [Variable(table)],
                )
                .get())
            .map((row) => row.data['entity_id'] as String)
            .toSet();

        // `synced_at IS NOT NULL` is essential: a row created locally while
        // offline has never been pushed, so its absence from the remote id set
        // means "not uploaded yet", not "deleted elsewhere".
        final localRows = await _db
            .customSelect(
              'SELECT sync_uuid FROM $table '
              'WHERE sync_uuid IS NOT NULL AND synced_at IS NOT NULL',
            )
            .get();

        for (final row in localRows) {
          final uuid = row.data['sync_uuid'] as String;
          if (remoteIds.contains(uuid) || pendingIds.contains(uuid)) continue;
          await _db.customUpdate(
            'DELETE FROM $table WHERE sync_uuid = ?',
            variables: [Variable(uuid)],
            updates: {},
          );
        }

        await _purgeEchoedDeletes(watermark);
      });
    }

    await _writeCursor(_tombstoneKey, DateTime.now().toUtc().toIso8601String());
    return clean;
  }

  /// Applies one pulled remote row to Drift, keyed by `sync_uuid`. Skips the
  /// row entirely if a local edit for the same `sync_uuid` is still sitting
  /// unpushed in the outbox — local wins until it's pushed, per HANDOFF.md's
  /// LWW design (the server's `updated_at` is authoritative only once both
  /// sides have actually seen each other's write).
  ///
  /// Quarantined ops are excluded from that guard: an op the client has
  /// provably failed to push [maxPushAttempts] times would otherwise freeze
  /// its row in *both* directions forever, so the server is allowed to win.
  Future<void> _applyPulledRow(
    String table,
    SyncTableSpec spec,
    Map<String, dynamic> remoteRow,
  ) async {
    final syncUuid = remoteRow['id'] as String;

    final pending = await _db
        .customSelect(
          'SELECT 1 FROM pending_sync_ops '
          'WHERE entity_type = ? AND entity_id = ? AND attempts < ?',
          variables: [
            Variable(table),
            Variable(syncUuid),
            Variable(maxPushAttempts),
          ],
        )
        .getSingleOrNull();
    if (pending != null) return;

    final local = <String, dynamic>{'sync_uuid': syncUuid};

    for (final fk in spec.fkFields) {
      if (fk is SimpleFk) {
        final remoteValue = remoteRow[fk.remoteColumn] as String?;
        local[fk.localColumn] = remoteValue == null
            ? null
            : await _resolver.syncUuidToLocalId(fk.parentTable, remoteValue);
      } else if (fk is CatalogueFk) {
        local[fk.localColumn] = await _resolver.resolveCatalogueRefForPull(
          localTable: fk.parentTable,
          naturalKeyColumn: fk.naturalKeyColumn,
          uuid: remoteRow[fk.remoteUuidColumn] as String?,
          naturalKey: remoteRow[fk.remoteNaturalKeyColumn] as String?,
        );
      } else if (fk is BandFk) {
        local[fk.localColumn] = await _resolver.resolveBandRefForPull(
          uuid: remoteRow['band_id'] as String?,
          color: remoteRow['band_color'] as String?,
          tensionKg: (remoteRow['band_tension_kg'] as num?)?.toDouble(),
        );
      }
    }

    final consumedRemote = <String>{
      'id',
      'user_id',
      'updated_at',
      ...spec.fkFields.expand(
        (fk) => switch (fk) {
          SimpleFk() => [fk.remoteColumn],
          CatalogueFk() => [fk.remoteUuidColumn, fk.remoteNaturalKeyColumn],
          BandFk() => ['band_id', 'band_color', 'band_tension_kg'],
          _ => const <String>[],
        },
      ),
    };
    final renameTargetToLocal = {
      for (final entry in spec.columnRenames.entries) entry.value: entry.key,
    };

    for (final entry in remoteRow.entries) {
      if (consumedRemote.contains(entry.key)) continue;
      final localColumn = renameTargetToLocal[entry.key] ?? entry.key;
      var value = entry.value;
      if ([...spec.dateTimeColumns, 'deleted_at'].contains(localColumn) &&
          value != null) {
        value = _isoToEpoch(value as String);
      }
      local[localColumn] = value;
    }

    final columns = local.keys.join(', ');
    final placeholders = List.filled(local.length, '?').join(', ');
    final updateAssignments = local.keys
        .where((c) => c != 'sync_uuid')
        .map((c) => '$c = excluded.$c')
        .join(', ');
    await _db.customUpdate(
      'INSERT INTO $table ($columns) VALUES ($placeholders) '
      'ON CONFLICT(sync_uuid) DO UPDATE SET $updateAssignments',
      variables: local.values.map(Variable.new).toList(),
    );

    // The INSERT/UPDATE above just fired `trg_outbox_ins_$table` or
    // `trg_outbox_upd_$table` — those triggers can't tell a locally-authored
    // write from us writing down a row we just pulled, so they enqueue an
    // outbox op either way. Left alone this is more than churn: the
    // `pending != null` guard above means we only ever reach this point when
    // there was *no* pre-existing op for this entity, so anything present
    // now is purely an echo of our own write, safe to remove. Until it's
    // removed, `_applyTombstoneBatch`'s local-wins check treats it as a real
    // unpushed edit and refuses to apply a same-cycle or later delete for
    // this entity — a delete on another device that lands soon after this
    // row's first arrival here would otherwise sit invisibly stuck for up to
    // the next 20s push timer.
    await _db.customUpdate(
      "DELETE FROM pending_sync_ops WHERE entity_type = ? AND entity_id = ?",
      variables: [Variable(table), Variable(syncUuid)],
    );
  }

  String? _epochToIso(dynamic value) {
    if (value == null) return null;
    final seconds = value as int;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toIso8601String();
  }

  int? _isoToEpoch(String? value) {
    if (value == null) return null;
    return DateTime.parse(value).toUtc().millisecondsSinceEpoch ~/ 1000;
  }
}

/// What the sync layer is actually doing, as opposed to what the old
/// `SyncEngine` inferred from an empty outbox table. Nothing here may be
/// derived without the backend having been talked to.
enum SyncPhase {
  /// No signed-in user, or this build has no backend configured
  /// (`Env.hasSupabase == false` → [NoopSyncBackendService]). Must never be
  /// rendered as success.
  disabled,

  /// A push or pull is in flight.
  syncing,

  /// Local changes are waiting to reach the backend — either not yet
  /// attempted, or attempted and backing off for a retry.
  pending,

  /// The outbox is empty *and* a round-trip completed without error.
  synced,

  /// At least one op has exhausted [maxPushAttempts], or the last cycle
  /// failed outright. Needs user-visible treatment.
  error,
}

/// Immutable snapshot of [SyncService.state].
class SyncState {
  const SyncState({
    required this.phase,
    this.pendingCount = 0,
    this.quarantinedCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final SyncPhase phase;

  /// Rows currently in `pending_sync_ops`, including quarantined ones.
  final int pendingCount;

  /// Rows that have hit [maxPushAttempts] and are no longer being retried.
  final int quarantinedCount;

  /// When a push+pull cycle last completed with an empty outbox. Persisted
  /// across restarts, so this survives an app relaunch.
  final DateTime? lastSyncedAt;

  final String? lastError;

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.phase == phase &&
      other.pendingCount == pendingCount &&
      other.quarantinedCount == quarantinedCount &&
      other.lastSyncedAt == lastSyncedAt &&
      other.lastError == lastError;

  @override
  int get hashCode =>
      Object.hash(phase, pendingCount, quarantinedCount, lastSyncedAt, lastError);

  @override
  String toString() =>
      'SyncState($phase, pending: $pendingCount, quarantined: $quarantinedCount, '
      'lastSyncedAt: $lastSyncedAt, lastError: $lastError)';
}
