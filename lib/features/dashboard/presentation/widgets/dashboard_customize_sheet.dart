import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../domain/dashboard_config.dart';
import '../dashboard_providers.dart';
import '../macro_card_prefs_provider.dart';

/// Edit-mode sheet (§18): toggle widget visibility, drag to reorder, and
/// manage widget stacks (Samsung One UI style).
class DashboardCustomizeSheet extends ConsumerWidget {
  const DashboardCustomizeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final config = ref.watch(dashboardConfigProvider);
    final notifier = ref.read(dashboardConfigProvider.notifier);
    final macroConfig = ref.watch(macroCardPrefsProvider);
    final macroNotifier = ref.read(macroCardPrefsProvider.notifier);
    final macrosVisible = config.widgets.any(
      (w) => w.types.contains(DashboardWidgetType.macros) && w.visible,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor ??
              hx.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: hx.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Customize Dashboard',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Drag to reorder · toggle to show/hide · manage stacks',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverReorderableList(
                      itemCount: config.widgets.length,
                      onReorder: (oldIdx, newIdx) {
                        Haptics.selection();
                        notifier.reorder(oldIdx, newIdx);
                      },
                      itemBuilder: (context, index) {
                        final slot = config.widgets[index];
                        return Padding(
                          key: ValueKey(slot.id),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: slot.isStack
                              ? _StackSlotCard(
                                  slotIndex: index,
                                  slot: slot,
                                  allSlots: config.widgets,
                                  notifier: notifier,
                                )
                              : _SingleSlotCard(
                                  slotIndex: index,
                                  slot: slot,
                                  allSlots: config.widgets,
                                  notifier: notifier,
                                ),
                        );
                      },
                    ),
                  ),
                  if (macrosVisible) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: hx.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.pie_chart_outline,
                                    size: 16,
                                    color: hx.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'MACRO TILES',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Which stats show in Nutrition Overview, and in what order.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.secondary),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverReorderableList(
                        itemCount: macroConfig.entries.length,
                        onReorder: (oldIdx, newIdx) {
                          Haptics.selection();
                          macroNotifier.reorder(oldIdx, newIdx);
                        },
                        itemBuilder: (context, index) {
                          final e = macroConfig.entries[index];
                          return Padding(
                            key: ValueKey(e.macro.id),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              decoration: BoxDecoration(
                                color: hx.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: hx.outlineVariant.withValues(alpha: 0.25),
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle),
                                ),
                                title: Text(
                                  e.macro.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: Switch(
                                  value: e.visible,
                                  onChanged: (v) {
                                    Haptics.selection();
                                    macroNotifier.toggle(e.macro, v);
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 32),
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

/// Standalone single widget slot card with squircle styling, icon badge,
/// stack creation menu, and visibility toggle.
class _SingleSlotCard extends StatelessWidget {
  const _SingleSlotCard({
    required this.slotIndex,
    required this.slot,
    required this.allSlots,
    required this.notifier,
  });

  final int slotIndex;
  final DashboardWidgetConfig slot;
  final List<DashboardWidgetConfig> allSlots;
  final DashboardConfigNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final type = slot.type;

    // Compatible candidate widgets for stacking
    final stackCandidates = <DashboardWidgetType>[];
    for (final s in allSlots) {
      for (final t in s.types) {
        if (t != type && t.kind == type.kind) {
          stackCandidates.add(t);
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hx.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: slotIndex,
              child: Icon(Icons.drag_handle, color: AppColors.secondary),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: hx.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(type.icon, size: 18, color: hx.primary),
            ),
          ],
        ),
        title: Text(
          type.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stackCandidates.isNotEmpty)
              PopupMenuButton<DashboardWidgetType>(
                icon: Icon(
                  Icons.layers_outlined,
                  size: 20,
                  color: AppColors.secondary,
                ),
                tooltip: 'Stack with...',
                onSelected: (added) {
                  Haptics.selection();
                  notifier.stackWidgets(type, added);
                },
                itemBuilder: (context) => [
                  for (final candidate in stackCandidates)
                    PopupMenuItem(
                      value: candidate,
                      child: Row(
                        children: [
                          Icon(candidate.icon, size: 18, color: hx.primary),
                          const SizedBox(width: 8),
                          Text('Stack with ${candidate.label}'),
                        ],
                      ),
                    ),
                ],
              ),
            Switch(
              value: slot.visible,
              onChanged: (v) {
                Haptics.selection();
                notifier.toggleSlot(slotIndex, v);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Stacked slot card with grouped squircle container, stack header, inner
/// widgets list, unstack actions, and add-to-stack menu.
class _StackSlotCard extends StatelessWidget {
  const _StackSlotCard({
    required this.slotIndex,
    required this.slot,
    required this.allSlots,
    required this.notifier,
  });

  final int slotIndex;
  final DashboardWidgetConfig slot;
  final List<DashboardWidgetConfig> allSlots;
  final DashboardConfigNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    // Compatible candidate widgets that can be added into this stack
    final stackKind = slot.types.first.kind;
    final stackCandidates = <DashboardWidgetType>[];
    for (final s in allSlots) {
      for (final t in s.types) {
        if (!slot.types.contains(t) && t.kind == stackKind) {
          stackCandidates.add(t);
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hx.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stack Header ──
          Row(
            children: [
              ReorderableDragStartListener(
                index: slotIndex,
                child: Icon(Icons.drag_handle, color: AppColors.secondary),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hx.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_outlined, size: 15, color: hx.primary),
                    const SizedBox(width: 4),
                    Text(
                      'STACK (${slot.types.length})',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: hx.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (stackCandidates.isNotEmpty)
                PopupMenuButton<DashboardWidgetType>(
                  icon: Icon(
                    Icons.add_circle_outline,
                    size: 20,
                    color: hx.primary,
                  ),
                  tooltip: 'Add widget to stack',
                  onSelected: (added) {
                    Haptics.selection();
                    notifier.stackWidgets(slot.types.first, added);
                  },
                  itemBuilder: (context) => [
                    for (final candidate in stackCandidates)
                      PopupMenuItem(
                        value: candidate,
                        child: Row(
                          children: [
                            Icon(candidate.icon, size: 18, color: hx.primary),
                            const SizedBox(width: 8),
                            Text('Add ${candidate.label}'),
                          ],
                        ),
                      ),
                  ],
                ),
              Switch(
                value: slot.visible,
                onChanged: (v) {
                  Haptics.selection();
                  notifier.toggleSlot(slotIndex, v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Stack Inner Items ──
          for (final (_, type) in slot.types.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: hx.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hx.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: hx.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(type.icon, size: 16, color: hx.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        type.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.call_split_outlined,
                        size: 18,
                        color: AppColors.secondary,
                      ),
                      tooltip: 'Unstack widget',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Haptics.selection();
                        notifier.unstackWidget(type);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
