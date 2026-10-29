part of '../labs_view.dart';

/// One finding in full: the change, the two halves it compares, how much
/// data it stands on, and how to read it.
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
    final hx = context.hx;
    final f = finding;
    final (icon, color) = _categoryStyle(f, hx);
    final association = f.q != null;
    final sorted = [...f.points]..sort((a, b) => a.at.compareTo(b.at));
    final from =
        f.comparisonStart ??
        (sorted.isEmpty ? snapshot.period.start : labsDay(sorted.first.at));
    final to =
        f.comparisonEnd ??
        (sorted.isEmpty
            ? snapshot.period.end
            : labsDay(sorted.last.at).add(const Duration(days: 1)));
    final split = association
        ? null
        : from.add(Duration(hours: to.difference(from).inHours ~/ 2));
    final firstN = split == null
        ? 0
        : sorted.where((p) => p.at.isBefore(split)).length;
    final secondN = sorted.length - firstN;
    final totalDays = max(1, to.difference(from).inDays);

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
      sub = f.support;
      headlineColor = hx.secondary;
    }

    final stats = association
        ? [
            ('LOW', f.intervalLow!.toStringAsFixed(2), 'interval'),
            ('HIGH', f.intervalHigh!.toStringAsFixed(2), 'interval'),
            ('ADJUSTED Q', f.q!.toStringAsFixed(3), '${f.n} days'),
          ]
        : [
            ('FIRST HALF', _num(f.before, f.unit), '$firstN days'),
            ('SECOND HALF', _num(f.after, f.unit), '$secondN days'),
            (
              'CHANGE',
              f.delta == null ? '—' : _deltaText(f),
              f.unit.isEmpty ? 'change' : f.unit,
            ),
          ];
    final interval = association
        ? '95% association interval ${f.intervalLow!.toStringAsFixed(2)} to '
              '${f.intervalHigh!.toStringAsFixed(2)}, corrected across '
              'questions.'
        : f.intervalLow != null && f.intervalHigh != null
        ? '95% interval ${_num(f.intervalLow, f.unit)} to '
              '${_num(f.intervalHigh, f.unit)}.'
        : "Training isn't expected every day, so coverage isn't a score.";
    final method = [
      ...switch (f.method) {
        'weekly-detrended-block-permutation-bh-v1' => const [
          'Weekly blocks',
          'Time-detrended',
          'Multiple-comparison corrected',
        ],
        'diet-period-descriptive-v1' => const ['Diet period comparison'],
        _ => const ['First vs second half'],
      },
      '${f.n} observed days',
    ];
    final windowEvents = [
      for (final e in snapshot.events)
        if (!DateTime.parse(e['at']).isBefore(from) &&
            DateTime.parse(e['at']).isBefore(to))
          e,
    ];

    TextStyle small(Color c) =>
        TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600);

    return _LabsTheme(
      child: HxScreenShell(
        title: 'Finding',
        titleIcon: Icons.science_outlined,
        children: [
          Row(
            children: [
              Flexible(
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
          const SizedBox(height: 8),
          Text(
            f.title,
            style: _labsDisplay(24, letterSpacing: -0.4, height: 1.15),
          ),
          if (headline.isNotEmpty) ...[
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                headline,
                maxLines: 1,
                style: _labsDisplay(
                  52,
                  weight: FontWeight.w600,
                  letterSpacing: -2,
                  height: 1,
                  color: headlineColor,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(
              color: hx.secondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sorted.length > 1) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
              decoration: _labsCard(context, radius: 24),
              child: _SplitDotsChart(
                points: sorted,
                split: split,
                from: from,
                to: to,
                before: association ? null : f.before,
                after: association ? null : f.after,
                color: color,
                leftLabel: split == null ? '' : _rangeLabel(from, split),
                rightLabel: split == null ? '' : _rangeLabel(split, to),
                height: 180,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            decoration: _labsCard(context, radius: 20),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < stats.length; i++)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: i == 0
                              ? null
                              : Border(
                                  left: BorderSide(color: hx.outlineVariant),
                                ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stats[i].$1,
                              style: TextStyle(
                                color: hx.secondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                stats[i].$2,
                                style: _labsDisplay(
                                  19,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              stats[i].$3,
                              style: TextStyle(
                                color: hx.tertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: _labsCard(context, radius: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Data coverage',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${f.n} of $totalDays days',
                      style: TextStyle(
                        color: hx.secondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: f.coverage.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: hx.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  interval,
                  style: small(hx.secondary).copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _Kicker(text: 'HOW TO READ THIS'),
          const SizedBox(height: 8),
          Text(
            f.detail,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          for (final l in f.limitations)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $l', style: small(hx.secondary)),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in method)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: hx.surfaceContainer,
                    borderRadius: HxRadius.pillAll,
                    border: Border.all(color: hx.outlineVariant),
                  ),
                  child: Text(
                    m,
                    style: TextStyle(
                      color: hx.onSurfaceVariant,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (windowEvents.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _Kicker(text: 'CHANGES DURING THIS WINDOW'),
            const SizedBox(height: 4),
            for (final e in windowEvents)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${e['at'].toString().substring(0, 10)} · ${e['title']}',
                  style: small(hx.onSurfaceVariant),
                ),
              ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Color.lerp(
                  hx.domainRecovery,
                  Colors.white,
                  0.4,
                ),
                backgroundColor: hx.domainRecovery.withValues(alpha: 0.12),
                side: BorderSide(
                  color: hx.domainRecovery.withValues(alpha: 0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: () => _startExperiment(context, ref),
              icon: const Icon(Icons.science_outlined, size: 20),
              label: const Text('Test this with an experiment'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// "1–15 Oct" for a half-open day range.
String _rangeLabel(DateTime from, DateTime to) {
  final last = labsDay(to).subtract(const Duration(days: 1));
  final end = last.isBefore(from) ? from : last;
  return from.month == end.month
      ? '${from.day}–${DateFormat('d MMM').format(end)}'
      : '${DateFormat('d MMM').format(from)} – ${DateFormat('d MMM').format(end)}';
}

/// Daily values as dots, split into two halves with each half's mean as a
/// dashed line. Without a split every dot takes the accent and no means are
/// drawn.
class _SplitDotsChart extends StatelessWidget {
  const _SplitDotsChart({
    required this.points,
    required this.split,
    required this.from,
    required this.to,
    required this.before,
    required this.after,
    required this.color,
    required this.leftLabel,
    required this.rightLabel,
    required this.height,
  });

  final List<LabsObservation> points;
  final DateTime? split;
  final DateTime from, to;
  final double? before, after;
  final Color color;
  final String leftLabel, rightLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SplitDotsPainter(
          chart: this,
          grid: hx.surfaceVariant,
          divider: hx.outline,
          muted: hx.tertiary,
          baseline: hx.secondary,
          labelStyle: TextStyle(
            color: hx.tertiary,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: Theme.of(context).textTheme.labelSmall?.fontFamily,
          ),
        ),
      ),
    );
  }
}

class _SplitDotsPainter extends CustomPainter {
  _SplitDotsPainter({
    required this.chart,
    required this.grid,
    required this.divider,
    required this.muted,
    required this.baseline,
    required this.labelStyle,
  });

  final _SplitDotsChart chart;
  final Color grid, divider, muted, baseline;
  final TextStyle labelStyle;

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash) {
    final length = (b - a).distance;
    if (length == 0) return;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += dash * 1.8) {
      canvas.drawLine(a + dir * d, a + dir * min(d + dash, length), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = chart;
    final hasLabels = c.leftLabel.isNotEmpty || c.rightLabel.isNotEmpty;
    final plotBottom = size.height - (hasLabels ? 22 : 6);
    const plotTop = 8.0;
    const padX = 6.0;
    final values = [for (final p in c.points) p.value, ?c.before, ?c.after];
    var lo = values.reduce(min), hi = values.reduce(max);
    final pad = (hi - lo) == 0 ? 1.0 : (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    final span = max(1, c.to.difference(c.from).inMinutes).toDouble();
    double x(DateTime d) =>
        padX +
        (size.width - padX * 2) *
            (d.difference(c.from).inMinutes / span).clamp(0.0, 1.0);
    double y(double v) =>
        plotTop + (plotBottom - plotTop) * (1 - (v - lo) / (hi - lo));

    final gridPaint = Paint()..color = grid;
    for (final t in const [0.2, 0.5, 0.8]) {
      final gy = plotTop + (plotBottom - plotTop) * t;
      canvas.drawLine(
        Offset(padX, gy),
        Offset(size.width - padX, gy),
        gridPaint,
      );
    }

    final split = c.split;
    final sx = split == null ? null : x(split);
    if (sx != null) {
      _dashed(
        canvas,
        Offset(sx, plotTop),
        Offset(sx, plotBottom),
        Paint()
          ..color = divider
          ..strokeWidth = 1,
        3,
      );
    }
    final meanPaint = Paint()..strokeWidth = 2;
    if (sx != null && c.before != null) {
      _dashed(
        canvas,
        Offset(padX, y(c.before!)),
        Offset(sx - 3, y(c.before!)),
        meanPaint..color = baseline,
        6,
      );
    }
    if (sx != null && c.after != null) {
      _dashed(
        canvas,
        Offset(sx + 3, y(c.after!)),
        Offset(size.width - padX, y(c.after!)),
        meanPaint..color = c.color,
        6,
      );
    }
    for (final p in c.points) {
      final early = split != null && p.at.isBefore(split);
      canvas.drawCircle(
        Offset(x(p.at), y(p.value)),
        4.5,
        Paint()..color = early ? muted : c.color,
      );
    }
    if (hasLabels) {
      void label(String text, double left) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: labelStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: size.width / 2 - 8);
        tp.paint(canvas, Offset(left, size.height - tp.height));
      }

      label(c.leftLabel, padX);
      if (sx != null) label(c.rightLabel, sx + 6);
    }
  }

  @override
  bool shouldRepaint(_SplitDotsPainter old) =>
      old.chart != chart || old.grid != grid || old.muted != muted;
}
