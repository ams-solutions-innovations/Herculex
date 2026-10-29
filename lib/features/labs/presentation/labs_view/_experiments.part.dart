part of '../labs_view.dart';

/// The running experiment up front, the finished ones below, and a way to
/// start the next one.
class _ExperimentsTab extends ConsumerWidget {
  const _ExperimentsTab({required this.snapshot});

  final LabsSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final now = ref.watch(clockProvider).now();
    final newestFirst = [...snapshot.experiments]
      ..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
    final running = newestFirst.where((e) => e['status'] == 'active').toList();
    final past = newestFirst.where((e) => e['status'] != 'active').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (running.isEmpty)
          _HeroCard(
            padding: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Kicker(
                  icon: Icons.science_outlined,
                  text: 'ONE CHANGE AT A TIME',
                  color: hx.primaryText,
                ),
                const SizedBox(height: 8),
                Text(
                  'Test a single change against your usual routine.',
                  style: _labsDisplay(22, letterSpacing: -0.4, height: 1.15),
                ),
                const SizedBox(height: 8),
                Text(
                  '14 days of your usual setup, then 14 days with one change. '
                  'Participation is always optional.',
                  style: TextStyle(
                    color: hx.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        for (final e in running) ...[
          _RunningExperimentCard(experiment: e, snapshot: snapshot, now: now),
          const SizedBox(height: 10),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionTitle('Past experiments', size: 20),
          const SizedBox(height: 10),
          Container(
            decoration: _labsCard(context),
            child: Column(
              children: [
                for (var i = 0; i < past.length; i++)
                  _PastExperimentRow(
                    experiment: past[i],
                    now: now,
                    divider: i > 0,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _DashedButton(
          icon: Icons.add_rounded,
          label: 'New experiment',
          onTap: () => _startExperiment(context, ref),
        ),
      ],
    );
  }
}

/// One running experiment: what changes, how far along it is, the metric
/// split into baseline and change, and the two things to do today.
class _RunningExperimentCard extends ConsumerWidget {
  const _RunningExperimentCard({
    required this.experiment,
    required this.snapshot,
    required this.now,
  });

  final Map<String, dynamic> experiment;
  final LabsSnapshot snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final purple = hx.domainRecovery;
    final purpleText = Color.lerp(purple, Colors.white, 0.4)!;
    final e = experiment;
    final phase = _ExperimentPhase.of(e, now);
    final unit = '${e['unit'] ?? ''}';
    final increase = e['direction'] != 'decrease';
    final metric = '${e['metric']}';
    final evaluation = e['evaluation'] as Map?;
    final before = (evaluation?['before'] as num?)?.toDouble();
    final after = (evaluation?['after'] as num?)?.toDouble();
    final baselineEnd = DateTime.parse(e['baselineEnd'] as String);
    final end = DateTime.parse(e['end'] as String);
    final baselineDays = baselineEnd
        .difference(DateTime.parse(e['at'] as String))
        .inDays;
    final points = [
      for (final f in snapshot.findings)
        for (final p in f.points)
          if (p.metric == metric) p,
    ];
    final change = '${e['changeDescription'] ?? ''}'.trim();
    final title = change.isEmpty || change == 'Selected single change'
        ? '${e['title']}'
        : change;
    final relative = before != null && after != null && before != 0
        ? (after - before) / before.abs() * 100
        : null;
    final towardTarget = relative != null && (relative > 0) == increase;
    final review = DateFormat('d MMM').format(end);
    final targetMet = evaluation != null && evaluation['targetMet'] == true;
    final state = evaluation == null ? null : evaluation['state'];
    final String notice;
    if (phase.label != 'Ready to review') {
      notice = "Target can't be marked as met before the review on $review.";
    } else if (targetMet) {
      notice = 'Your predefined target was reached in the recorded data.';
    } else {
      notice = '${state ?? 'Review the comparison before deciding.'}';
    }

    TextStyle label(Color color) => TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1,
    );

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: purple.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.55],
            colors: [purple.withValues(alpha: 0.18), hx.surfaceContainerLowest],
          ),
        ),
        child: InkWell(
          onTap: () => _showExperimentDetails(context, ref, e),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: purple,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Kicker(
                        text: 'RUNNING · ${phase.label.toUpperCase()}',
                        color: purpleText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: _labsDisplay(24, letterSpacing: -0.4, height: 1.15),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (k, v) in [
                      ('OUTCOME', labsMetricLabels[metric] ?? metric),
                      ('DIRECTION', increase ? 'Increase' : 'Decrease'),
                      (
                        'TARGET',
                        '${increase ? '+' : '−'}${_num((e['target'] as num?)?.toDouble(), unit)}',
                      ),
                    ]) ...[
                      if (k != 'OUTCOME') const SizedBox(width: 8),
                      Expanded(
                        child: _MiniTile(label: k, value: v),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        phase.inChange
                            ? 'BASELINE · $baselineDays DAYS'
                            : 'BASELINE · ${phase.dayText.toUpperCase()}',
                        style: label(hx.secondary),
                      ),
                    ),
                    Text(
                      phase.inChange
                          ? 'CHANGE · ${phase.dayText.toUpperCase()}'
                          : 'CHANGE · NEXT',
                      style: label(hx.secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _PhaseBar(phase: phase, height: 10, marker: true),
                if (points.length > 1) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    decoration: BoxDecoration(
                      color: hx.background.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: _SplitDotsChart(
                      points: points,
                      split: baselineEnd,
                      from: DateTime.parse(e['at'] as String),
                      to: end,
                      before: before,
                      after: after,
                      color: purple,
                      leftLabel: 'Baseline',
                      rightLabel: 'Change',
                      height: 140,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AverageStat(
                        label: 'BASELINE AVG',
                        value: _num(before, unit),
                        labelColor: hx.secondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AverageStat(
                        label: 'SO FAR',
                        value: _num(after, unit),
                        labelColor: purpleText,
                        delta: relative == null
                            ? null
                            : '${relative >= 0 ? '+' : '−'}${relative.abs().toStringAsFixed(1)}%',
                        deltaColor: towardTarget ? hx.success : hx.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: hx.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: hx.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          notice,
                          style: TextStyle(
                            color: hx.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: hx.danger,
                            side: BorderSide(color: hx.outline),
                            shape: RoundedRectangleBorder(
                              borderRadius: HxRadius.mdAll,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: () => _confirmStop(context, ref, e),
                          child: const Text('Stop'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: purple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: HxRadius.mdAll,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: () =>
                              ref
                                  .read(labsConsentProvider)
                                  .allows(LabsCategory.context)
                              ? _checkIn(context, ref)
                              : _change(context, ref),
                          child: Text(
                            ref
                                    .watch(labsConsentProvider)
                                    .allows(LabsCategory.context)
                                ? 'Daily check-in'
                                : 'Record a deviation',
                          ),
                        ),
                      ),
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

/// A finished or stopped experiment in one row.
class _PastExperimentRow extends ConsumerWidget {
  const _PastExperimentRow({
    required this.experiment,
    required this.now,
    required this.divider,
  });

  final Map<String, dynamic> experiment;
  final DateTime now;
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final e = experiment;
    final evaluation = e['evaluation'] as Map?;
    final met = evaluation?['targetMet'] == true;
    final stopped = e['status'] == 'stopped';
    final start = DateTime.parse(e['at'] as String);
    final unit = '${e['unit'] ?? ''}';
    final delta = (evaluation?['delta'] as num?)?.toDouble();
    final metric = labsMetricLabels[e['metric']] ?? '${e['metric']}';
    final String sub;
    if (stopped) {
      final stoppedAt = e['stoppedAt'] == null
          ? now
          : DateTime.parse(e['stoppedAt'] as String);
      sub =
          'Stopped on day ${stoppedAt.difference(start).inDays + 1} · no conclusion';
    } else {
      final change = delta == null
          ? ''
          : ' ${delta >= 0 ? '+' : '−'}${_num(delta.abs(), unit)}';
      sub = '$metric$change · ${met ? 'target met' : 'target not met'}';
    }
    final (icon, color) = stopped
        ? (Icons.stop_circle_outlined, hx.secondary)
        : met
        ? (Icons.check_circle_rounded, hx.success)
        : (Icons.flag_rounded, hx.warning);

    return InkWell(
      onTap: () => _showExperimentDetails(context, ref, e),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: divider
              ? Border(top: BorderSide(color: hx.outlineVariant))
              : null,
        ),
        child: Row(
          children: [
            _IconTile(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e['title']}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(
                      color: hx.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('MMM').format(start),
              style: TextStyle(
                color: hx.tertiary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
