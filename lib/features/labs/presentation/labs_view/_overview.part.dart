part of '../labs_view.dart';

/// The lead card: on-device promise, how much of the period has data, and
/// the period itself (15 / 30 / 90 / 180 days).
class _OverviewHero extends StatelessWidget {
  const _OverviewHero({
    required this.consent,
    required this.snapshot,
    required this.days,
    required this.onDays,
  });

  final LabsConsent consent;
  final LabsSnapshot? snapshot;
  final int days;
  final ValueChanged<int> onDays;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final coverage = snapshot == null ? null : _coverage(snapshot!);
    return _HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Kicker(
            icon: Icons.lock_outline_rounded,
            text: 'ON-DEVICE ANALYSIS',
            color: hx.primaryText,
          ),
          const SizedBox(height: 10),
          Text(
            'Learn what works for your body.',
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 26,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 50,
                      child: CircularProgressIndicator(
                        value: coverage,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: hx.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation(hx.primary),
                      ),
                    ),
                    Text(
                      coverage == null ? '…' : '${(coverage * 100).round()}%',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  snapshot == null
                      ? 'Analysing your last $days days on this device…'
                      : 'of the last $days days have data across '
                            '${consent.categories.length} '
                            '${consent.categories.length == 1 ? 'category' : 'categories'}.',
                  style: TextStyle(
                    color: hx.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final d in const [15, 30, 90, 180]) ...[
                if (d != 15) const SizedBox(width: 6),
                Expanded(
                  child: Material(
                    color: d == days
                        ? hx.primary.withValues(alpha: 0.2)
                        : hx.background.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: HxRadius.smAll,
                      side: BorderSide(
                        color: d == days ? hx.primary : hx.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: d == days ? null : () => onDays(d),
                      child: SizedBox(
                        height: 34,
                        child: Center(
                          child: Text(
                            '${d}d',
                            style: TextStyle(
                              color: d == days ? hx.onSurface : hx.secondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// What we found, the experiment you are running, one daily action, and the
/// research tooling folded away underneath.
class _OverviewTab extends ConsumerStatefulWidget {
  const _OverviewTab({
    required this.consent,
    required this.snapshot,
    required this.days,
    required this.onDays,
    required this.onOpenExperiments,
  });

  final LabsConsent consent;
  final LabsSnapshot snapshot;
  final int days;
  final ValueChanged<int> onDays;
  final VoidCallback onOpenExperiments;

  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  static const _headline = 4;
  bool showAll = false;
  LabsCategory? category;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final snapshot = widget.snapshot;
    final consent = widget.consent;
    final all = snapshot.findings;
    final shown = showAll
        ? all.where((f) => category == null || f.category == category).toList()
        : all.take(_headline).toList();
    final running = snapshot.experiments
        .where((e) => e['status'] == 'active')
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewHero(
          consent: consent,
          snapshot: snapshot,
          days: widget.days,
          onDays: widget.onDays,
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          'What we found',
          trailing: all.isEmpty
              ? null
              : '${min(_headline, all.length)} of ${all.length}',
        ),
        const SizedBox(height: 12),
        if (all.isEmpty)
          const Text(
            'Keep logging — your first findings appear after a couple of weeks of data.',
          ),
        if (showAll) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: category == null,
                onSelected: (_) => setState(() => category = null),
              ),
              for (final c in consent.categories)
                ChoiceChip(
                  label: Text(c.label),
                  selected: category == c,
                  onSelected: (_) => setState(() => category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        for (final f in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FindingCard(finding: f, snapshot: snapshot),
          ),
        if (all.length > _headline)
          TextButton(
            onPressed: () => setState(() {
              showAll = !showAll;
              category = null;
            }),
            child: Text(
              showAll ? 'Show fewer' : 'Show all ${all.length} findings',
            ),
          ),
        if (running != null) ...[
          const SizedBox(height: 10),
          _ExperimentTeaser(
            experiment: running,
            onTap: widget.onOpenExperiments,
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: consent.allows(LabsCategory.context)
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: HxRadius.lgAll),
                  ),
                  onPressed: () => _checkIn(context, ref),
                  icon: const Icon(Icons.mood_rounded),
                  label: const Text('Daily check-in'),
                )
              : FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: HxRadius.lgAll),
                  ),
                  onPressed: () => _change(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Record a change'),
                ),
        ),
        const SizedBox(height: 14),
        Text(
          "Changes describe your records. Associations are exploratory and don't prove a cause.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: hx.tertiary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('More details', style: theme.textTheme.titleMedium),
            subtitle: const Text('Data coverage, change timeline and methods'),
            children: [_details(context, snapshot)],
          ),
        ),
      ],
    );
  }

  Widget _details(BuildContext context, LabsSnapshot snapshot) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _quality(context, snapshot),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _change(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Record a change or diet period'),
        ),
        const SizedBox(height: 12),
        Text('Your change timeline', style: theme.textTheme.titleMedium),
        if (snapshot.events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Record when you change a routine, begin a supplement or adjust your diet.',
            ),
          ),
        for (final e in snapshot.events.reversed.take(12))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timeline),
            title: Text(e['title']),
            subtitle: Text(
              '${e['at'].toString().substring(0, 10)}${e['end'] == null ? '' : ' → ${e['end']}'}',
            ),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Methods & evidence'),
          children: [
            const ListTile(
              title: Text(
                'Descriptive comparisons: 3 observed days in each half. Exploratory signals: at least 8 weekly blocks, time adjustment and multiple-comparison correction. These screening thresholds do not establish causality.',
              ),
            ),
            for (final e in labsSources.entries)
              ListTile(title: Text(e.key), subtitle: SelectableText(e.value)),
          ],
        ),
      ],
    );
  }
}

