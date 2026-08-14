/// The cloud counterpart behind [SyncService] — mirrors how
/// `AuthProviderService` sits behind `AuthRepository`: a contract so
/// `SyncService` depends on a shape, not a concrete `SupabaseClient`, and so
/// tests can substitute [FakeSyncBackendService] without a live backend.
/// How many tombstones one [SyncBackendService.pullTombstones] page returns.
const int tombstonePageSize = 1000;

abstract interface class SyncBackendService {
  /// Whether this backend can actually reach a remote. False for
  /// [NoopSyncBackendService], which lets `SyncService` report
  /// `SyncPhase.disabled` instead of an empty outbox masquerading as a
  /// successful sync.
  bool get isConfigured;

  /// Upserts one row into [table] (Postgres RLS scopes it to [userId]
  /// server-side; `user_id` must still be present in [row] to satisfy the
  /// `with check (user_id = auth.uid())` policy on insert).
  Future<void> upsert(String table, Map<String, dynamic> row);

  /// Soft-deletes are pushed as an [upsert] of a tombstoned row (`deleted_at`
  /// set); this is only for the hard-delete fallback path — see
  /// `sync_triggers.dart`'s `trg_outbox_del_*` triggers.
  Future<void> delete(String table, String id);

  /// Rows in [table] belonging to [userId] with `updated_at > since`,
  /// including tombstoned (soft-deleted) rows so pull can propagate deletes.
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    required String userId,
    required DateTime since,
  });

  /// Hard deletes recorded server-side by `record_sync_tombstone()`
  /// (`0005_sync_tombstones.sql`) with `deleted_at` after [since], oldest
  /// first. Each map is `{entity_type, entity_id, deleted_at}`.
  ///
  /// This exists because a hard-deleted row can never come back from [pull] —
  /// it no longer exists to have an `updated_at` greater than any cursor — so
  /// without it a delete on one device never reaches the others. Soft deletes
  /// never appear here; they travel as tombstoned rows through [pull].
  ///
  /// [inclusive] switches the boundary from `>` to `>=` so the caller can page
  /// through a group of tombstones sharing one timestamp without cutting it in
  /// half.
  Future<List<Map<String, dynamic>>> pullTombstones({
    required String userId,
    required DateTime since,
    bool inclusive = false,
    int limit = tombstonePageSize,
  });

  /// Every `id` currently present remotely in [table] for [userId] — the
  /// existence snapshot behind the full reconcile that runs when a device has
  /// been offline longer than the tombstone retention window.
  ///
  /// An empty result means "this table is empty remotely", which is
  /// indistinguishable from a failed request, so callers must treat empty as
  /// "skip this table", never as "delete everything local".
  Future<Set<String>> pullExistingIds(String table, {required String userId});

  /// Emits the table name whenever a Realtime change lands for it — a hint
  /// to run a delta [pull], never a payload to apply directly (per
  /// HANDOFF.md's Phase 10 design: Realtime is latency, not the source of
  /// truth).
  Stream<String> realtimeHints(List<String> tables, {required String userId});

  void dispose();
}

/// Stands in for [SupabaseSyncBackendService] when the app has no backend
/// configured (`Env.hasSupabase == false`) — mirrors
/// `UnconfiguredAuthService`. Every method is a safe no-op so `SyncService`
/// never has to branch on whether a backend exists.
class NoopSyncBackendService implements SyncBackendService {
  const NoopSyncBackendService();

  @override
  bool get isConfigured => false;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) async {}

  @override
  Future<void> delete(String table, String id) async {}

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    required String userId,
    required DateTime since,
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> pullTombstones({
    required String userId,
    required DateTime since,
    bool inclusive = false,
    int limit = tombstonePageSize,
  }) async => const [];

  @override
  Future<Set<String>> pullExistingIds(
    String table, {
    required String userId,
  }) async => const <String>{};

  @override
  Stream<String> realtimeHints(List<String> tables, {required String userId}) =>
      const Stream.empty();

  @override
  void dispose() {}
}
