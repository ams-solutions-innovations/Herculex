import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/colors.dart';
import '../../domain/dashboard_config.dart';
import '../dashboard_providers.dart';
import '../macro_card_prefs_provider.dart';

/// Edit-mode sheet (§18): toggle widget visibility and drag to reorder.
/// A second, nested reorderable section lets users pick which macro tiles
/// show inside the "Nutrition Overview" widget — only shown while that
/// widget is itself visible, since configuring it otherwise has no effect.
class DashboardCustomizeSheet extends ConsumerWidget {
  const DashboardCustomizeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(dashboardConfigProvider);
    final notifier = ref.read(dashboardConfigProvider.notifier);
    final macroConfig = ref.watch(macroCardPrefsProvider);
    final macroNotifier = ref.read(macroCardPrefsProvider.notifier);
    final macrosVisible = config.widgets.any(
      (w) => w.type == DashboardWidgetType.macros && w.visible,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Customize Dashboard',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Drag to reorder · toggle to show/hide',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondary)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: notifier.reorder,
                    children: [
                      for (final w in config.widgets)
                        Padding(
                          key: ValueKey(w.type.id),
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.drag_handle),
                              title: Text(w.type.label),
                              // Use the themed Switch (white thumb on a blue
                              // track) — the previous adaptive switch forced
                              // a blue thumb, which vanished against the
                              // blue track.
                              trailing: Switch(
                                value: w.visible,
                                onChanged: (v) => notifier.toggle(w.type, v),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (macrosVisible) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text('MACRO TILES',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      'Which stats show in Nutrition Overview, and in what order.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondary),
                    ),
                    const SizedBox(height: 8),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: macroNotifier.reorder,
                      children: [
                        for (final e in macroConfig.entries)
                          Padding(
                            key: ValueKey(e.macro.id),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: const Icon(Icons.drag_handle),
                                title: Text(e.macro.label),
                                trailing: Switch(
                                  value: e.visible,
                                  onChanged: (v) =>
                                      macroNotifier.toggle(e.macro, v),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
