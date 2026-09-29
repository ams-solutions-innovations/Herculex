part of '../block_builder_view.dart';

mixin _StepPoolsMixin on _BuilderStateBase {
  Widget _stepExercisePools(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          'Exercise pools',
          'Equipment and movement affinities.',
          centered: true,
        ),
        _builderInputCard(
          theme,
          icon: Icons.favorite_outline_rounded,
          title: 'Exercise preferences',
          subtitle: 'Movement affinities (Never, Like, Core).',
          action: 'Review',
          onTap: () => context.push(AppRoutes.exercises),
        ),
        _builderInputCard(
          theme,
          icon: Icons.fitness_center_rounded,
          title: 'Available equipment',
          subtitle: 'Gym profile and equipment access.',
          action: 'Configure',
          onTap: () => context.push(AppRoutes.gyms),
        ),
      ],
    );
  }

  @override
  Widget _builderInputCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? actionWidget,
    String? action,
    VoidCallback? onTap,
    VoidCallback? onCardTap,
    bool selected = false,
    String? status,
  }) {
    return GestureDetector(
      onTap: () {
        if (onCardTap != null) {
          Haptics.selection();
          onCardTap();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: .08)
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: .35),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: .18)
                          : AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary.withValues(alpha: .5)
                            : AppColors.outlineVariant.withValues(alpha: .3),
                      ),
                    ),
                    child: Text(
                      status,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                height: 1.3,
              ),
            ),
            if (actionWidget != null || action != null) ...[
              const SizedBox(height: 12),
              actionWidget ??
                  OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(action!),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  String get _manualPlanSummary {
    if (_manualMuscleWeights.isEmpty) {
      return 'Choose the muscles you want to prioritise.';
    }
    final total = _manualMuscleWeights.values.fold(0, (a, b) => a + b);
    return _manualMuscleWeights.entries
        .map((entry) {
          final pct = total == 0 ? 0 : (entry.value / total * 100).round();
          final cap = _manualSetCaps[entry.key] ?? 10;
          return '${_BuilderStateBase._manualMuscleLabels[entry.key]} $pct% · ≤$cap sets';
        })
        .join('  •  ');
  }

  @override
  Future<void> _showManualMusclePlan() async {
    final result =
        await showModalBottomSheet<
          ({Map<String, int> weights, Map<String, int> caps})
        >(
          context: context,
          isScrollControlled: true,
          builder: (context) => _ManualMusclePlanSheet(
            labels: _BuilderStateBase._manualMuscleLabels,
            initialWeights: _manualMuscleWeights,
            initialCaps: _manualSetCaps,
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      _useManualMusclePlan = true;
      _manualMuscleWeights
        ..clear()
        ..addAll(result.weights);
      _manualSetCaps
        ..clear()
        ..addAll(result.caps);
    });
  }

  @override
  Widget _slotCard(
    ThemeData theme,
    ({int slotIndex, String label}) slot,
    List<WorkoutTemplateData> templates,
  ) {
    final templateId = _templatesBySlot[slot.slotIndex];
    final template = templateId == null
        ? null
        : templates.where((t) => t.id == templateId).firstOrNull;
    final repeats = _plan.trainingDays
        .where((d) => d.slotIndex == slot.slotIndex)
        .length;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final picked = await TemplatePickerSheet.show(context);
        if (picked == null) return;
        setState(() => _templatesBySlot[slot.slotIndex] = picked.id);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: template != null
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: template != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template?.name ??
                        'Tap to link a template'
                            '${repeats > 1 ? ' · used $repeats× per week' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: template != null
                          ? AppColors.primary
                          : AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (template != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: AppColors.secondary),
                onPressed: () =>
                    setState(() => _templatesBySlot.remove(slot.slotIndex)),
              )
            else
              Icon(Icons.add_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ── Step 5: content & methods ──────────────────────────────────────────────
}
