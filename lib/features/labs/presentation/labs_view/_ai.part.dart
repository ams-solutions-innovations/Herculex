part of '../labs_view.dart';

Future<void> _explain(
  BuildContext context,
  WidgetRef ref,
  LabsSnapshot snapshot,
) async {
  final repo = ref.read(labsRepositoryProvider);
  final previewToken = jsonEncode(repo.consent.toJson());
  final allowed = {...repo.consent.categories};
  final selected = {...allowed};
  final approved = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Preview what leaves your device'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Only these aggregate values are sent to Herculex AI. No photos, names, notes or individual logs.',
                ),
                for (final cat in allowed)
                  CheckboxListTile(
                    title: Text(cat.label),
                    value: selected.contains(cat),
                    onChanged: (v) => set(
                      () =>
                          v == true ? selected.add(cat) : selected.remove(cat),
                    ),
                  ),
                SelectableText(
                  const JsonEncoder.withIndent(
                    '  ',
                  ).convert(LabsAiService.facts(snapshot, selected)),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selected.isEmpty ? null : () => Navigator.pop(c, true),
            child: const Text('Send this summary'),
          ),
        ],
      ),
    ),
  );
  if (approved != true ||
      jsonEncode(repo.consent.toJson()) != previewToken ||
      !context.mounted ||
      !repo.consent.enabled ||
      !repo.consent.ai ||
      !repo.consent.categories.containsAll(selected)) {
    return;
  }
  final token = jsonEncode(repo.consent.toJson());
  final notices = AppNotice.of(context);
  notices.show('Writing your optional explanation…', kind: AppNoticeKind.info);
  try {
    final explanation = await ref
        .read(labsAiProvider)
        .explain(LabsAiService.facts(snapshot, selected));
    if (!context.mounted || jsonEncode(repo.consent.toJson()) != token) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Optional AI explanation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(explanation.summary),
              const SizedBox(height: 12),
              for (final text in explanation.suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $text'),
                ),
              const Text(
                'Your recorded findings and support levels remain authoritative.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  } catch (_) {
    if (context.mounted) {
      notices.show(
        'AI explanation is unavailable or could not be validated. Local results and PDFs remain available.',
        kind: AppNoticeKind.error,
      );
    }
  }
}

String _experimentText(Map<String, dynamic> experiment) {
  final result = experiment['evaluation'] as Map?;
  if (result == null) return 'Collecting baseline observations.';
  final before =
      (result['before'] as num?)?.toStringAsFixed(1) ?? 'Not enough data';
  final after =
      (result['after'] as num?)?.toStringAsFixed(1) ?? 'Not enough data';
  final delta = (result['delta'] as num?)?.toStringAsFixed(1);
  return '${result['state']}\nBaseline: $before ${experiment['unit']} (${result['beforeDays']} days)'
      '\nChange phase: $after ${experiment['unit']} (${result['afterDays']} days)'
      '${delta == null ? '' : '\nObserved difference: $delta ${experiment['unit']}'}'
      '${result['targetMet'] == null
          ? ''
          : result['targetMet'] == true
          ? '\nYour predefined target was reached in the recorded data.'
          : '\nYour predefined target was not reached in the recorded data.'}'
      '\n\n${result['limitation']}';
}

class _LabsTheme extends StatelessWidget {
  const _LabsTheme({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: theme.textTheme.labelLarge,
          secondaryLabelStyle: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
      child: child,
    );
  }
}
