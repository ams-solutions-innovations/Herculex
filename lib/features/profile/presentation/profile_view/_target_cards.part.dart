part of '../profile_view.dart';

class _ProfileActiveTargetSquircleCard extends ConsumerWidget {
  const _ProfileActiveTargetSquircleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final activePlan = ref.watch(activeDietPlanProvider);
    final profile = ref.watch(profileProvider).asData?.value;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targets =
        ref.watch(effectiveTargetsProvider(today)).asData?.value ??
        ref.watch(baselineTargetsProvider);

    final phaseColor = switch (activePlan.phase) {
      DietPhase.cut => AppColors.macroKcal,
      DietPhase.bulk => const Color(0xFF30D158),
      DietPhase.maingain => const Color(0xFFBF5AF2),
      DietPhase.maintain => const Color(0xFF64D2FF),
    };

    final phaseIcon = switch (activePlan.phase) {
      DietPhase.cut => Icons.trending_down_rounded,
      DietPhase.bulk => Icons.trending_up_rounded,
      DietPhase.maingain => Icons.auto_awesome_rounded,
      DietPhase.maintain => Icons.balance_rounded,
    };

    final kcal = targets?.kcal ?? 0;
    final protein = targets?.proteinG ?? 0;
    final carbs = targets?.carbsG ?? 0;
    final fat = targets?.fatG ?? 0;
    final bwKg = profile?.weightKg;

    final deltaText = activePlan.kcalDelta == 0
        ? 'TDEE Maintenance'
        : '${activePlan.kcalDelta > 0 ? '+' : ''}${activePlan.kcalDelta} kcal / day (${activePlan.phase.label})';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            phaseColor.withValues(alpha: hx.isDark ? 0.20 : 0.14),
            hx.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: phaseColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Haptics.selection();
            context.push(AppRoutes.nutritionTargets);
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: phaseColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(phaseIcon, color: phaseColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Active Goal & Calories',
                                style: TextStyle(
                                  color: hx.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: hx.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activePlan.phase.label,
                            style: TextStyle(
                              color: hx.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$kcal kcal',
                          style: TextStyle(
                            color: hx.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Target daily intake',
                          style: TextStyle(
                            color: hx.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: phaseColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: phaseColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        deltaText,
                        style: TextStyle(
                          color: phaseColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (kcal > 0) ...[
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: hx.outlineVariant.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileMacroSquircleBadge(
                          label: 'Protein',
                          value: '${protein}g',
                          subtext: bwKg != null
                              ? '${(protein / bwKg).toStringAsFixed(1)} g/kg'
                              : '${((protein * 4 / kcal) * 100).round()}%',
                          color: AppColors.macroProtein,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ProfileMacroSquircleBadge(
                          label: 'Carbs',
                          value: '${carbs}g',
                          subtext: '${((carbs * 4 / kcal) * 100).round()}%',
                          color: AppColors.macroCarbs,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ProfileMacroSquircleBadge(
                          label: 'Fat',
                          value: '${fat}g',
                          subtext: '${((fat * 9 / kcal) * 100).round()}%',
                          color: AppColors.macroFat,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Tap to change phase or pace',
                      style: TextStyle(
                        color: phaseColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 14, color: phaseColor),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMacroSquircleBadge extends StatelessWidget {
  final String label;
  final String value;
  final String subtext;
  final Color color;

  const _ProfileMacroSquircleBadge({
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtext,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DreamPhysiqueCard extends StatelessWidget {
  const _DreamPhysiqueCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.hx.primary.withValues(alpha: 0.12),
            context.hx.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hx.primary.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            context.push(AppRoutes.dreamPhysique);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.hx.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 22,
                    color: context.hx.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Dream Physique AI',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.hx.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Comparison with target physique, estimated months, muscle & BF%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hx.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.hx.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centred identity block: picture above the name (§5). Tapping the picture
/// is what opens the editor — there's no separate name field on the page.
