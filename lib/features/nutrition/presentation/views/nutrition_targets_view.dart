import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/toast/hx_toast_controller.dart';
import 'package:herculex/core/notifications/toast/hx_toast_model.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/data/carb_cycle_service.dart';
import 'package:herculex/features/nutrition/domain/carb_cycling.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/presentation/widgets/tdee_estimate_badge.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/presentation/widgets/restriction_notice.dart';

/// Presentation-only chip/card styling for a [DietPhase]. Kept as a single
/// extension so the quick planner card and its chip buttons can't drift
/// apart on color or icon the way they previously did as two hand-copied
/// switch statements.
extension DietPhaseUi on DietPhase {
  Color get uiColor => switch (this) {
    DietPhase.cut => AppColors.macroKcal,
    DietPhase.bulk => const Color(0xFF30D158),
    DietPhase.maingain => const Color(0xFFBF5AF2),
    DietPhase.maintain => const Color(0xFF64D2FF),
    DietPhase.recomp => const Color(0xFFFF9F0A),
  };

  IconData get uiIcon => switch (this) {
    DietPhase.cut => Icons.trending_down_rounded,
    DietPhase.bulk => Icons.trending_up_rounded,
    DietPhase.maingain => Icons.auto_awesome_rounded,
    DietPhase.maintain => Icons.balance_rounded,
    DietPhase.recomp => Icons.change_circle_rounded,
  };
}

/// Hub for everything target-related (§5).
class NutritionTargetsView extends ConsumerWidget {
  /// Pre-selects the quick planner's phase, e.g. when arriving from the
  /// Dream Physique "Optional next nutrition phase" card so the chosen
  /// direction isn't silently dropped in favor of the active plan's phase.
  final DietPhase? initialPhase;

  const NutritionTargetsView({super.key, this.initialPhase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final targets = ref.watch(nutritionTargetsProvider).asData?.value;
    final schedule = ref.watch(activeDietScheduleProvider).asData?.value;

    return HxScreenShell(
      title: 'Cilji in prehrana',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HxSpace.x2),
          child: Text(
            'Nastavi ciljne kalorije, hitro izberi prehransko fazo in '
            'prilagodi makrohranila glede na življenjski slog in trening.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x5),

        // ── Quick Phase & Calorie Planner ──
        _QuickPhasePlannerSection(initialPhase: initialPhase),

        const SizedBox(height: HxSpace.x6),
        _SectionHeaderTitle('NAPREDNE NASTAVITVE IN RAZPOREDI'),
        const SizedBox(height: HxSpace.x3),

        _HubTile(
          icon: Icons.flag_rounded,
          title: 'Dnevni cilji',
          subtitle: targets == null || targets.isEmpty
              ? 'Uporabljeni so cilji, izračunani iz profila'
              : 'Lastni cilji: ${targets.length}',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DailyTargetsView())),
        ),
        const SizedBox(height: HxSpace.x3),
        _HubTile(
          icon: Icons.timeline_rounded,
          title: 'Aktiven razpored',
          subtitle: schedule == null
              ? 'Samodejna sprememba kalorij ni vklopljena'
              : schedule.reducePct < 0
              ? 'Masa · +${(-schedule.reducePct).toStringAsFixed(1)} % '
                    'vsakih ${schedule.intervalDays} dni'
              : 'Redukcija · −${schedule.reducePct.toStringAsFixed(1)} % '
                    'vsakih ${schedule.intervalDays} dni',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ActiveScheduleView())),
        ),
        const SizedBox(height: HxSpace.x3),
        _HubTile(
          icon: Icons.bakery_dining_rounded,
          title: 'Ciklanje ogljikovih hidratov',
          subtitle: 'Najtežji treningi dobijo največ ogljikovih hidratov',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CarbCycleView())),
        ),
      ],
    );
  }
}

class _SectionHeaderTitle extends StatelessWidget {
  final String text;
  const _SectionHeaderTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Text(
      text,
      style: TextStyle(
        color: hx.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }
}

/// Interactive quick calorie and phase planning section right on the main Targets view.
class _QuickPhasePlannerSection extends ConsumerStatefulWidget {
  final DietPhase? initialPhase;

  const _QuickPhasePlannerSection({this.initialPhase});

