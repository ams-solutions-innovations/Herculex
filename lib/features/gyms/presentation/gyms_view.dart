import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/ui/ui.dart';

/// Gym profile management (§10). Sessions tag their gym; deleting a gym keeps
/// its sessions (FK set-null) so history is never lost.
class GymsView extends ConsumerWidget {
  const GymsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gyms = ref.watch(gymsProvider);
    final repo = ref.watch(gymsRepositoryProvider);

    return HxScreenShell(
      title: 'My Gyms',
      pinnedBottom: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () async {
            final name = await _prompt(context, null);
            if (name != null) await repo.createGym(name);
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Gym'),
        ),
      ),
      children: [
        gyms.when(
          data: (list) => list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No gyms yet. Add one to compare machine performance per location.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final g in list)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.location_on_outlined,
                            color: g.isDefault
                                ? AppColors.primary
                                : AppColors.secondary,
                          ),
                          title: Text(
                            g.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: g.isDefault ? const Text('Default') : null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              switch (action) {
                                case 'default':
                                  await repo.setDefaultGym(g.id);
                                case 'rename':
                                  final name = await _prompt(context, g.name);
                                  if (name != null) {
                                    await repo.renameGym(g.id, name);
                                  }
                                case 'delete':
                                  await repo.deleteGym(g.id);
                              }
                            },
                            itemBuilder: (_) => [
                              if (!g.isDefault)
                                const PopupMenuItem(
                                  value: 'default',
                                  child: Text('Make default'),
                                ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  static Future<String?> _prompt(BuildContext context, String? initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(initial == null ? 'New gym' : 'Rename gym'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Home Gym'),
          onSubmitted: (v) => Navigator.pop(dialogCtx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final trimmed = result?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
