import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/programs/presentation/programs_providers.dart';
import 'package:herculex/features/programs/presentation/rotation_pool_sheet.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/ui/ui.dart';

class RotationPoolsView extends ConsumerWidget {
  const RotationPoolsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final poolsAsync = ref.watch(rotationPoolsProvider);

    return HxScreenShell(
      title: 'Rotation Pools',
      actions: [
        IconButton(
          tooltip: 'New Pool',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => RotationPoolSheet.show(context),
        ),
      ],
      children: [
        poolsAsync.when(
          data: (pools) {
            if (pools.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.loop,
                        size: 56,
                        color: AppColors.secondary.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No rotation pools',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create one to automatically cycle max-effort lifts or exercise variants week-to-week.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < pools.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final pool = pools[i];
                      final membersAsync = ref.watch(
                        rotationMembersProvider(pool.id),
                      );
                      final memberCount =
                          membersAsync.asData?.value.length ?? 0;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pool.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      _chip(
                                        theme,
                                        '$memberCount exercise${memberCount == 1 ? '' : 's'}',
                                      ),
                                      const SizedBox(width: 8),
                                      _chip(
                                        theme,
                                        'Every ${pool.rotateEveryWeeks}w',
                                      ),
                                      if (pool.movementPattern != null) ...[
                                        const SizedBox(width: 8),
                                        _chip(theme, pool.movementPattern!),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Edit',
                              onPressed: () => RotationPoolSheet.show(
                                context,
                                existing: pool,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.redAccent,
                              ),
                              tooltip: 'Delete',
                              onPressed: () => _confirmDelete(
                                context,
                                ref,
                                pool.id,
                                pool.name,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary),
    ),
  );

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete pool?'),
        content: Text(
          'Remove "$name" and all its members? Program day exercises linked to this pool will be unlinked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(rotationsRepositoryProvider).deleteRotation(id);
    }
  }
}