  @override
  ConsumerState<_QuickPhasePlannerSection> createState() =>
      _QuickPhasePlannerSectionState();
}

class _QuickPhasePlannerSectionState
    extends ConsumerState<_QuickPhasePlannerSection> {
  late DietPhase _selectedPhase;
  int _selectedPaceIndex = 1;
  bool _initialized = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final activePlan = ref.read(activeDietPlanProvider);
      _selectedPhase = widget.initialPhase ?? activePlan.phase;
      final options = DietPhaseCalculator.paceOptionsFor(_selectedPhase);
      final idx = options.indexWhere(
        (o) =>
            (o.weeklyKg - activePlan.weeklyRateKg).abs() < 0.01 ||
            o.kcalDelta == activePlan.kcalDelta,
      );
      _selectedPaceIndex = (idx >= 0 && idx < options.length)
          ? idx
          : (options.length > 1 ? 1 : 0);
      _initialized = true;
    }
  }

  /// Live-coerced, never captured, so an allowed phase returns once the
  /// profile arrives (PHYS-04).
  DietPhase get _effectivePhase =>
      ref.read(physiqueEditorEligibilityProvider).coerce(_selectedPhase);

  void _onPhaseSelected(DietPhase phase) {
    if (!ref.read(physiqueEditorEligibilityProvider).allows(phase)) return;
    if (_selectedPhase == phase) return;
    setState(() {
      _selectedPhase = phase;
      final options = DietPhaseCalculator.paceOptionsFor(phase);
      _selectedPaceIndex = (options.length > 1) ? 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final profile = ref.watch(profileProvider).asData?.value;
    final baselineKcal = ref.watch(maintenanceKcalProvider) ?? 2500;
    final bwKg = profile?.weightKg;

    final eligibility = ref.watch(physiqueEditorEligibilityProvider);
    final paceOptions = DietPhaseCalculator.paceOptionsFor(_effectivePhase);
    final currentPace =
        (_selectedPaceIndex >= 0 && _selectedPaceIndex < paceOptions.length)
        ? paceOptions[_selectedPaceIndex]
        : paceOptions.first;

    final minTargets = ref.watch(minimumTargetsProvider);
    final minProteinG = minTargets.resolvedMinProteinG(bwKg);
    final minKcal = minTargets.effectiveMinCaloriesKcal;

    // PHYS-04: eligibility clamps the delta for restricted members.
    final targets = DietPhaseCalculator.apply(
      phase: _effectivePhase,
      eligibility: eligibility,
      baselineKcal: baselineKcal,
      bodyweightKg: bwKg,
      calorieDeltaOverride: currentPace.kcalDelta,
      minProteinG: minProteinG,
      minCaloriesKcal: minKcal,
    );

    final phaseColor = _effectivePhase.uiColor;
    final phaseIcon = _effectivePhase.uiIcon;
    final phaseSubtitle = _effectivePhase.subtitle;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            phaseColor.withValues(alpha: hx.isDark ? 0.16 : 0.12),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(phaseIcon, color: phaseColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hitri načrt kalorij in faz',
                      style: TextStyle(
                        color: hx.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Izhodišče: $baselineKcal kcal (TDEE)',
                      style: TextStyle(
                        color: hx.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          RestrictionNoticeList(
            eligibility: eligibility,
            onAddAge: () => context.push(AppRoutes.profile),
          ),
          if (eligibility.isRestricted) const SizedBox(height: 12),
          // ── Phase Selector (Cut, Bulk, Maingain, Maintain) ──
          Row(
            children: [
              for (final phase in DietPhase.values) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _PhaseChipButton(
                      phase: phase,
                      selected: _effectivePhase == phase,
                      enabled: eligibility.allows(phase),
                      onTap: () => _onPhaseSelected(phase),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // ── Pace / Rate Selector ──
          Text(
            _effectivePhase == DietPhase.maintain
                ? 'TEMPO IN INTENZIVNOST'
                : 'TEDENSKI TEMPO / AGRESIVNOST',
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (int i = 0; i < paceOptions.length; i++)
                ChoiceChip(
                  label: Text(paceOptions[i].label),
                  selected: _selectedPaceIndex == i,
                  selectedColor: phaseColor.withValues(alpha: 0.25),
                  labelStyle: TextStyle(
                    color: _selectedPaceIndex == i
                        ? phaseColor
                        : hx.onSurfaceVariant,
                    fontWeight: _selectedPaceIndex == i
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: _selectedPaceIndex == i
                        ? phaseColor
                        : hx.outlineVariant.withValues(alpha: 0.4),
                  ),
                  onSelected: (_) => setState(() => _selectedPaceIndex = i),
                ),
            ],
          ),

          const SizedBox(height: 6),
          Text(
            currentPace.description,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 12,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 16),

          // ── Live Calculated Target & Macros Card ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hx.surfaceContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hx.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${targets.kcal} kcal',
                          style: TextStyle(
                            color: hx.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Ciljni dnevni vnos',
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
                        targets.deltaKcal == 0
                            ? 'TDEE vzdrževanje'
                            : '${targets.deltaKcal > 0 ? '+' : ''}${targets.deltaKcal} kcal / dan',
                        style: TextStyle(
                          color: phaseColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: hx.outlineVariant.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MacroStatBox(
                        label: 'Beljakovine',
                        value: '${targets.proteinG}g',
                        subtext: bwKg != null
                            ? '${(targets.proteinG / bwKg).toStringAsFixed(1)} g/kg'
                            : '${((targets.proteinG * 4 / targets.kcal) * 100).round()}%',
                        color: AppColors.macroProtein,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MacroStatBox(
                        label: 'Ogljikovi hidrati',
                        value: '${targets.carbsG}g',
                        subtext:
                            '${((targets.carbsG * 4 / targets.kcal) * 100).round()}%',
                        color: AppColors.macroCarbs,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MacroStatBox(
                        label: 'Maščobe',
                        value: '${targets.fatG}g',
                        subtext:
                            '${((targets.fatG * 9 / targets.kcal) * 100).round()}%',
                        color: AppColors.macroFat,
                      ),
                    ),
                  ],
                ),
                if (minTargets.enabled &&
                    (minProteinG != null || minKcal != null)) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (minProteinG != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.macroProtein.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.macroProtein.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Min. beljakovine: ${minProteinG} g',
                            style: TextStyle(
                              color: AppColors.macroProtein,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (minKcal != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.macroKcal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.macroKcal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            'Min. kalorije: $minKcal kcal',
                            style: TextStyle(
                              color: AppColors.macroKcal,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),
          Text(
            phaseSubtitle,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),

          const SizedBox(height: 16),

          // ── Minimum Targets & Floor Limits ──
          _MinimumTargetsSection(bwKg: bwKg),

          const SizedBox(height: 16),

          // ── Save / Apply Button ──
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: phaseColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                _saving
                    ? 'Shranjujem …'
                    : 'Uporabi: ${_effectivePhase.label} (${targets.kcal} kcal)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      final repo = ref.read(nutritionRepositoryProvider);
                      await repo.upsertTarget(
                        label: 'Splošno (${_effectivePhase.label})',
                        appliesTo: 'global',
                        kcal: targets.kcal,
                        proteinG: targets.proteinG,
                        carbsG: targets.carbsG,
                        fatG: targets.fatG,
                      );
                      await ref
                          .read(activeDietPlanProvider.notifier)
                          .setPlan(
                            phase: _effectivePhase,
                            weeklyRateKg: currentPace.weeklyKg,
                            kcalDelta: currentPace.kcalDelta,
                            paceLabel: currentPace.label,
                          );
                      if (!mounted) return;
                      setState(() => _saving = false);
                      ref
                          .read(hxToastControllerProvider.notifier)
                          .show(
                            HxToastItem.targetsUpdated(
                              message:
                                  '${_effectivePhase.label} • ${targets.kcal} kcal',
                            ),
                          );
                    },
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseChipButton extends StatelessWidget {
  final DietPhase phase;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PhaseChipButton({
    required this.phase,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final color = phase.uiColor;
    final sel = selected && enabled;
    final fg = sel ? color : (enabled ? hx.onSurfaceVariant : hx.tertiary);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: sel
              ? color.withValues(alpha: 0.2)
              : hx.surfaceContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? color : hx.outlineVariant.withValues(alpha: 0.3),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(phase.uiIcon, size: 18, color: fg),
            const SizedBox(height: 4),
            Text(
              phase.label,
              style: TextStyle(
                color: fg,
                fontWeight: sel ? FontWeight.bold : FontWeight.w600,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroStatBox extends StatelessWidget {
  final String label;
  final String value;
  final String subtext;
  final Color color;

  const _MacroStatBox({
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

/// One polished entry tile on the Targets & Dieting hub.
class _HubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hx.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: hx.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: hx.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: hx.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: hx.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Daily Targets screen ────────────────────────────────────────────────────

class DailyTargetsView extends ConsumerWidget {
  const DailyTargetsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final targets = ref.watch(nutritionTargetsProvider);

    return HxScreenShell(
      title: 'Dnevni cilji',
      pinnedBottom: SizedBox(
        width: double.infinity,
        child: PremiumButton(
          text: 'DODAJ / UREDI CILJ',
          isPrimary: true,
          icon: Icons.add_rounded,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TargetEditorView())),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HxSpace.x2),
          child: Text(
            'Velja najbolj specifičen cilj: datum > dan v tednu > trening/počitek > splošno.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        targets.when(
          data: (rows) => rows.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: hx.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: hx.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 40,
                        color: hx.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Še ni lastnih ciljev',
                        style: TextStyle(
                          color: hx.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Trenutno veljajo izhodiščne kalorije in makrohranila, izračunana iz tvojega profila.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: hx.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final t in rows)
                      _TargetCard(
                        target: t,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TargetEditorView(initialTarget: t),
                          ),
                        ),
                        onDelete: () async {
                          final repo = ref.read(nutritionRepositoryProvider);
                          await repo.deleteTarget(t.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Cilj »${t.label}« izbrisan'),
                                action: SnackBarAction(
                                  label: 'Razveljavi',
                                  onPressed: () {
                                    repo.upsertTarget(
                                      label: t.label,
                                      appliesTo: t.appliesTo,
                                      kcal: t.kcal,
                                      proteinG: t.proteinG,
                                      carbsG: t.carbsG,
                                      fatG: t.fatG,
                                      fiberG: t.fiberG,
                                    );
                                  },
                                ),
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Center(child: Text('Napaka: $e')),
        ),
      ],
    );
  }
}

class _TargetCard extends StatelessWidget {
  final NutritionTargetData target;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TargetCard({
    required this.target,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hx.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.flag_rounded,
                        color: hx.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        target.label,
                        style: TextStyle(
                          color: hx.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '${target.kcal} kcal',
                      style: TextStyle(
                        color: hx.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: hx.onSurfaceVariant,
                      ),
                      onPressed: onDelete,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MacroBadge(
                      label: 'P',
                      grams: target.proteinG,
                      color: AppColors.macroProtein,
                    ),
                    _MacroBadge(
                      label: 'C',
                      grams: target.carbsG,
                      color: AppColors.macroCarbs,
                    ),
                    _MacroBadge(
                      label: 'F',
                      grams: target.fatG,
                      color: AppColors.macroFat,
                    ),
                    if (target.fiberG != null && target.fiberG! > 0)
                      _MacroBadge(
                        label: 'Vlaknine',
                        grams: target.fiberG!,
                        color: hx.tertiary,
                      ),
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

class _MacroBadge extends StatelessWidget {
  final String label;
  final int grams;
  final Color color;

  const _MacroBadge({
    required this.label,
    required this.grams,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            '${grams}g',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active Schedule screen ──────────────────────────────────────────────────

class ActiveScheduleView extends ConsumerWidget {
  const ActiveScheduleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final schedule = ref.watch(activeDietScheduleProvider);

    return HxScreenShell(
      title: 'Aktiven razpored',
      pinnedBottom: Row(
        children: [
          Expanded(
            child: PremiumButton(
              text: 'ZAČNI REDUKCIJO',
              isPrimary: false,
              icon: Icons.trending_down_rounded,
              onTap: () => _showCutBulkSheet(context, ref, isBulk: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PremiumButton(
              text: 'ZAČNI MASO',
              isPrimary: true,
              icon: Icons.trending_up_rounded,
              onTap: () => _showCutBulkSheet(context, ref, isBulk: true),
            ),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HxSpace.x2),
          child: Text(
            'Razpored samodejno zvišuje ali znižuje kalorije v stalnih '
            'intervalih, da ti ni treba ponovno vnašati ciljev.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        schedule.when(
          data: (s) {
            if (s == null) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: hx.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hx.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.timeline_rounded,
                      size: 40,
                      color: hx.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ni aktivnega razporeda',
                      style: TextStyle(
                        color: hx.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Samodejno postopno prilagajanje kalorij: spodaj začni cikel redukcije ali mase.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hx.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }
            final isBulk = s.reducePct < 0;
            final color = isBulk ? const Color(0xFF30D158) : hx.primary;
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: hx.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isBulk
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          color: color,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isBulk ? 'Aktivna masa' : 'Aktivna redukcija',
                              style: TextStyle(
                                color: hx.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isBulk
                                  ? '+${(-s.reducePct).toStringAsFixed(1)} % vsakih ${s.intervalDays} dni'
                                  : '−${s.reducePct.toStringAsFixed(1)} % vsakih ${s.intervalDays} dni',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: hx.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Začeto ${s.startDateIso}',
                        style: TextStyle(
                          color: hx.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('Ustavi'),
                        style: TextButton.styleFrom(foregroundColor: hx.danger),
                        onPressed: () => ref
                            .read(nutritionRepositoryProvider)
                            .stopDietSchedules(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Center(child: Text('Napaka: $e')),
        ),
      ],
    );
  }

  Future<void> _showCutBulkSheet(
    BuildContext context,
    WidgetRef ref, {
    required bool isBulk,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CutBulkSheet(ref: ref, isBulk: isBulk),
    );
  }
}

// ── Carb Cycle screen ───────────────────────────────────────────────────────

class CarbCycleView extends ConsumerWidget {
  const CarbCycleView({super.key});

  static DateTime _mondayOf(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return local.subtract(Duration(days: local.weekday - DateTime.monday));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final today = DateTime.now();
    final carbCycle = ref.watch(
      generatedCarbCycleProvider(DateTime(today.year, today.month, today.day)),
    );

    return HxScreenShell(
      title: 'Ciklanje ogljikovih hidratov',
      pinnedBottom: SizedBox(
        width: double.infinity,
        child: PremiumButton(
          text: 'SHRANI TEDENSKI NAČRT',
          isPrimary: true,
          icon: Icons.auto_awesome_rounded,
          onTap: () async {
            final levels = carbCycle.asData?.value;
            if (levels == null) return;
            await ref
                .read(nutritionRepositoryProvider)
                .saveCarbCyclePlan(
                  weekStart: _mondayOf(today),
                  dayLevelsJson: CarbCycleService.encodeLevels(levels),
                );
            if (context.mounted) {
              ref
                  .read(hxToastControllerProvider.notifier)
                  .show(
                    HxToastItem.targetsUpdated(
                      title: 'Ciklanje shranjeno',
                      message: 'Tedenski načrt je pripravljen',
                    ),
                  );
            }
          },
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HxSpace.x2),
          child: Text(
            'Ustvarjeno iz tvojega treninga: najtežji dnevi dobijo največ ogljikovih hidratov za boljšo zmogljivost.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x5),
        carbCycle.when(
          data: (levels) => _CarbCycleRow(levels: levels),
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Center(child: Text('Napaka: $e')),
        ),
      ],
    );
  }
}

// ── Add / Edit Target screen ───────────────────────────────────────────────

/// Which macro input mode the user is working in.
enum _MacroMode { grams, percent, perLb }

/// Full-screen target editor (§5).
class TargetEditorView extends ConsumerStatefulWidget {
  final NutritionTargetData? initialTarget;

  const TargetEditorView({super.key, this.initialTarget});

  @override
  ConsumerState<TargetEditorView> createState() => _TargetEditorViewState();
}

class _TargetEditorViewState extends ConsumerState<TargetEditorView> {
  String _scope = 'global';
  int? _weekday;
  _MacroMode _mode = _MacroMode.grams;

  /// The dieting phase the entered numbers represent (§5).
  DietPhase _phase = DietPhase.maintain;

  /// Maintenance calories the phase adjustment is derived from.
  final _maintenanceKcal = TextEditingController();

  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fiber = TextEditingController();
  // % mode
  final _proteinPct = TextEditingController(text: '30');
  final _carbsPct = TextEditingController(text: '40');
  final _fatPct = TextEditingController(text: '30');
  // g/lb mode
  final _proteinPerLb = TextEditingController(text: '1.0');

  @override
  void initState() {
    super.initState();
    final baseline = ref.read(baselineTargetsProvider);
    final maintenance = ref.read(maintenanceKcalProvider);

    if (widget.initialTarget != null) {
      final t = widget.initialTarget!;
      if (t.appliesTo.startsWith('weekday:')) {
        _scope = 'weekday';
        _weekday = int.tryParse(t.appliesTo.split(':').last) ?? 1;
      } else {
        _scope = t.appliesTo;
      }
      _kcal.text = t.kcal.toString();
      _protein.text = t.proteinG.toString();
      _carbs.text = t.carbsG.toString();
      _fat.text = t.fatG.toString();
      if (t.fiberG != null && t.fiberG! > 0) {
        _fiber.text = t.fiberG.toString();
      }
      _maintenanceKcal.text = (maintenance ?? baseline?.kcal ?? t.kcal)
          .toString();
    } else {
      if (baseline != null) {
        _maintenanceKcal.text = (maintenance ?? baseline.kcal).toString();
        _kcal.text = baseline.kcal.toString();
        _protein.text = baseline.proteinG.toString();
        _carbs.text = baseline.carbsG.toString();
        _fat.text = baseline.fatG.toString();
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _maintenanceKcal,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fiber,
      _proteinPct,
      _carbsPct,
      _fatPct,
      _proteinPerLb,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Returns bodyweight in kg from profile, or null.
  double? get _bodyweightKg =>
      ref.read(profileProvider).asData?.value?.weightKg;

  /// Recomputes every field from the maintenance figure for [_phase] (§5).
  void _applyPhase(DietPhase phase) {
    final eligibility = ref.read(physiqueEditorEligibilityProvider);
    if (!eligibility.allows(phase)) return;
    final baseline = int.tryParse(_maintenanceKcal.text.trim());
    setState(() {
      _phase = phase;
      if (baseline == null || baseline <= 0) return;
      final t = DietPhaseCalculator.apply(
        phase: phase,
        eligibility: eligibility,
        baselineKcal: baseline,
        bodyweightKg: _bodyweightKg,
      );
      _mode = _MacroMode.grams;
      _kcal.text = t.kcal.toString();
      _protein.text = t.proteinG.toString();
      _carbs.text = t.carbsG.toString();
      _fat.text = t.fatG.toString();
    });
  }

  // Converts current mode inputs into final gram values. Returns null if inputs incomplete.
  ({int kcal, int protein, int carbs, int fat})? _resolve() {
    final kcal = int.tryParse(_kcal.text);
    if (kcal == null || kcal <= 0) return null;

    if (_mode == _MacroMode.grams) {
      final p = int.tryParse(_protein.text);
      final c = int.tryParse(_carbs.text);
      final f = int.tryParse(_fat.text);
      if (p == null || c == null || f == null) return null;
      return (kcal: kcal, protein: p, carbs: c, fat: f);
    }

    if (_mode == _MacroMode.percent) {
      final pp = double.tryParse(_proteinPct.text) ?? 0;
      final cp = double.tryParse(_carbsPct.text) ?? 0;
      final fp = double.tryParse(_fatPct.text) ?? 0;
      if ((pp + cp + fp - 100).abs() > 1) return null;
      final p = (kcal * pp / 100 / 4).round();
      final c = (kcal * cp / 100 / 4).round();
      final f = (kcal * fp / 100 / 9).round();
      return (kcal: kcal, protein: p, carbs: c, fat: f);
    }

    // _MacroMode.perLb
    final bwKg = _bodyweightKg;
    if (bwKg == null) return null;
    final bwLb = bwKg * 2.20462;
    final gPerLb = double.tryParse(_proteinPerLb.text) ?? 1.0;
    final p = (bwLb * gPerLb).round();
    // Remaining kcal split 55% carbs / rest fat.
    final remainingKcal = kcal - p * 4;
    if (remainingKcal < 0) return null;
    final c = (remainingKcal * 0.55 / 4).round();
    final f = ((remainingKcal - c * 4) / 9).round().clamp(0, 9999).toInt();
    return (kcal: kcal, protein: p, carbs: c, fat: f);
  }

  double get _pctSum =>
      (double.tryParse(_proteinPct.text) ?? 0) +
      (double.tryParse(_carbsPct.text) ?? 0) +
      (double.tryParse(_fatPct.text) ?? 0);

  String get _scopeKey {
    if (_scope == 'weekday' && _weekday != null) return 'weekday:$_weekday';
    return _scope;
  }

  String get _scopeLabel {
    if (_scope == 'global') return 'Splošno';
    if (_scope == 'training_day') return 'Dan treninga';
    if (_scope == 'rest_day') return 'Dan počitka';
    if (_scope == 'weekday' && _weekday != null) {
      const names = ['Pon', 'Tor', 'Sre', 'Čet', 'Pet', 'Sob', 'Ned'];
      return names[(_weekday! - 1).clamp(0, 6)];
    }
    return _scope;
  }

  Future<void> _save() async {
    final resolved = _resolve();
    if (resolved == null) {
      String msg = 'Izpolni kalorije in vsa polja makrohranil.';
      if (_mode == _MacroMode.percent && (_pctSum - 100).abs() > 1) {
        msg =
            'Odstotki makrohranil morajo skupaj znašati 100 % (trenutno ${_pctSum.round()} %).';
      } else if (_mode == _MacroMode.perLb && _bodyweightKg == null) {
        msg = 'Najprej dodaj telesno težo v profilu.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    await ref
        .read(nutritionRepositoryProvider)
        .upsertTarget(
          label: _scopeLabel,
          appliesTo: _scopeKey,
          kcal: resolved.kcal,
          proteinG: resolved.protein,
          carbsG: resolved.carbs,
          fatG: resolved.fat,
          fiberG: int.tryParse(_fiber.text),
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final eligibility = ref.watch(physiqueEditorEligibilityProvider);
    final bwKg = _bodyweightKg;
    final bwLb = bwKg != null ? bwKg * 2.20462 : null;

    final kcalVal = int.tryParse(_kcal.text) ?? 0;
    final resolved = kcalVal > 0 ? _resolve() : null;

    return HxScreenShell(
      title: widget.initialTarget != null ? 'Uredi cilj' : 'Dodaj cilj',
      pinnedBottom: SizedBox(
        width: double.infinity,
        child: PremiumButton(
          text: _phase.saveLabel.toUpperCase(),
          isPrimary: true,
          icon: Icons.check_circle_outline_rounded,
          onTap: _save,
        ),
      ),
      children: [
        Center(
          child: Text(
            'Shranjevanje za isti obseg nadomesti obstoječi cilj za ta obseg.',
            textAlign: TextAlign.center,
            style: TextStyle(color: hx.onSurfaceVariant, fontSize: 13),
          ),
        ),
        const SizedBox(height: HxSpace.x5),

        // ── Dieting phase (§5) ──
        _SectionTitle('PREHRANSKA FAZA'),
        const SizedBox(height: HxSpace.x2),
        RestrictionNoticeList(
          eligibility: eligibility,
          onAddAge: () => context.push(AppRoutes.profile),
        ),
        if (eligibility.isRestricted) const SizedBox(height: HxSpace.x3),
        Wrap(
          spacing: 8,
          children: [
            for (final phase in DietPhase.values)
              ChoiceChip(
                label: Text(phase.label),
                selected: _phase == phase,
                onSelected: eligibility.allows(phase)
                    ? (_) => _applyPhase(phase)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: HxSpace.x3),
        _NumField(
          controller: _maintenanceKcal,
          label: 'Vzdrževalne kalorije',
          suffix: 'kcal',
          onChanged: (_) => _applyPhase(_phase),
        ),
        const SizedBox(height: HxSpace.x2),
        const TdeeEstimateBadge(),
        const SizedBox(height: HxSpace.x2),
        Text(
          _phase.subtitle,
          style: TextStyle(color: hx.onSurfaceVariant, fontSize: 12),
        ),

        const SizedBox(height: HxSpace.x6),

        // ── Scope ──
        _SectionTitle('VELJA ZA'),
        const SizedBox(height: HxSpace.x2),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in {
              'global': 'Splošno (vsak dan)',
              'training_day': 'Dan treninga',
              'rest_day': 'Dan počitka',
              'weekday': 'Določen dan v tednu',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _scope == entry.key,
                onSelected: (_) => setState(() {
                  _scope = entry.key;
                  _weekday ??= 1;
                }),
              ),
          ],
        ),
        if (_scope == 'weekday') ...[
          const SizedBox(height: HxSpace.x3),
          Text(
            'IZBERI DAN',
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 1; i <= 7; i++)
                ChoiceChip(
                  label: Text(
                    ['Pon', 'Tor', 'Sre', 'Čet', 'Pet', 'Sob', 'Ned'][i - 1],
                  ),
                  selected: _weekday == i,
                  onSelected: (_) => setState(() => _weekday = i),
                ),
            ],
          ),
        ],

        const SizedBox(height: HxSpace.x6),

        // ── Calories ──
        _SectionTitle('KALORIJE'),
        const SizedBox(height: HxSpace.x2),
        _NumField(
          controller: _kcal,
          label: 'Dnevne ciljne kalorije',
          suffix: 'kcal',
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: HxSpace.x6),

        // ── Macro input mode ──
        _SectionTitle('NAČIN VNOSA MAKROHRANIL'),
        const SizedBox(height: HxSpace.x2),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Grami'),
              selected: _mode == _MacroMode.grams,
              onSelected: (_) => setState(() => _mode = _MacroMode.grams),
            ),
            ChoiceChip(
              label: const Text('% kalorij'),
              selected: _mode == _MacroMode.percent,
              onSelected: (_) => setState(() => _mode = _MacroMode.percent),
            ),
            ChoiceChip(
              label: const Text('g / lb telesne teže'),
              selected: _mode == _MacroMode.perLb,
              onSelected: (_) => setState(() => _mode = _MacroMode.perLb),
            ),
          ],
        ),

        const SizedBox(height: HxSpace.x4),

        // ── Mode-specific inputs ──
        if (_mode == _MacroMode.grams) ...[
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: _protein,
                  label: 'Beljakovine',
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  controller: _carbs,
                  label: 'OH',
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: _fat,
                  label: 'Maščobe',
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  controller: _fiber,
                  label: 'Vlaknine (neobvezno)',
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (int.tryParse(_protein.text) != null &&
              int.tryParse(_carbs.text) != null &&
              int.tryParse(_fat.text) != null) ...[
            const SizedBox(height: 8),
            _MacroKcalSummary(
              proteinG: int.tryParse(_protein.text) ?? 0,
              carbsG: int.tryParse(_carbs.text) ?? 0,
              fatG: int.tryParse(_fat.text) ?? 0,
              targetKcal: int.tryParse(_kcal.text) ?? 0,
            ),
          ],
        ],

        if (_mode == _MacroMode.percent) ...[
          Text(
            'Nastavi odstotek vseh kalorij za posamezno makrohranilo. Skupaj mora biti 100 %.',
            style: TextStyle(color: hx.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: _proteinPct,
                  label: 'Beljakovine',
                  suffix: '%',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  controller: _carbsPct,
                  label: 'OH',
                  suffix: '%',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  controller: _fatPct,
                  label: 'Maščobe',
                  suffix: '%',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Skupaj: ${_pctSum.round()} %',
                style: TextStyle(
                  color: (_pctSum - 100).abs() <= 1
                      ? const Color(0xFF30D158)
                      : hx.danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 150,
                child: _NumField(
                  controller: _fiber,
                  label: 'Vlaknine (neobvezno)',
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],

        if (_mode == _MacroMode.perLb) ...[
          if (bwLb != null)
            Text(
              'Tvoja telesna teža: ${bwLb.toStringAsFixed(1)} lb (${bwKg!.toStringAsFixed(1)} kg)',
              style: TextStyle(color: hx.onSurfaceVariant, fontSize: 13),
            )
          else
            Text(
              'Za ta način dodaj telesno težo v profilu.',
              style: TextStyle(color: hx.danger, fontSize: 13),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: _proteinPerLb,
                  label: 'Beljakovine',
                  suffix: 'g/lb',
                  hint: '1.0',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumField(
                  controller: _fiber,
                  label: 'Vlaknine (neobvezno)',
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (bwLb != null) ...[
            const SizedBox(height: 6),
            Text(
              'Predlog: 1,0 g/lb = ${(bwLb * 1.0).round()} g beljakovin',
              style: TextStyle(color: hx.onSurfaceVariant, fontSize: 12),
            ),
          ],
          Text(
            'Preostale kalorije se razdelijo: 55 % OH / 45 % maščob.',
            style: TextStyle(color: hx.onSurfaceVariant, fontSize: 12),
          ),
        ],

        // ── Live preview ──
        if (resolved != null && _mode != _MacroMode.grams) ...[
          const SizedBox(height: HxSpace.x4),
          _LivePreviewCard(resolved: resolved),
        ],

        const SizedBox(height: HxSpace.x6),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Text(
      text,
      style: TextStyle(
        color: hx.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }
}

class _MacroKcalSummary extends StatelessWidget {
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int targetKcal;

  const _MacroKcalSummary({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.targetKcal,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final totalMacroKcal = (proteinG * 4) + (carbsG * 4) + (fatG * 9);
    final diff = totalMacroKcal - targetKcal;
    final isMatch = targetKcal > 0 && diff.abs() <= 15;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMatch
            ? const Color(0xFF30D158).withValues(alpha: 0.1)
            : hx.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isMatch
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            size: 16,
            color: isMatch ? const Color(0xFF30D158) : hx.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Vsota makrov: $totalMacroKcal kcal ${targetKcal > 0 ? '(cilj: $targetKcal kcal · ${diff >= 0 ? '+' : ''}$diff)' : ''}',
              style: TextStyle(
                color: isMatch ? const Color(0xFF30D158) : hx.onSurfaceVariant,
                fontSize: 12,
                fontWeight: isMatch ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePreviewCard extends StatelessWidget {
  final ({int kcal, int protein, int carbs, int fat}) resolved;

  const _LivePreviewCard({required this.resolved});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hx.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _PreviewItem(
            label: 'Beljakovine',
            value: '${resolved.protein}g',
            color: AppColors.macroProtein,
          ),
          _PreviewItem(
            label: 'OH',
            value: '${resolved.carbs}g',
            color: AppColors.macroCarbs,
          ),
          _PreviewItem(
            label: 'Maščobe',
            value: '${resolved.fat}g',
            color: AppColors.macroFat,
          ),
          _PreviewItem(
            label: 'Kalorije',
            value: '${resolved.kcal} kcal',
            color: hx.primary,
          ),
        ],
      ),
    );
  }
}

class _PreviewItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PreviewItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: hx.onSurfaceVariant, fontSize: 11)),
      ],
    );
  }
}

// ── Cut / Bulk schedule sheet ──────────────────────────────────────────────

class _CutBulkSheet extends StatefulWidget {
  final WidgetRef ref;
  final bool isBulk;
  const _CutBulkSheet({required this.ref, required this.isBulk});

  @override
  State<_CutBulkSheet> createState() => _CutBulkSheetState();
}

class _CutBulkSheetState extends State<_CutBulkSheet> {
  final _pct = TextEditingController();
  final _interval = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pct.text = widget.isBulk ? '3' : '5';
    _interval.text = '14';
  }

  @override
  void dispose() {
    _pct.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final pct = double.tryParse(_pct.text);
    final interval = int.tryParse(_interval.text);
    if (pct == null || interval == null || pct <= 0 || interval <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vnesi veljavna pozitivna števila')),
      );
      return;
    }
    final effectivePct = widget.isBulk ? -pct : pct;
    await widget.ref
        .read(nutritionRepositoryProvider)
        .startDietSchedule(
          startDate: DateTime.now(),
          reducePct: effectivePct,
          intervalDays: interval,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final mq = MediaQuery.of(context);
    final color = widget.isBulk ? const Color(0xFF30D158) : hx.primary;
    final title = widget.isBulk ? 'Začni maso' : 'Začni redukcijo';
    final verb = widget.isBulk ? 'Povečaj' : 'Zmanjšaj';

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: hx.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: hx.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    widget.isBulk
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: color,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      color: hx.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.isBulk
                    ? 'Kalorije se vsak interval povečajo za nastavljeni %. Beljakovine ostanejo enake; presežek gre v OH in maščobe.'
                    : 'Kalorije se vsak interval zmanjšajo za nastavljeni %. Beljakovine ostanejo enake; primanjkljaj pride iz OH in maščob.',
                style: TextStyle(color: hx.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      controller: _pct,
                      label: '$verb za (%)',
                      suffix: '%',
                      hint: widget.isBulk ? '3' : '5',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumField(
                      controller: _interval,
                      label: 'Vsakih (dni)',
                      suffix: 'dni',
                      hint: '14',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: PremiumButton(
                  text: title.toUpperCase(),
                  isPrimary: true,
                  onTap: _start,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  const _NumField({
    required this.controller,
    required this.label,
    this.hint,
    this.suffix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      style: TextStyle(
        color: hx.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hx.onSurfaceVariant, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: hx.onSurfaceVariant.withValues(alpha: 0.5)),
        suffixText: suffix,
        suffixStyle: TextStyle(
          color: hx.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        filled: true,
        fillColor: hx.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: hx.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: hx.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: hx.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

class _CarbCycleRow extends StatelessWidget {
  final List<CarbLevel> levels;
  const _CarbCycleRow({required this.levels});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    const days = ['Pon', 'Tor', 'Sre', 'Čet', 'Pet', 'Sob', 'Ned'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < levels.length && i < 7; i++)
            Expanded(
              child: Column(
                children: [
                  Text(
                    days[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hx.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: _color(levels[i]).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _color(levels[i]).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          levels[i].label[0],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _color(levels[i]),
                          ),
                        ),
                        Text(
                          levels[i].label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: _color(levels[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _color(CarbLevel l) => switch (l) {
    CarbLevel.high => const Color(0xFF30D158),
    CarbLevel.medium => const Color(0xFFFF9F0A),
    CarbLevel.low => const Color(0xFFFF453A),
  };
}

class _MinimumTargetsSection extends ConsumerStatefulWidget {
  final double? bwKg;
  const _MinimumTargetsSection({required this.bwKg});

  @override
  ConsumerState<_MinimumTargetsSection> createState() =>
      __MinimumTargetsSectionState();
}

class __MinimumTargetsSectionState
    extends ConsumerState<_MinimumTargetsSection> {
  late TextEditingController _kcalController;
  late TextEditingController _customGramsController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(minimumTargetsProvider);
    _kcalController = TextEditingController(
      text: state.minCaloriesKcal?.toString() ?? '',
    );
    _customGramsController = TextEditingController(
      text: state.proteinValue.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _kcalController.dispose();
    _customGramsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final minTargets = ref.watch(minimumTargetsProvider);
    final notifier = ref.read(minimumTargetsProvider.notifier);
    final bwKg = widget.bwKg;
    final bwLb = bwKg != null ? bwKg * 2.20462 : null;
    final resolvedMinP = minTargets.resolvedMinProteinG(bwKg);

    return Container(
      decoration: BoxDecoration(
        color: hx.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: minTargets.enabled
              ? hx.primary.withValues(alpha: 0.4)
              : hx.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: minTargets.enabled ? hx.primary : hx.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Minimalni cilji (beljakovine in kalorije)',
                        style: TextStyle(
                          color: hx.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (minTargets.enabled && resolvedMinP != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Min. beljakovine: ${resolvedMinP} g'
                          '${minTargets.minCaloriesKcal != null ? ' • Min. ${minTargets.minCaloriesKcal} kcal' : ''}',
                          style: TextStyle(
                            color: hx.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (!minTargets.enabled) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Nastavi spodnjo mejo za proteine in kalorije',
                          style: TextStyle(
                            color: hx.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: minTargets.enabled,
                  onChanged: (val) => notifier.setEnabled(val),
                ),
              ],
            ),
            children: [
              if (minTargets.enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(color: hx.outlineVariant.withValues(alpha: 0.2)),
                      const SizedBox(height: 8),

                      // ── Minimum Protein Presets & Formulas ──
                      Text(
                        'MINIMALNE BELJAKOVINE (FORMULA)',
                        style: TextStyle(
                          color: hx.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MinProteinChip(
                            label: '1.0 g/lb (Optimalno)',
                            selected:
                                minTargets.mode == MinProteinMode.perLb &&
                                (minTargets.proteinValue - 1.0).abs() < 0.05,
                            onTap: () {
                              notifier.setMode(MinProteinMode.perLb);
                              notifier.setProteinValue(1.0);
                            },
                          ),
                          _MinProteinChip(
                            label: '0.8 g/lb',
                            selected:
                                minTargets.mode == MinProteinMode.perLb &&
                                (minTargets.proteinValue - 0.8).abs() < 0.05,
                            onTap: () {
                              notifier.setMode(MinProteinMode.perLb);
                              notifier.setProteinValue(0.8);
                            },
                          ),
                          _MinProteinChip(
                            label: '1.2 g/lb (Visoko)',
                            selected:
                                minTargets.mode == MinProteinMode.perLb &&
                                (minTargets.proteinValue - 1.2).abs() < 0.05,
                            onTap: () {
                              notifier.setMode(MinProteinMode.perLb);
                              notifier.setProteinValue(1.2);
                            },
                          ),
                          _MinProteinChip(
                            label: '2.2 g/kg',
                            selected:
                                minTargets.mode == MinProteinMode.perKg &&
                                (minTargets.proteinValue - 2.2).abs() < 0.05,
                            onTap: () {
                              notifier.setMode(MinProteinMode.perKg);
                              notifier.setProteinValue(2.2);
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      if (bwLb != null && resolvedMinP != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.macroProtein.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.fitness_center_rounded,
                                size: 14,
                                color: AppColors.macroProtein,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Izračunan minimum: ${resolvedMinP}g '
                                  '(${bwLb.toStringAsFixed(1)} lb @ ${minTargets.proteinValue} ${minTargets.mode.label})',
                                  style: TextStyle(
                                    color: AppColors.macroProtein,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          'Za samodejni izračun g/lb dodajte težo v profilu.',
                          style: TextStyle(
                            color: hx.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),

                      const SizedBox(height: 14),

                      // ── Minimum Calories Floor ──
                      Text(
                        'MINIMALNE KALORIJE (MEJA DEFICITA)',
                        style: TextStyle(
                          color: hx.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _NumField(
                              controller: _kcalController,
                              label: 'Minimalne kalorije',
                              suffix: 'kcal',
                              hint: 'npr. 1500',
                              onChanged: (val) {
                                final parsed = int.tryParse(val.trim());
                                notifier.setMinCalories(parsed);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MinProteinChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MinProteinChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: hx.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? hx.primary : hx.onSurfaceVariant,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 11,
      ),
      side: BorderSide(
        color: selected ? hx.primary : hx.outlineVariant.withValues(alpha: 0.4),
      ),
      onSelected: (_) => onTap(),
    );
  }
}
