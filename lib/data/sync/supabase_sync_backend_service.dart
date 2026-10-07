import 'dart:async';
import 'dart:io';

import 'package:herculex/data/sync/sync_backend_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Real [SyncBackendService], wrapping the same `Supabase.instance.client`
/// singleton `SupabaseAuthService` already uses. `updated_at` is never sent
/// on [upsert] — it's server-trigger-set (`0004_sync_triggers.sql`) and must
/// stay the authoritative LWW clock, not a client-supplied value.
///
/// Every method funnels its failures through [_classify], so callers get a
/// [SyncBackendException] with a resolved [SyncErrorKind] rather than a bare
/// `PostgrestException` whose `toString()` makes `401 JWT expired` and
/// `23503 foreign_key_violation` look identical.
class SupabaseSyncBackendService implements SyncBackendService {
  SupabaseSyncBackendService(this._client);

  final SupabaseClient _client;
  final Map<String, RealtimeChannel> _channels = {};

  @override
  bool get isConfigured => true;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) async {
    final payload = Map<String, dynamic>.from(row)..remove('updated_at');
    await _guard(() => _client.from(table).upsert(payload));
  }

  @override
  Future<void> delete(String table, String id) async {
    // Hard-delete fallback path only (see sync_triggers.dart's
    // trg_outbox_del_* comment) — routine soft-deletes go through upsert
    // with deleted_at set, handled by the caller before this is reached.
    await _guard(() => _client.from(table).delete().eq('id', id));
  }

  /// Delta pull, paged by keyset on `(updated_at, id)`.
  ///
  /// The ordering and the paging are both required for correctness, not
  /// speed. PostgREST truncates any response at the project's `db-max-rows`
  /// (1000 by default) without saying so, and `_pullTable` advances its
  /// cursor to the largest `updated_at` it was handed — so an unordered,
  /// unpaged request silently and permanently skips every row the cap cut
  /// off. That is the single failure mode in this file that loses data
  /// rather than merely delaying it.
  ///
  /// `id` is the tie-break rather than decoration: a cascading write stamps
  /// many rows with one `now()`, so a page boundary can land in the middle
  /// of a group sharing an `updated_at`. Paging on `updated_at` alone would
  /// then either loop forever (a full page of identical timestamps never
  /// advances the cursor) or skip the rest of the group. The composite
  /// keyset does neither.
  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    required String userId,
    required DateTime since,
  }) async {
    return _guard(() async {
      final out = <Map<String, dynamic>>[];
      var cursorIso = since.toUtc().toIso8601String();
      String? cursorId;

      while (true) {
        final base = _client.from(table).select().eq('user_id', userId);
        // First page has no id to tie-break against, so a plain `>` on the
        // timestamp is exact. Subsequent pages resume strictly after the
        // last row of the previous one.
        final filtered = cursorId == null
            ? base.gt('updated_at', cursorIso)
            : base.or(
                'updated_at.gt."$cursorIso",'
                'and(updated_at.eq."$cursorIso",id.gt."$cursorId")',
              );

        final rows = await filtered
            .order('updated_at', ascending: true)
            .order('id', ascending: true)
            .limit(pullPageSize);

        final page = (rows as List).cast<Map<String, dynamic>>();
        if (page.isEmpty) break;
        out.addAll(page);
        if (page.length < pullPageSize) break;

        final last = page.last;
        cursorIso = last['updated_at'] as String;
        cursorId = last['id'] as String;
      }
      return out;
    });
  }

  @override
  Future<List<Map<String, dynamic>>> pullTombstones({
    required String userId,
    required DateTime since,
    bool inclusive = false,
    int limit = tombstonePageSize,
  }) async {
    return _guard(() async {
      final iso = since.toUtc().toIso8601String();
      final scoped = _client
          .from('sync_tombstones')
          .select('entity_type, entity_id, deleted_at')
          .eq('user_id', userId);
      final rows =
          await (inclusive
                  ? scoped.gte('deleted_at', iso)
                  : scoped.gt('deleted_at', iso))
              // Ordered so paging is deterministic across a group of
              // tombstones written by one cascading delete, which all share
              // `now()`.
              .order('deleted_at', ascending: true)
              .order('entity_type', ascending: true)
              .order('entity_id', ascending: true)
              .limit(limit);
      return (rows as List).cast<Map<String, dynamic>>();
    });
  }

  /// Paged for the same reason [pull] is, and more urgently: the caller
  /// (`SyncService._fullReconcile`) *deletes* every local row whose id is
  /// absent from this set. A response truncated at `db-max-rows` would make
  /// the reconcile delete rows that exist perfectly well remotely.
  ///
  /// Keyset on `id` alone is enough here — it is the primary key, so it is
  /// unique and totally ordered.
  @override
  Future<Set<String>> pullExistingIds(
    String table, {
    required String userId,
  }) async {
    return _guard(() async {
      final ids = <String>{};
      String? cursorId;

      while (true) {
        final base = _client.from(table).select('id').eq('user_id', userId);
        final filtered = cursorId == null ? base : base.gt('id', cursorId);
        final rows = await filtered
            .order('id', ascending: true)
            .limit(pullPageSize);

        final page = (rows as List).cast<Map<String, dynamic>>();
        if (page.isEmpty) break;
        for (final row in page) {
          ids.add(row['id'] as String);
        }
        if (page.length < pullPageSize) break;
        cursorId = page.last['id'] as String;
      }
      return ids;
    });
  }

  @override
  Stream<String> realtimeHints(List<String> tables, {required String userId}) {
    final controller = StreamController<String>.broadcast();
    for (final table in tables) {
      final channel = _client
          .channel('sync_${table}_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              if (!controller.isClosed) controller.add(table);
            },
          )
          .subscribe();
      _channels[table] = channel;
    }
    controller.onCancel = () {
      for (final channel in _channels.values) {
        _client.removeChannel(channel);
      }
      _channels.clear();
    };
    return controller.stream;
  }

  @override
  void dispose() {
    for (final channel in _channels.values) {
      _client.removeChannel(channel);
    }
    _channels.clear();
  }

  // ── Error classification ─────────────────────────────────────────────

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on SyncBackendException {
      rethrow;
    } catch (e) {
      throw _classify(e);
    }
  }

  /// Maps a raw exception onto a [SyncErrorKind]. The codes come from two
  /// namespaces that PostgREST mixes in one field: its own `PGRST*` codes
  /// and the underlying Postgres SQLSTATEs.
  static SyncBackendException _classify(Object e) {
    if (e is PostgrestException) {
      final code = e.code;
      final message = e.message;
      switch (code) {
        // PostgREST: JWT expired / invalid / role not found.
        case 'PGRST301':
        case 'PGRST302':
        case '401':
        case '403':
          return SyncBackendException(SyncErrorKind.auth, message, code: code);
        // PGRST204: column named in the payload does not exist remotely.
        // 42P01 / 42703: table / column does not exist. All three mean a
        // migration in supabase/migrations/ has not been applied — see the
        // header of 0013, 0015 and 0016, which document this exact loop.
        case 'PGRST204':
        case 'PGRST205':
        case '42P01':
        case '42703':
          return SyncBackendException(
            SyncErrorKind.schema,
            message,
            code: code,
          );
        case '23503':
          return SyncBackendException(
            SyncErrorKind.foreignKey,
            message,
            code: code,
          );
        case '23505':
          return SyncBackendException(
            SyncErrorKind.conflict,
            message,
            code: code,
          );
      }
      // Some deployments surface an expired token as a plain 401 body with
      // no code at all, so fall back to the message.
      final lower = message.toLowerCase();
      if (lower.contains('jwt') ||
          lower.contains('token is expired') ||
          lower.contains('not authenticated')) {
        return SyncBackendException(SyncErrorKind.auth, message, code: code);
      }
      return SyncBackendException(SyncErrorKind.unknown, message, code: code);
    }

    if (e is AuthException) {
      return SyncBackendException(SyncErrorKind.auth, e.message);
    }

    if (e is SocketException ||
        e is TimeoutException ||
        e is HttpException ||
        e is HandshakeException) {
      return SyncBackendException(SyncErrorKind.transient, e.toString());
    }

    return SyncBackendException(SyncErrorKind.unknown, e.toString());
  }
}
