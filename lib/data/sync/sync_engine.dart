import 'dart:async';
import 'package:flutter/foundation.dart';

import '../local/database.dart';

/// SyncEngine - Persistent hybrid local-first sync coordinator.
/// Manages local outbox state for pending cloud synchronization.
class SyncEngine {
  final AppDatabase _db;
  Timer? _syncTimer;
  bool _isSyncing = false;

  final _syncStatusController = StreamController<SyncStatus>.broadcast();

  SyncEngine(this._db) {
    // Periodic check on persistent outbox status every 15 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) => triggerSync());
    _syncStatusController.add(SyncStatus.idle);
  }

  Stream<SyncStatus> get statusStream => _syncStatusController.stream;

  /// Manually queue a synchronization operation into the persistent Drift outbox.
  Future<void> queueSyncOp({
    required String entityType,
    required String entityId,
    required String operation,
  }) async {
    await _db.into(_db.pendingSyncOps).insert(
          PendingSyncOpsCompanion.insert(
            entityType: entityType,
            entityId: entityId,
            operation: operation,
          ),
        );

    // Proactively update sync status
    await triggerSync();
  }

  /// Check persistent sync outbox status and update the status stream.
  Future<void> triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final ops = await _db.select(_db.pendingSyncOps).get();
      if (ops.isEmpty) {
        _syncStatusController.add(SyncStatus.savedLocally);
      } else {
        _syncStatusController.add(SyncStatus.pendingCloud);
      }
    } catch (e) {
      debugPrint("SyncEngine Error: $e");
      _syncStatusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncStatusController.close();
  }
}

enum SyncStatus {
  idle,
  savedLocally,
  pendingCloud,
  error,
}

extension SyncStatusExtension on SyncStatus {
  String get label => switch (this) {
        SyncStatus.idle => "Data saved locally",
        SyncStatus.savedLocally => "Data saved locally",
        SyncStatus.pendingCloud => "Pending cloud sync",
        SyncStatus.error => "Local storage error",
      };
}

