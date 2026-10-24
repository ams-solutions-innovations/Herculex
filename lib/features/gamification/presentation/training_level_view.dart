import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/gamification/presentation/level_band_style.dart';
import 'package:herculex/features/gamification/presentation/strength_percentile_card.dart';

/// The user's Herculex rank: band from strength, I–V from training. XP
/// numbers stay off this screen on purpose; the explainer covers the rules.
class TrainingLevelView extends ConsumerWidget {
  const TrainingLevelView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(levelProgressProvider);
    final strength = ref.watch(strengthAssessmentProvider).valueOrNull;

    return HxScreenShell(
      title: 'Training Level',
      children: [
        const SizedBox(height: HxSpace.x2),
        ...progressAsync.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text(
                  'Could not load training level: $e',
                  style: TextStyle(color: context.hx.danger),
                ),
              ),
            ),
          ],
          data: (progress) => [
            _HeroCard(progress: progress),
            const SizedBox(height: HxSpace.x5),
            if (progress.band.next case final next?) ...[
              _NextBandCard(
                next: next,
                requirements:
                    strength?.requirementsFor(next) ??
                    const <LiftRequirement>[],
              ),
              const SizedBox(height: HxSpace.x5),
            ],
            const StrengthPercentileCard(),
            _BandLadder(current: progress.band),
          ],
        ),
        const SizedBox(height: HxSpace.x6),
        PremiumButton(
          text: 'How Herculex calculates levels',
          isPrimary: false,
          onTap: () {
            Haptics.selection();
            context.push(AppRoutes.levelSystem);
          },
        ),
        const SizedBox(height: HxSpace.x8),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.progress});

  final LevelProgress progress;

  String get _caption {
    final next = progress.nextLevel;
    if (next != null) return 'Keep training to reach ${next.title}';
    final nextBand = progress.band.next;
    if (nextBand == null) return 'Top rank reached';
    return 'Rank maxed. Your lifts unlock ${nextBand.label}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final level = progress.level;
    final bandColor = level.band.color(context);

    return HxCard(
      accent: bandColor,
      padding: const EdgeInsets.all(HxSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bandColor.withValues(alpha: 0.18),
                  border: Border.all(color: bandColor, width: 2),
                ),
                child: Icon(level.band.icon, color: bandColor, size: 30),
              ),
              const SizedBox(width: HxSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.band.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: bandColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: HxSpace.x1),
                    Text(
                      level.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x4),
          Text(
            level.band.lore,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: HxSpace.x5),
          ClipRRect(
            borderRadius: BorderRadius.circular(HxRadius.pill),
            child: LinearProgressIndicator(
              value: progress.progressToNext,
              minHeight: 10,
              backgroundColor: hx.surfaceVariant.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(bandColor),
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          Text(
            _caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// What still stands between the user and the next band.
class _NextBandCard extends StatelessWidget {
  const _NextBandCard({required this.next, required this.requirements});

  final LevelBand next;
  final List<LiftRequirement> requirements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final met = requirements.where((r) => r.met).length;

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(next.icon, size: 20, color: next.color(context)),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: Text(
                  'To reach ${next.label}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${met.clamp(0, liftsNeededPerBand)}/$liftsNeededPerBand',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: next.color(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            next == LevelBand.elite
                ? 'Any $liftsNeededPerBand of these, logged in Herculex.'
                : 'Any $liftsNeededPerBand of these.',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: HxSpace.x3),
          for (final requirement in requirements)
            _RequirementRow(requirement: requirement),
        ],
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.requirement});

  final LiftRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final met = requirement.met;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x1 + 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 20,
            color: met ? hx.success : hx.outline,
          ),
          const SizedBox(width: HxSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${requirement.lift.label} · '
                  '${formatStrengthValue(requirement.lift, requirement.required)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!met)
                  Text(
                    requirementStatus(requirement),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.secondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BandLadder extends StatelessWidget {
  const _BandLadder({required this.current});

  final LevelBand current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Row(
      children: [
        for (final band in LevelBand.values) ...[
          if (band != LevelBand.values.first) const SizedBox(width: HxSpace.x2),
          Expanded(
            child: Builder(
              builder: (context) {
                final color = band.color(context);
                final isCurrent = band == current;
                final reached = band.index <= current.index;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: HxSpace.x3),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? color.withValues(alpha: 0.18)
                        : hx.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(HxRadius.md),
                    border: Border.all(
                      color: isCurrent
                          ? color
                          : hx.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        reached ? band.icon : Icons.lock_outline_rounded,
                        size: 20,
                        color: reached ? color : hx.outline,
                      ),
                      const SizedBox(height: HxSpace.x1),
                      Text(
                        band.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: reached ? hx.onSurface : hx.secondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
