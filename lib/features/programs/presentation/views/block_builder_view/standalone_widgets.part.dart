part of '../block_builder_view.dart';

class _RecommendedPill extends StatelessWidget {
  const _RecommendedPill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'Recommended',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ManualMusclePlanSheet extends StatefulWidget {
  const _ManualMusclePlanSheet({
    required this.labels,
    required this.initialWeights,
    required this.initialCaps,
  });

  final Map<String, String> labels;
  final Map<String, int> initialWeights;
  final Map<String, int> initialCaps;

  @override
  State<_ManualMusclePlanSheet> createState() => _ManualMusclePlanSheetState();
}

class _ManualMusclePlanSheetState extends State<_ManualMusclePlanSheet> {
  late final Map<String, int> _weights = Map.of(widget.initialWeights);
  late final Map<String, int> _caps = Map.of(widget.initialCaps);

  int get _total => _weights.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        maxChildSize: .95,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Set my muscle priorities',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the muscle groups that matter most. Percentages are your relative focus volume and always add up to 100%. The set number is a weekly hard-set ceiling.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    Text(
                      'Choose focus muscles',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.labels.entries.map((entry) {
                        final selected = _weights.containsKey(entry.key);
                        return FilterChip(
                          label: Text(entry.value),
                          selected: selected,
                          onSelected: (value) => setState(() {
                            if (value) {
                              _weights[entry.key] = 1;
                              _caps[entry.key] = 10;
                            } else {
                              _weights.remove(entry.key);
                              _caps.remove(entry.key);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    if (_weights.isEmpty) ...[
                      const SizedBox(height: 28),
                      Text(
                        'No focus selected: the program will use your goal and any saved Dream Physique priorities.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 24),
                      Text(
                        'Focus and set ceiling',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final id in _weights.keys.toList())
                        _focusRow(theme, id),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PremiumButton(
                  text: _weights.isEmpty
                      ? 'Use goal / AI recommendation'
                      : 'Use these priorities',
                  onTap: () => Navigator.pop(context, (
                    weights: Map.of(_weights),
                    caps: Map.of(_caps),
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _focusRow(ThemeData theme, String id) {
    final pct = _total == 0 ? 0 : (_weights[id]! / _total * 100).round();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.labels[id]!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _caps[id],
                underline: const SizedBox.shrink(),
                items: const [10, 15, 20]
                    .map(
                      (sets) => DropdownMenuItem(
                        value: sets,
                        child: Text('≤$sets sets'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _caps[id] = value);
                },
              ),
            ],
          ),
          Slider(
            value: _weights[id]!.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$pct%',
            onChanged: (value) => setState(() => _weights[id] = value.round()),
          ),
        ],
      ),
    );
  }
}
