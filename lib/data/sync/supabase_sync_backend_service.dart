import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_backend_service.dart';

/// Real [SyncBackendService], wrapping the same `Supabase.instance.client`
/// singleton `SupabaseAuthService` already uses. `updated_at` is never sent
/// on [upsert] — it's server-trigger-set (`0004_sync_triggers.sql`) and must
/// stay the authoritative LWW clock, not a client-supplied value.
class SupabaseSyncBackendService implements SyncBackendService {
  SupabaseSyncBackendService(this._client);

  final SupabaseClient _client;
  final Map<String, RealtimeChannel> _channels = {};

  @override
  bool get isConfigured => true;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) async {
    final payload = Map<String, dynamic>.from(row)..remove('updated_at');
    await _client.from(table).upsert(payload);
  }

  @override
  Future<void> delete(String table, String id) async {
    // Hard-delete fallback path only (see sync_triggers.dart's
    // trg_outbox_del_* comment) — routine soft-deletes go through upsert
    // with deleted_at set, handled by the caller before this is reached.
    await _client.from(table).delete().eq('id', id);
  }

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    required String userId,
    required DateTime since,
  }) async {
    final rows = await _client
        .from(table)
        .select()
        .eq('user_id', userId)
        .gt('updated_at', since.toUtc().toIso8601String());
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> pullTombstones({
    required String userId,
    required DateTime since,
    bool inclusive = false,
    int limit = tombstonePageSize,
  }) async {
    final iso = since.toUtc().toIso8601String();
    final scoped = _client
        .from('sync_tombstones')
        .select('entity_type, entity_id, deleted_at')
        .eq('user_id', userId);
    final rows =
        await (inclusive
                ? scoped.gte('deleted_at', iso)
                : scoped.gt('deleted_at', iso))
            // Ordered so paging is deterministic across a group of tombstones
            // written by one cascading delete, which all share `now()`.
            .order('deleted_at', ascending: true)
            .order('entity_type', ascending: true)
            .order('entity_id', ascending: true)
            .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<Set<String>> pullExistingIds(
    String table, {
    required String userId,
  }) async {
    final rows = await _client.from(table).select('id').eq('user_id', userId);
    return (rows as List)
        .map((r) => (r as Map)['id'] as String)
        .toSet();
  }

  @override
  Stream<String> realtimeHints(
    List<String> tables, {
    required String userId,
  }) {
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
}
