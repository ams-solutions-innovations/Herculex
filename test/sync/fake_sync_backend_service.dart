import 'dart:async';

import 'package:herculex/data/sync/sync_backend_service.dart';

/// In-memory [SyncBackendService] for tests — mirrors
/// `test/auth/auth_repository_test.dart`'s `FakeAuthProviderService`: fakes
/// only the network-facing seam, so `SyncService` runs for real against it.
class FakeSyncBackendService implements SyncBackendService {
  final List<(String table, Map<String, dynamic> row)> upsertCalls = [];
  final List<(String table, String id)> deleteCalls = [];

  /// table -> remote row (keyed by 'id') available for pull.
  final Map<String, List<Map<String, dynamic>>> remoteRows = {};

  /// Stands in for `public.sync_tombstones`.
  final List<Map<String, dynamic>> tombstones = [];

  int upsertFailuresRemaining = 0;

  /// Set to make every [pull] throw, standing in for a server/network error.
  bool failPulls = false;

  /// How many times `SyncService.stop()` has torn this backend down.
  int disposeCount = 0;

  final _hintsController = StreamController<String>.broadcast();

  @override
  bool get isConfigured => true;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) async {
    if (upsertFailuresRemaining > 0) {
      upsertFailuresRemaining--;
      throw Exception('simulated upsert failure');
    }
    // Recorded exactly as the client sent it, so tests can assert the client
    // never supplies `updated_at` itself.
    upsertCalls.add((table, row));
    // Stored with a server-side `updated_at`, the way the real Postgres
    // `set_updated_at` trigger stamps it (`0004_sync_triggers.sql`) — without
    // this a pushed row could never be pulled back.
    final stored = Map<String, dynamic>.from(row)
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final rows = remoteRows.putIfAbsent(table, () => []);
    rows.removeWhere((r) => r['id'] == stored['id']);
    rows.add(stored);
  }

  @override
  Future<void> delete(String table, String id) async {
    deleteCalls.add((table, id));
    final existed = remoteRows[table]?.any((r) => r['id'] == id) ?? false;
    remoteRows[table]?.removeWhere((r) => r['id'] == id);
    // Mirrors the server's `t_record_tombstone_*` trigger. `existed` matters:
    // an `AFTER DELETE FOR EACH ROW` trigger does not fire when the DELETE
    // matches nothing, which is what keeps a pushed echo from writing a fresh
    // tombstone and ping-ponging.
    if (existed) seedTombstone(table, id);
  }

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    required String userId,
    required DateTime since,
  }) async {
    if (failPulls) throw Exception('simulated pull failure');
    final rows = remoteRows[table] ?? const [];
    return rows
        .where((r) => r['user_id'] == userId)
        .where((r) => DateTime.parse(r['updated_at'] as String).isAfter(since))
        .toList();
  }

  void seedRemoteRow(String table, Map<String, dynamic> row) {
    remoteRows.putIfAbsent(table, () => []).add(row);
  }

  /// Records a hard delete the way `record_sync_tombstone()` does, including
  /// its `on conflict do update set deleted_at` refresh.
  void seedTombstone(
    String entityType,
    String entityId, {
    DateTime? deletedAt,
    String userId = 'user-1',
  }) {
    tombstones.removeWhere(
      (t) => t['entity_type'] == entityType && t['entity_id'] == entityId,
    );
    tombstones.add({
      'entity_type': entityType,
      'entity_id': entityId,
      'user_id': userId,
      'deleted_at': (deletedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> pullTombstones({
    required String userId,
    required DateTime since,
    bool inclusive = false,
    int limit = tombstonePageSize,
  }) async {
    if (failPulls) throw Exception('simulated tombstone pull failure');
    final matching =
        tombstones.where((t) => t['user_id'] == userId).where((t) {
          final at = DateTime.parse(t['deleted_at'] as String);
          return inclusive
              ? at.isAfter(since) || at.isAtSameMomentAs(since)
              : at.isAfter(since);
        }).toList()..sort((a, b) {
          final byTime = (a['deleted_at'] as String).compareTo(
            b['deleted_at'] as String,
          );
          if (byTime != 0) return byTime;
          final byType = (a['entity_type'] as String).compareTo(
            b['entity_type'] as String,
          );
          return byType != 0
              ? byType
              : (a['entity_id'] as String).compareTo(b['entity_id'] as String);
        });
    return matching.take(limit).toList();
  }

  @override
  Future<Set<String>> pullExistingIds(
    String table, {
    required String userId,
  }) async {
    if (failPulls) throw Exception('simulated existence pull failure');
    return (remoteRows[table] ?? const [])
        .where((r) => r['user_id'] == userId)
        .map((r) => r['id'] as String)
        .toSet();
  }

  void emitHint(String table) => _hintsController.add(table);

  @override
  Stream<String> realtimeHints(List<String> tables, {required String userId}) =>
      _hintsController.stream;

  /// Deliberately does not close the hints controller: `SyncService.stop()`
  /// calls this on every sign-out, and an account-switch test needs the
  /// backend to survive a stop/start cycle the way the real one does (its
  /// controller is created per `realtimeHints` call).
  @override
  void dispose() {
    disposeCount++;
  }

  /// For test teardown, once no further start/stop cycles are expected.
  void close() => _hintsController.close();
}
