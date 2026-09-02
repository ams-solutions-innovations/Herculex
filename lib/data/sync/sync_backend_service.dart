/// The cloud counterpart behind [SyncService] — mirrors how
/// `AuthProviderService` sits behind `AuthRepository`: a contract so
/// `SyncService` depends on a shape, not a concrete `SupabaseClient`, and so
/// tests can substitute [FakeSyncBackendService] without a live backend.
/// How many tombstones one [SyncBackendService.pullTombstones] page returns.
const int tombstonePageSize = 1000;

/// How many rows one [SyncBackendService.pull] / [pullExistingIds] page
/// returns.
///
/// Supabase's PostgREST caps every response at the project's `db-max-rows`
/// setting (**1000 by default**), and it does so *silently* — a truncated
/// response is indistinguishable from a complete one. Before this constant
/// existed, `pull` sent no `limit`, no `order` and no `range`, so a delta
/// larger than that cap came back as an arbitrary, unordered 1000 rows and
/// `_pullTable` then advanced its cursor to the largest `updated_at` in that
/// batch — permanently skipping every older row the cap had cut off.
///
/// Kept comfortably under the default cap so the page boundary is decided
/// here, by keyset paging we control, rather than by a server setting that
/// can be changed in the dashboard without anyone touching this code.
const int pullPageSize = 500;

/// What kind of failure a [SyncBackendService] call hit. The distinction is
/// load-bearing, not cosmetic: `SyncService` retries every failure eight
/// times with backoff, so before this existed an expired JWT (which no
/// number of retries can fix, and which a token refresh fixes instantly)
/// quarantined the entire outbox in about twenty minutes, and a missing
/// Postgres column (which no retry can fix either) burned eight attempts per
/// row before going quiet.
enum SyncErrorKind {
  /// Expired / missing / rejected JWT. Must NOT count as a push attempt —
  /// refresh the session and try the same op again.
  auth,

  /// The remote schema does not have what the payload names: PostgREST
  /// `PGRST204` (unknown column), `42P01` (unknown table), `42703` (unknown
  /// column). Always means a `supabase/migrations/` file has not been
  /// applied. Retrying is pointless — quarantine immediately and say so
  /// loudly.
  schema,

  /// `23503` — the parent row has not been pushed yet. Self-heals on the
  /// next cycle once the parent goes up, so this is the one kind where the
  /// existing retry-with-backoff behaviour is exactly right.
  foreignKey,

  /// `23505` — the row is already there. Under last-write-wins this is not a
  /// failure; the op can be acknowledged.
  conflict,

  /// Network, timeout, 5xx. Retry with backoff.
  transient,

  /// Anything unclassified. Treated like [transient].
  unknown,
}

/// A backend failure with its [kind] resolved, so callers can branch on the
/// cause instead of pattern-matching `e.toString()`.
class SyncBackendException implements Exception {
  const SyncBackendException(this.kind, this.message, {this.code});

  final SyncErrorKind kind;
  final String message;

  /// The PostgREST / SQLSTATE code, when the backend gave one.
  final String? code;

  /// Whether retrying this op could ever succeed without something else
  /// changing first.
  bool get isRetryable =>
      kind == SyncErrorKind.foreignKey ||
      kind == SyncErrorKind.transient ||
      kind == SyncErrorKind.unknown;

  @override
  String toString() =>
      'SyncBackendException(${kind.name}${code == null ? '' : ', $code'}): '
      '$message';
}

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