/// One finding: category, how much it can carry, the change in one big
/// number and its recent shape.
class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, required this.snapshot});

  final LabsFinding finding;
  final LabsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final f = finding;
    final (icon, color) = _categoryStyle(f, hx);
    final association = f.q != null;
    final String headline;
    final String sub;
    final Color headlineColor;
    if (association) {
      headline =
          '${f.intervalLow!.toStringAsFixed(2)} to ${f.intervalHigh!.toStringAsFixed(2)}';
      sub = 'association interval · q = ${f.q!.toStringAsFixed(2)}';
      headlineColor = color;
    } else if (f.delta != null) {
      headline = _deltaText(f);
      sub = '${_num(f.before, f.unit)} → ${_num(f.after, f.unit)}';
      headlineColor = f.delta! > 0
          ? hx.success
          : f.delta! < 0
          ? hx.warning
          : hx.secondary;
    } else {
      headline = '';
      sub = f.detail;
      headlineColor = hx.secondary;
    }
    final values = [for (final p in f.points) p.value];
    final spark = values.length > 20
        ? values.sublist(values.length - 20)
        : values;

    return Material(
      color: hx.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: hx.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LabsFindingView(finding: f, snapshot: snapshot),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Kicker(
                      icon: icon,
                      text: _categoryLabel(f),
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SupportBadge(support: f.support),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (headline.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            headline,
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -1,
                                  height: 1.05,
                                  color: headlineColor,
                                ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hx.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (spark.length > 1) ...[
                    const SizedBox(width: 12),
                    _Sparkline(values: spark, color: color),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The running experiment in one line, with its phase progress. Opens the
/// Experiments tab.
class _ExperimentTeaser extends ConsumerWidget {
  const _ExperimentTeaser({required this.experiment, required this.onTap});

  final Map<String, dynamic> experiment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final purple = hx.domainRecovery;
    final phase = _ExperimentPhase.of(
      experiment,
      ref.watch(clockProvider).now(),
    );
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: purple.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.6],
            colors: [purple.withValues(alpha: 0.14), hx.surfaceContainerLowest],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: purple,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Kicker(
                        text: 'EXPERIMENT · ${phase.label.toUpperCase()}',
                        color: Color.lerp(purple, Colors.white, 0.4),
                      ),
                    ),
                    Text(
                      phase.dayText,
                      style: TextStyle(
                        color: hx.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${experiment['title']} → ${labsMetricLabels[experiment['metric']] ?? experiment['metric']}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _PhaseBar(phase: phase, height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
