part of '../profile_view.dart';

/// "Today you squatted 3 cars" — shown only when the history has something
/// worth saying.
class _ProfileFunFactCard extends ConsumerWidget {
  const _ProfileFunFactCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fact = ref.watch(funFactProvider).valueOrNull;
    if (fact == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hx = context.hx;
    final text = funFactSentence(fact, ref.watch(weightFormatProvider));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HxCard(
        accent: hx.domainTraining,
        padding: const EdgeInsets.all(HxSpace.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_rounded, color: hx.domainTraining),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FUN FACT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.domainTraining,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's sentence; units come from the user's measurement setting.
@visibleForTesting
String funFactSentence(FunFact fact, WeightFormat units) {
  final load = fact.kind == FunFactKind.todayHeaviestSet
      ? units.format(fact.kg)
      : units.formatTonnage(fact.kg);
  final what = fact.comparison.phrase;
  return switch (fact.kind) {
    FunFactKind.todayExercise =>
      "Today's ${fact.subject} added up to $load. That's $what.",
    FunFactKind.todayHeaviestSet =>
      'Your heaviest set today, $load, weighs as much as $what.',
    FunFactKind.weekCategory =>
      'This week your ${_categoryNoun(fact.category)} work moved $load. '
          "That's $what.",
    FunFactKind.weekTotal => "This week you've moved $load. That's $what.",
    FunFactKind.lifetime => "All-time you've moved $load. That's $what.",
  };
}

String _categoryNoun(MuscleCategory? c) => switch (c) {
  MuscleCategory.push => 'push',
  MuscleCategory.pull => 'pull',
  MuscleCategory.legs => 'leg',
  MuscleCategory.core || null => 'core',
};
