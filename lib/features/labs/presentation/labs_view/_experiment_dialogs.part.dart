part of '../labs_view.dart';

// Stopping, reading and starting an experiment.

Future<void> _confirmStop(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> experiment,
) async {
  final stop = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Stop this experiment?'),
      content: const Text(
        'It moves to past experiments without a conclusion. Your logs are '
        'unaffected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Keep running'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Stop experiment'),
        ),
      ],
    ),
  );
  if (stop != true) return;
  await ref
      .read(labsRepositoryProvider)
      .stopExperiment(experiment, at: ref.read(clockProvider).now());
}

/// The full protocol and the comparison so far.
Future<void> _showExperimentDetails(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> e,
) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(e['title']),
    content: SingleChildScrollView(
      child: Text(
        'Usual setup: ${e['baselineDescription'] ?? 'Usual routine'}\nPlanned change: ${e['changeDescription'] ?? e['change']}\n\n${e['protocol']}\n\n${_experimentText(e)}\n\nBaseline ends ${e['baselineEnd'].toString().substring(0, 10)}\nReview ${e['end'].toString().substring(0, 10)}\n\nRecord deviations on the change timeline.',
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
    ],
  ),
);

Future<void> _startExperiment(BuildContext context, WidgetRef ref) async {
  var selected = 'rest';
  final target = TextEditingController(text: '2');
  final baseline = TextEditingController();
  final change = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('One change at a time'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                items: [
                  for (final t in LabsRepository.templates.entries)
                    DropdownMenuItem(value: t.key, child: Text(t.value.$1)),
                ],
                onChanged: (v) => set(() => selected = v!),
              ),
              const SizedBox(height: 12),
              const Text(
                '14 days of your usual routine, then 14 days changing one factor. This is a descriptive comparison, not a blinded trial. Rest duration and adherence must be recorded on your timeline.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: baseline,
                decoration: const InputDecoration(
                  labelText: 'Your usual setup',
                  hintText: 'For example: 120 seconds rest',
                ),
              ),
              TextField(
                controller: change,
                decoration: const InputDecoration(
                  labelText: 'The single planned change',
                  hintText: 'For example: 180 seconds rest',
                ),
              ),
              TextField(
                controller: target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      'Meaningful change (${LabsRepository.templates[selected]!.$4})',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                if (baseline.text.trim().isEmpty ||
                    change.text.trim().isEmpty) {
                  throw StateError(
                    'Describe your usual setup and the single planned change first.',
                  );
                }
                await ref
                    .read(labsRepositoryProvider)
                    .startExperiment(
                      selected,
                      ref.read(clockProvider).now(),
                      double.tryParse(target.text) ?? 0,
                      baselineDescription: baseline.text.trim(),
                      changeDescription: change.text.trim(),
                    );
                if (c.mounted) Navigator.pop(c);
              } catch (e) {
                if (c.mounted) {
                  AppNotice.show(
                    context,
                    e is StateError
                        ? e.message
                        : 'Enter a positive target change.',
                    kind: AppNoticeKind.error,
                  );
                }
              }
            },
            child: const Text('Start baseline'),
          ),
        ],
      ),
    ),
  );
  target.dispose();
  baseline.dispose();
  change.dispose();
}
