import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/buddy/application/buddy_providers.dart';
import 'package:herculex/features/buddy/domain/buddy_join_payload.dart';
import 'package:herculex/theme/colors.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Bottom sheet displaying the host's live join QR code.
/// Automatically hides the QR code once a partner has joined.
class BuddyShareSheet extends ConsumerStatefulWidget {
  const BuddyShareSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BuddyShareSheet(),
    );
  }

  @override
  ConsumerState<BuddyShareSheet> createState() => _BuddyShareSheetState();
}

class _BuddyShareSheetState extends ConsumerState<BuddyShareSheet> {
  bool _isInitializing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureHosting();
    });
  }

  Future<void> _ensureHosting() async {
    final state = ref.read(buddySessionControllerProvider);
    if (state.isSharing) return;

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(buddySessionControllerProvider.notifier)
          .hostFromActiveWorkout();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buddyState = ref.watch(buddySessionControllerProvider);

    return Container(
      decoration: BoxDecoration(
        color:
            theme.bottomSheetTheme.backgroundColor ??
            AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_rounded, color: AppColors.primary, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    'Gym Buddy Workout',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isInitializing) ...[
                const SizedBox(height: 48),
                CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 24),
                Text(
                  'Creating shared session...',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 48),
              ] else if (_errorMessage != null) ...[
                const SizedBox(height: 24),
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to host session',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.redAccent,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: _ensureHosting,
                  child: const Text('Retry'),
                ),
              ] else if (buddyState.partner != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primaryContainer,
                        child: Icon(
                          Icons.person_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              buddyState.partner!.displayName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Training together now',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await ref
                        .read(buddySessionControllerProvider.notifier)
                        .endForEveryone();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.redAccent,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('End Shared Session'),
                ),
              ] else if (buddyState.pendingJoinToken != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: BuddyJoinPayload(
                      buddyState.pendingJoinToken!,
                    ).encode(),
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Scan to join workout',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Have your gym buddy open Herculex, tap the + button, and select "Join Gym Buddy" to scan.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.7,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(buddySessionControllerProvider.notifier)
                        .leave();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel Invite'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
