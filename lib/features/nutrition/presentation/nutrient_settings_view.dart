import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../domain/nutrient_definitions.dart';
import 'nutrient_settings_provider.dart';

class NutrientSettingsView extends ConsumerWidget {
  const NutrientSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final visible = ref.watch(visibleNutrientIdsProvider);

    return HxScreenShell(
      title: 'Nutrients Shown',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HxSpace.x2),
          child: Text(
            'Choose which nutrients appear in the daily diary. A missing source value stays unavailable; it is never shown as a measured zero.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        for (final definition in trackedNutrients)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: hx.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hx.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: SwitchListTile.adaptive(
              title: Text(
                definition.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Unit: ${definition.unit}'),
              value: visible.contains(definition.id),
              onChanged: (enabled) => ref
                  .read(visibleNutrientIdsProvider.notifier)
                  .toggle(definition.id, enabled),
            ),
          ),
      ],
    );
  }
}
