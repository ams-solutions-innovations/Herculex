part of '../labs_view.dart';

Future<void> _checkIn(BuildContext context, WidgetRef ref) async {
  final now = ref.read(clockProvider).now();
  final repo = ref.read(labsRepositoryProvider);
  final old = repo
      .records('checkin')
      .where((r) => r['at'].toString().startsWith(labsDate(now)))
      .firstOrNull;
  final values = <String, double>{
    if (old != null)
      ...(old['values'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
  };
  final note = TextEditingController(text: old?['note'] ?? '');
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('How are you today?'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Only the scores you touch are saved. 0 = none / very low; 5 = very high.',
                ),
                for (final key in [
                  'energy',
                  'stress',
                  'pain',
                  'hunger',
                  'sleep_quality',
                  'digestion',
                ])
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(labsMetricLabels[key] ?? key)),
                          Text(
                            values.containsKey(key)
                                ? values[key]!.round().toString()
                                : 'Not recorded',
                          ),
                          if (values.containsKey(key))
                            IconButton(
                              tooltip: 'Clear score',
                              onPressed: () => set(() => values.remove(key)),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                        ],
                      ),
                      Slider(
                        value: values[key] ?? 2,
                        min: 0,
                        max: 5,
                        divisions: 5,
                        onChanged: (v) => set(() => values[key] = v),
                      ),
                    ],
                  ),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Optional context',
                    hintText:
                        'Illness, travel, caffeine, alcohol, unusual routine…',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await repo.checkIn(now, values, note: note.text.trim());
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
}

Future<void> _change(BuildContext context, WidgetRef ref) async {
  final consent = ref.read(labsConsentProvider);
  var cat = consent.categories.first;
  var date = ref.read(clockProvider).now();
  DateTime? end;
  var diet = false;
  var goal = 'maintenance';
  final title = TextEditingController(), details = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Record a change'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<LabsCategory>(
                initialValue: cat,
                isExpanded: true,
                items: [
                  for (final v in consent.categories)
                    DropdownMenuItem(value: v, child: Text(v.label)),
                ],
                onChanged: (v) => set(() => cat = v!),
              ),
              if (cat == LabsCategory.nutrition) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Track this as a diet period'),
                  value: diet,
                  onChanged: (v) => set(() => diet = v == true),
                ),
                if (diet)
                  DropdownButtonFormField<String>(
                    initialValue: goal,
                    decoration: const InputDecoration(labelText: 'Diet goal'),
                    items: const [
                      DropdownMenuItem(
                        value: 'fat_loss',
                        child: Text('Fat loss'),
                      ),
                      DropdownMenuItem(
                        value: 'maintenance',
                        child: Text('Maintain bodyweight'),
                      ),
                      DropdownMenuItem(
                        value: 'muscle_gain',
                        child: Text('Gain muscle / bodyweight'),
                      ),
                    ],
                    onChanged: (v) => set(() => goal = v!),
                  ),
              ],
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'What changed?',
                  hintText: 'Started creatine, higher protein, new programme…',
                ),
              ),
              TextField(
                controller: details,
                decoration: const InputDecoration(
                  labelText: 'Details / dose / diet goal',
                ),
                maxLines: 3,
              ),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: c,
                    firstDate: DateTime(2000),
                    lastDate: ref.read(clockProvider).now(),
                    initialDate: date,
                  );
                  if (d != null) set(() => date = d);
                },
                child: Text('Start: ${labsDate(date)}'),
              ),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: c,
                    firstDate: labsDay(date),
                    lastDate: DateTime(2100),
                    initialDate: labsDay(date),
                  );
                  if (d != null) set(() => end = d);
                },
                child: Text(
                  end == null
                      ? 'Add end date (optional)'
                      : 'End: ${labsDate(end!)}',
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
              if (title.text.trim().isEmpty) return;
              await ref
                  .read(labsRepositoryProvider)
                  .addChange(
                    cat,
                    title.text.trim(),
                    date,
                    end: end == null ? null : labsDate(end!),
                    details: {
                      'note': details.text.trim(),
                      if (cat == LabsCategory.nutrition && diet) 'kind': 'diet',
                      if (cat == LabsCategory.nutrition && diet) 'goal': goal,
                    },
                  );
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Save change'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  details.dispose();
}
