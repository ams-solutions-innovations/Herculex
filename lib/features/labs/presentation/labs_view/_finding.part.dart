part of '../labs_view.dart';

/// A finding in one glance: which way it moved and in plain words.
Widget _simpleFindingTile(
  BuildContext context,
  LabsFinding f,
  LabsSnapshot snapshot,
) {
  final hx = context.hx;
  final delta = f.delta;
  final (icon, color) = switch (delta) {
    null => (Icons.insights_rounded, hx.primary),
    > 0 => (Icons.trending_up_rounded, hx.success),
    < 0 => (Icons.trending_down_rounded, hx.warning),
    _ => (Icons.trending_flat_rounded, hx.secondary),
  };
  return HxCard(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LabsFindingView(finding: f, snapshot: snapshot),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                f.category.label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: hx.secondary),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}

Widget _findingTile(
  BuildContext context,
  LabsFinding f,
  LabsSnapshot snapshot,
) => HxCard(
  onTap: () => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LabsFindingView(finding: f, snapshot: snapshot),
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(_icon(f.category), size: 20, color: context.hx.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(f.title, style: Theme.of(context).textTheme.titleSmall),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      const SizedBox(height: 8),
      Text(f.detail, maxLines: 3, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 8),
      Text(
        '${f.support} · ${f.n} observed days',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: context.hx.primary),
      ),
    ],
  ),
);

class LabsFindingView extends ConsumerWidget {
  const LabsFindingView({
    super.key,
    required this.finding,
    required this.snapshot,
  });
  final LabsFinding finding;
  final LabsSnapshot snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(labsConsentProvider);
    if (!consent.allows(finding.category) ||
        (!consent.history &&
            finding.points.any(
              (o) =>
                  o.at.isBefore(labsDay(consent.since ?? snapshot.generatedAt)),
            ))) {
      return const HxScreenShell(
        title: 'Labs',
        children: [Text('This category is no longer enabled.')],
      );
    }
    final f = finding;
    return _LabsTheme(
      child: HxScreenShell(
        title: 'Lab finding',
        children: [
          Text(f.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(f.detail, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
          if (f.points.length > 1)
            _LabsChart(points: f.points, events: snapshot.events, unit: f.unit),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Numbers & method'),
            subtitle: Text(f.support),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (f.before != null || f.after != null)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        'First half: ${f.before?.toStringAsFixed(1) ?? '—'} ${f.unit}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Second half: ${f.after?.toStringAsFixed(1) ?? '—'} ${f.unit}',
                      ),
                    ),
                    if (f.delta != null)
                      Chip(
                        label: Text(
                          'Change: ${f.delta! >= 0 ? '+' : ''}${f.delta!.toStringAsFixed(1)} ${f.unit}',
                        ),
                      ),
                  ],
                ),
              Text(
                '${f.n} observed days · ${(f.coverage * 100).round()}% calendar coverage',
              ),
              if (f.comparisonStart != null)
                Text(
                  '${labsDate(f.comparisonStart!)} → ${labsDate(f.comparisonEnd!)} (end exclusive)',
                ),
              if (f.q != null)
                Text(
                  'Adjusted q=${f.q!.toStringAsFixed(3)} · 95% association interval ${f.intervalLow!.toStringAsFixed(2)} to ${f.intervalHigh!.toStringAsFixed(2)}',
                ),
              const SizedBox(height: 20),
              Text(
                'How to read this',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final l in f.limitations)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('• $l'),
                ),
              const SizedBox(height: 16),
              Text(
                'Method: ${f.method}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Changes during this window',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final e in snapshot.events)
            ListTile(
              title: Text(e['title']),
              subtitle: Text(e['at'].toString().substring(0, 10)),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LabsChart extends StatelessWidget {
  const _LabsChart({
    required this.points,
    required this.events,
    required this.unit,
  });
  final List<LabsObservation> points;
  final List<Map<String, dynamic>> events;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final origin = points.first.at;
    double x(DateTime d) => DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(origin.year, origin.month, origin.day))
        .inDays
        .toDouble();
    final last = max(1.0, x(points.last.at));
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: last,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${labsDate(points[s.spotIndex].at)}\n${s.y.toStringAsFixed(1)} $unit',
                      TextStyle(color: context.hx.onSurface),
                    ),
                  )
                  .toList(),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 46),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: max(1, last / 3),
                getTitlesWidget: (v, m) => Text(
                  labsDate(
                    DateTime(origin.year, origin.month, origin.day + v.round()),
                  ).substring(5),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              for (final e in events)
                if (x(DateTime.parse(e['at'])) >= 0 &&
                    x(DateTime.parse(e['at'])) <= last)
                  VerticalLine(
                    x: x(DateTime.parse(e['at'])),
                    color: context.hx.tertiary,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points.map((p) => FlSpot(x(p.at), p.value)).toList(),
              color: context.hx.primary,
              barWidth: 2.5,
              isCurved: false,
              dotData: FlDotData(show: points.length < 35),
              belowBarData: BarAreaData(
                show: true,
                color: context.hx.primary.withValues(alpha: .08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
