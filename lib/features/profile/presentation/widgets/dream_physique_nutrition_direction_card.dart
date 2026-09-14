import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/profile/data/dream_physique_nutrition_preference_repository.dart';
import 'package:herculex/features/profile/domain/dream_physique_nutrition_recommendation.dart';

/// A member-controlled starting point for nutrition targets after a Dream
/// Physique analysis. It deliberately does not write a diet plan itself.
class DreamPhysiqueNutritionDirectionCard extends ConsumerWidget {
  const DreamPhysiqueNutritionDirectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dreamPhysiqueSummaryProvider).valueOrNull;
    final profile = ref.watch(profileProvider).valueOrNull;
    final recommendation = DreamPhysiqueNutritionRecommender.recommend(
      profile: profile,
      summary: summary,
    );
    if (summary == null || recommendation == null) {
      return const SizedBox.shrink();
    }

    final preference = ref
        .watch(dreamPhysiqueNutritionPreferenceProvider)
        .valueOrNull;
    final isForCurrentAnalysis =
        preference?.summaryAnalyzedAt.isAtSameMomentAs(summary.analyzedAt) ??
        false;
    if (isForCurrentAnalysis && preference!.dismissed) {
      return const SizedBox.shrink();
    }

    final chosenDirection = isForCurrentAnalysis
        ? preference?.selectedDirection ?? recommendation.direction
        : recommendation.direction;
    final isUserChoice =
        isForCurrentAnalysis && preference?.selectedDirection != null;

    return HxCard(
      key: const Key('dream-physique-nutrition-direction-card'),
      accent: context.hx.domainNutrition,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: context.hx.domainNutrition.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.route_rounded,
                  color: context.hx.domainNutrition,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUserChoice
                          ? 'Your next nutrition phase'
                          : 'Optional next nutrition phase',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUserChoice
                          ? 'You chose ${chosenDirection.label}. You can change it any time.'
                          : 'A starting point based on your saved profile and Dream Physique summary.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            chosenDirection.label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: context.hx.domainNutrition,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            chosenDirection.shortDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          ...recommendation.reasons.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: context.hx.domainNutrition,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      reason,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.hx.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a different direction',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PhysiqueNutritionDirection.values.map((direction) {
              return ChoiceChip(
                key: Key('nutrition-direction-${direction.name}'),
                label: Text(direction.label),
                selected: chosenDirection == direction,
                onSelected: (_) => _choose(
                  ref: ref,
                  summaryAnalyzedAt: summary.analyzedAt,
                  direction: direction,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            'Planning guidance only — adjust it for your preferences, recovery, and circumstances. It is not medical advice.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.hx.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                key: const Key('dismiss-nutrition-direction'),
                onPressed: () =>
                    _dismiss(ref: ref, summaryAnalyzedAt: summary.analyzedAt),
                child: const Text('Not now'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('open-nutrition-targets'),
                onPressed: () => context.push(
                  AppRoutes.nutritionTargets,
                  extra: chosenDirection.dietPhase,
                ),
                child: const Text('Set targets'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _choose({
    required WidgetRef ref,
    required DateTime summaryAnalyzedAt,
    required PhysiqueNutritionDirection direction,
  }) {
    return ref
        .read(dreamPhysiqueNutritionPreferenceRepositoryProvider)
        .save(
          DreamPhysiqueNutritionPreference(
            summaryAnalyzedAt: summaryAnalyzedAt,
            selectedDirection: direction,
          ),
        );
  }

  Future<void> _dismiss({
    required WidgetRef ref,
    required DateTime summaryAnalyzedAt,
  }) {
    return ref
        .read(dreamPhysiqueNutritionPreferenceRepositoryProvider)
        .save(
          DreamPhysiqueNutritionPreference(
            summaryAnalyzedAt: summaryAnalyzedAt,
            dismissed: true,
          ),
        );
  }
}
