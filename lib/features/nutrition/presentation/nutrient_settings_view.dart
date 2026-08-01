import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../domain/nutrient_definitions.dart';
import 'nutrient_settings_provider.dart';

class NutrientSettingsView extends ConsumerWidget {
  const NutrientSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleNutrientIdsProvider);
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Nutrients shown'),
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Choose which nutrients appear in the daily diary. A missing source value stays unavailable; it is never shown as a measured zero.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (final definition in trackedNutrients)
            Card(
              color: AppColors.surfaceContainer,
              child: SwitchListTile.adaptive(
                title: Text(definition.label),
                subtitle: Text('Unit: ${definition.unit}'),
                value: visible.contains(definition.id),
                onChanged: (enabled) => ref
                    .read(visibleNutrientIdsProvider.notifier)
                    .toggle(definition.id, enabled),
              ),
            ),
        ],
      ),
    );
  }
}
