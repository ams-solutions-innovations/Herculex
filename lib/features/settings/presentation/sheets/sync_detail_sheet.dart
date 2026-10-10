import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Cloud sync status with manual retry / re-upload actions.
class SyncDetailSheet extends ConsumerStatefulWidget {
  const SyncDetailSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SyncDetailSheet(),
    );
  }

  @override
  ConsumerState<SyncDetailSheet> createState() => _SyncDetailSheetState();
}

class _SyncDetailSheetState extends ConsumerState<SyncDetailSheet> {
  bool _busy = false;
  String? _statusMessage;

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await ref.read(syncServiceProvider).retryAll();
      if (mounted) {
        setState(() {
          _statusMessage = 'Sync completed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Sync failed: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reuploadAll() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final count = await ref.read(syncServiceProvider).reuploadAllLocalData();
      if (mounted) {
        setState(() {
          _statusMessage = 'Re-enqueued $count items for upload';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Re-upload failed: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncState =
        ref.watch(syncStateProvider).valueOrNull ??
        const SyncState(phase: SyncPhase.disabled);
    final session = ref.watch(authSessionProvider).valueOrNull;

    final Color statusColor = switch (syncState.phase) {
      SyncPhase.disabled => context.hx.onSurfaceVariant,
      SyncPhase.syncing => context.hx.primary,
      SyncPhase.pending => Colors.orangeAccent,
      SyncPhase.synced => context.hx.primary,
      SyncPhase.error => Colors.redAccent,
    };

    final String statusLabel = switch (syncState.phase) {
      SyncPhase.disabled => 'Disabled',
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.pending => '${syncState.pendingCount} pending changes',
      SyncPhase.synced => 'Synced and up to date',
      SyncPhase.error => 'Sync error',
    };

    return HxSheet(
      scrollable: false,
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  switch (syncState.phase) {
                    SyncPhase.disabled => Icons.cloud_off_outlined,
                    SyncPhase.syncing => Icons.cloud_sync_outlined,
                    SyncPhase.pending => Icons.cloud_upload_outlined,
                    SyncPhase.synced => Icons.cloud_done_outlined,
                    SyncPhase.error => Icons.cloud_off,
                  },
                  color: statusColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud Sync',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      session?.email ?? 'Account sync status',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                if (syncState.lastSyncedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last synced: ${syncState.lastSyncedAt}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.hx.onSurfaceVariant,
                    ),
                  ),
                ],
                if (syncState.pendingCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Pending outbox items: ${syncState.pendingCount}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (syncState.quarantinedCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Quarantined items: ${syncState.quarantinedCount}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent.shade200,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (syncState.lastError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      syncState.lastError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMessage!,
              style: TextStyle(
                fontSize: 13,
                color: context.hx.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _syncNow,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(_busy ? 'Syncing…' : 'Sync Now / Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: context.hx.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reuploadAll,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Re-upload All Local Data'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
