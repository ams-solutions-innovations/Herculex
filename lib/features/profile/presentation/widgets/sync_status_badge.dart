import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Reports what cloud sync has actually done — never "synced" unless the
/// backend acknowledged every queued write (RB-02).
///
/// Public only so `test/widgets/sync_status_badge_test.dart` can pump it
/// directly: this switch *is* the user-facing half of RB-02's claim, and
/// reaching it through the whole of [ProfileView] would mean the assertion
/// depended on an unrelated settings list staying scrollable.
@visibleForTesting
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(syncStateProvider).valueOrNull ??
        const SyncState(phase: SyncPhase.disabled);

    final Color color = switch (state.phase) {
      SyncPhase.disabled => context.hx.onSurfaceVariant,
      SyncPhase.syncing => context.hx.primary,
      SyncPhase.pending => Colors.orangeAccent,
      SyncPhase.synced => context.hx.primary,
      SyncPhase.error => Colors.redAccent,
    };

    final String label = switch (state.phase) {
      SyncPhase.disabled => 'Cloud sync off',
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.pending => '${state.pendingCount} pending',
      SyncPhase.synced => 'Synced',
      SyncPhase.error => 'Sync error',
    };

    return Tooltip(
      message: switch (state.phase) {
        SyncPhase.disabled =>
          'This build has no cloud backend configured, or '
              'you are signed out. Data is saved on this device only.',
        SyncPhase.error =>
          state.lastError ?? 'Some changes could not be uploaded.',
        _ =>
          state.lastSyncedAt == null
              ? 'Not yet synced to the cloud.'
              : 'Last synced ${state.lastSyncedAt}',
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (state.phase) {
                SyncPhase.disabled => Icons.cloud_off_outlined,
                SyncPhase.syncing => Icons.cloud_sync_outlined,
                SyncPhase.pending => Icons.cloud_upload_outlined,
                SyncPhase.synced => Icons.cloud_done_outlined,
                SyncPhase.error => Icons.cloud_off,
              },
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Auth Sheet ───────────────────────────────────────────────────────────────
