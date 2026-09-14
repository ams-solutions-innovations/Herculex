import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/gyms/data/gyms_repository.dart';
import 'package:herculex/features/gyms/domain/gym_equipment_catalog.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';

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
                          subtitle: Text(
                            [
                              if (g.isDefault) 'Default',
                              g.allEquipment
                                  ? 'All equipment'
                                  : 'Custom equipment',
                            ].join(' · '),
                          ),
                          onTap: () => _showEquipment(context, repo, g),
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

  static Future<void> _showEquipment(
    BuildContext context,
    GymsRepository repo,
    GymData gym,
  ) {
    var allEquipment = gym.allEquipment;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: .9,
          child: SafeArea(
            child: StreamBuilder<List<GymEquipmentData>>(
              stream: repo.watchEquipment(gym.id),
              builder: (context, snapshot) {
                final selected = {
                  for (final row in snapshot.data ?? const <GymEquipmentData>[])
                    if (row.available) row.equipmentKey,
                };
                final groups = <String, List<GymEquipmentOption>>{};
                for (final option in GymEquipmentCatalog.options) {
                  groups.putIfAbsent(option.group, () => []).add(option);
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${gym.name} equipment',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Unavailable equipment is hidden from Smart selection and exercise pickers.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.secondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile.adaptive(
                      title: const Text('All equipment available'),
                      subtitle: const Text(
                        'Disable to choose what this gym has',
                      ),
                      value: allEquipment,
                      onChanged: (value) async {
                        setSheetState(() => allEquipment = value);
                        await repo.setAllEquipment(gym.id, value);
                      },
                    ),
                    if (!allEquipment)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final preset
                                  in GymEquipmentCatalog.quickPresets.entries)
                                ActionChip(
                                  label: Text('+ ${preset.key}'),
                                  onPressed: () => repo.addEquipmentPreset(
                                    gym.id,
                                    preset.value,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          for (final group in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 16,
                                bottom: 6,
                              ),
                              child: Text(
                                group.key.toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: AppColors.secondary,
                                      letterSpacing: 1,
                                    ),
                              ),
                            ),
                            for (final option in group.value)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(option.label),
                                value:
                                    allEquipment ||
                                    selected.contains(option.key),
                                onChanged: allEquipment
                                    ? null
                                    : (value) => repo.setEquipmentAvailable(
                                        gym.id,
                                        option.key,
                                        value ?? false,
                                      ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
