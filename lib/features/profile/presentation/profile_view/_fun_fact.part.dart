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
