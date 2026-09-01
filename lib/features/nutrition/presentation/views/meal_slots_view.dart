import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/meal_slots_provider.dart';
import 'package:herculex/features/nutrition/application/nutrient_settings_provider.dart';
import 'package:herculex/features/nutrition/domain/meal_slots.dart';

class MealSlotsView extends ConsumerWidget {
  const MealSlotsView({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, MealSlot slot) async {
    final label = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RenameMealSheet(initialLabel: slot.label),
    );
    if (label != null && label.isNotEmpty) {
      await ref.read(mealSlotsProvider.notifier).rename(slot.key, label);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final currentSlots = ref.read(mealSlotsProvider);
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddMealSheet(currentSlots: currentSlots),
    );
    if (result is MealSlot) {
      await ref.read(mealSlotsProvider.notifier).addBuiltIn(result);
    } else if (result is String && result.isNotEmpty) {
      await ref.read(mealSlotsProvider.notifier).add(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final slots = ref.watch(mealSlotsProvider);
    final canDelete = slots.length > 1;

    return HxScreenShell(
      title: 'Meal Slots',
      pinnedBottom: SizedBox(
        width: double.infinity,
        child: PremiumButton(
          text: 'ADD MEAL',
          isPrimary: true,
          icon: Icons.add_rounded,
          onTap: () => _add(context, ref),
        ),
      ),
      children: [
        Container(
          decoration: BoxDecoration(
            color: hx.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: SwitchListTile(
            value: ref.watch(logTimestampEnabledProvider),
            onChanged: (v) =>
                ref.read(logTimestampEnabledProvider.notifier).set(v),
            secondary: Icon(Icons.schedule_rounded, color: hx.primary),
            title: const Text('Ask for time when logging'),
            subtitle: const Text(
              'Adds an optional time-of-day field to the food entry form.',
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slots.length,
          onReorderItem: (oldIndex, newIndex) =>
              ref.read(mealSlotsProvider.notifier).reorder(oldIndex, newIndex),
          itemBuilder: (context, index) {
            final slot = slots[index];
            return Container(
              key: ValueKey(slot.key),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: hx.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hx.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: ListTile(
                leading: Icon(slot.icon, color: hx.primary),
                title: Text(
                  slot.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(slot.isBuiltIn ? 'Default slot' : 'Custom slot'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _edit(context, ref, slot),
                    ),
                    IconButton(
                      tooltip: canDelete
                          ? 'Delete'
                          : 'At least one slot required',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: canDelete
                            ? null
                            : hx.onSurface.withValues(alpha: 0.38),
                      ),
                      onPressed: canDelete
                          ? () => ref
                                .read(mealSlotsProvider.notifier)
                                .remove(slot.key)
                          : null,
                    ),
                    const Icon(Icons.drag_handle_rounded),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AddMealSheet extends StatefulWidget {
  final List<MealSlot> currentSlots;

  const _AddMealSheet({required this.currentSlots});

  @override
  State<_AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends State<_AddMealSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitCustom() {
    FocusManager.instance.primaryFocus?.unfocus();
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      Navigator.of(context).pop(value);
    }
  }

  void _selectClassic(MealSlot slot) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(slot);
  }

  @override
  Widget build(BuildContext context) {
    final existingKeys = widget.currentSlots.map((s) => s.key).toSet();
    final availableDefaults = MealSlot.defaults;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add meal slot',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Classic slots',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final slot in availableDefaults) ...[
              Builder(
                builder: (ctx) {
                  final isAdded = existingKeys.contains(slot.key);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      slot.icon,
                      color: isAdded
                          ? AppColors.onSurface.withValues(alpha: 0.38)
                          : AppColors.primary,
                    ),
                    title: Text(
                      slot.label,
                      style: TextStyle(
                        color: isAdded
                            ? AppColors.onSurface.withValues(alpha: 0.38)
                            : null,
                      ),
                    ),
                    trailing: isAdded
                        ? const Icon(Icons.check, size: 20)
                        : FilledButton.tonal(
                            onPressed: () => _selectClassic(slot),
                            child: const Text('Add'),
                          ),
                    onTap: isAdded ? null : () => _selectClassic(slot),
                  );
                },
              ),
            ],
            const Divider(height: 24),
            Text(
              'Custom slot',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Custom meal name',
                hintText: 'e.g. Pre-workout',
              ),
              onSubmitted: (_) => _submitCustom(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitCustom,
              child: const Text('Add custom meal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameMealSheet extends StatefulWidget {
  final String initialLabel;

  const _RenameMealSheet({required this.initialLabel});

  @override
  State<_RenameMealSheet> createState() => _RenameMealSheetState();
}

class _RenameMealSheetState extends State<_RenameMealSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLabel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Rename meal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Meal name'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}
