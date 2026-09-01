import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:herculex/theme/colors.dart';

/// Gym selection at workout start (§10). Returns the chosen gym id, null for
/// "no gym", or never shows when the user has no gym profiles. New gyms can
/// be created inline.
class GymPickerSheet extends ConsumerWidget {
  const GymPickerSheet({super.key});

  /// Resolves the gym for a new session: no gyms ⇒ null without prompting;
  /// one gym ⇒ that gym without prompting; otherwise show the picker
  /// (pre-highlighting the default gym).
  static Future<({int? gymId, bool cancelled})> resolve(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final gyms = await ref.read(gymsRepositoryProvider).watchGyms().first;
    if (gyms.isEmpty) return (gymId: null, cancelled: false);
    if (gyms.length == 1) return (gymId: gyms.first.id, cancelled: false);
    if (!context.mounted) return (gymId: null, cancelled: true);
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const GymPickerSheet(),
    );
    return (gymId: picked, cancelled: picked == null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gyms = ref.watch(gymsProvider);

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Where are you training?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New'),
                    onPressed: () => _addGym(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              gyms.maybeWhen(
                data: (list) => Column(
                  children: [
                    for (final g in list)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: g.isDefault
                              ? AppColors.primaryContainer.withValues(
                                  alpha: 0.3,
                                )
                              : AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(14),
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
                              fontWeight: g.isDefault
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: g.isDefault ? const Text('Default') : null,
                          onTap: () => Navigator.of(context).pop(g.id),
                        ),
                      ),
                  ],
                ),
                orElse: () => const Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _addGym(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New gym'),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(gymsRepositoryProvider).createGym(name.trim());
    }
  }
}
