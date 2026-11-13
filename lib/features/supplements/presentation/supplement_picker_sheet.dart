import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_presets.dart';
import 'package:herculex/features/supplements/presentation/supplement_edit_sheet.dart';

const _accent = Color(0xFF9B59B6);

/// The one way to add a supplement: pick from the list (creatine, omega-3,
/// multivitamin, ZMA, …) or make a custom one. Presets already on the user's
/// list are ticked and open for editing instead of being added twice.
class SupplementPickerSheet extends ConsumerWidget {
  const SupplementPickerSheet({super.key});

  /// Shows the picker, then opens the edit sheet for whatever was chosen.
  static Future<void> show(BuildContext context) async {
    final choice = await showModalBottomSheet<_PickerChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => const SupplementPickerSheet(),
    );
    if (choice == null || !context.mounted) return;
    await SupplementEditSheet.show(
      context,
      existing: choice.supplement,
      isNewDraft: choice.isNew,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final added = {
      for (final s in ref.watch(supplementsProvider).valueOrNull ?? const [])
        if (s.presetKey != null) s.presetKey!: s,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color:
            theme.bottomSheetTheme.backgroundColor ??
            theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Add supplement',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick one — you can change the dose afterwards.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final preset in supplementPresets)
                    _PresetTile(
                      preset: preset,
                      existing: added[preset.key],
                      onTap: () {
                        Haptics.selection();
                        final existing = added[preset.key];
                        Navigator.of(context).pop(
                          existing != null
                              ? _PickerChoice(existing, isNew: false)
                              : _PickerChoice(
                                  preset.toSupplement(),
                                  isNew: true,
                                ),
                        );
                      },
                    ),
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x269B59B6),
                      child: Icon(Icons.add, color: _accent),
                    ),
                    title: const Text('Custom supplement'),
                    subtitle: const Text('Name and dose of your own'),
                    onTap: () {
                      Haptics.selection();
                      Navigator.of(context).pop(const _PickerChoice(null));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerChoice {
  /// Null for a blank custom supplement.
  final Supplement? supplement;
  final bool isNew;

  const _PickerChoice(this.supplement, {this.isNew = true});
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.existing,
    required this.onTap,
  });

  final SupplementPreset preset;
  final Supplement? existing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdded = existing != null;
    final dose =
        '${preset.doseAmount.toStringAsFixed(preset.doseAmount.truncateToDouble() == preset.doseAmount ? 0 : 1)} ${preset.doseUnit}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: _accent.withValues(alpha: isAdded ? 0.28 : 0.14),
        child: Icon(
          isAdded ? Icons.check : _iconFor(preset.key),
          color: _accent,
          size: 20,
        ),
      ),
      title: Text(
        preset.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        isAdded ? 'Already added · tap to edit' : preset.blurb,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
      ),
      trailing: Text(
        dose,
        style: theme.textTheme.labelMedium?.copyWith(
          color: AppColors.secondary,
        ),
      ),
      onTap: onTap,
    );
  }
}

IconData _iconFor(String key) => switch (key) {
  'creatine' => Icons.bolt_rounded,
  'omega3' => Icons.water_drop_outlined,
  'multivitamin' => Icons.grid_view_rounded,
  'zma' => Icons.bedtime_outlined,
  'vitamin_d' => Icons.wb_sunny_outlined,
  'magnesium' => Icons.spa_outlined,
  'caffeine' => Icons.coffee_outlined,
  'melatonin' => Icons.nightlight_outlined,
  _ => Icons.medication_outlined,
};
