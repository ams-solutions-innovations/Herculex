part of '../labs_view.dart';

/// The newest report up front, the period being collected now, the rest of
/// the library, and the optional AI explanation.
class _ReportsTab extends ConsumerWidget {
  const _ReportsTab({required this.snapshot});

  /// The live analysis, for the optional AI explanation.
  final LabsSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final repo = ref.watch(labsRepositoryProvider);
    final canExport = ref.watch(labsPdfProvider).canSaveFiles;
    final consent = ref.watch(labsConsentProvider);
    final now = ref.watch(clockProvider).now();
    final reports =
        repo
            .records('report')
            .map(LabsSnapshot.fromJson)
            .where(
              (r) =>
                  consent.enabled &&
                  r.findings.every(
                    (f) => consent.categories.contains(f.category),
                  ),
            )
            .toList()
          ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    final latest = reports.firstOrNull;
    final library = reports.skip(1).toList();
    final collecting = LabsPeriod.containing(now);

    TextStyle sub(Color c) =>
        TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A report covers days 1–15 and 16–end of each month. Built on this '
          'device; PDFs stay private.',
          style: TextStyle(
            color: hx.secondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        if (latest != null)
          _HeroCard(
            padding: 18,
            radius: 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Pill('READY', color: hx.success),
                    const SizedBox(width: 6),
                    Text(
                      latest.partial
                          ? 'Partial first period · revision ${latest.revision}'
                          : 'Revision ${latest.revision}',
                      style: TextStyle(
                        color: hx.secondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _periodTitle(latest.period),
                  style: _labsDisplay(26, letterSpacing: -0.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (v, l) in [
                      ('${_reportFindings(latest)}', 'FINDINGS'),
                      ('${(_coverage(latest) * 100).round()}%', 'COVERAGE'),
                      (
                        '${latest.experiments.length}',
                        latest.experiments.length == 1
                            ? 'EXPERIMENT'
                            : 'EXPERIMENTS',
                      ),
                    ])
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v,
                              style: _labsDisplay(22, weight: FontWeight.w600),
                            ),
                            Text(
                              l,
                              style: TextStyle(
                                color: hx.secondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (canExport) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: HxRadius.mdAll,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: () => _sharePdf(context, ref, latest),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('Share PDF'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (latest != null) const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _labsCard(context, radius: 20),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_rounded, size: 20, color: hx.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _periodTitle(collecting),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Builds automatically on '
                      '${DateFormat('d MMMM').format(collecting.end)}',
                      style: sub(hx.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (library.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle('Library', size: 20),
          const SizedBox(height: 10),
          Container(
            decoration: _labsCard(context),
            child: Column(
              children: [
                for (var i = 0; i < library.length; i++)
                  InkWell(
                    onTap: canExport
                        ? () => _sharePdf(context, ref, library[i])
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : Border(top: BorderSide(color: hx.outlineVariant)),
                      ),
                      child: Row(
                        children: [
                          _IconTile(
                            icon: Icons.description_outlined,
                            color: hx.onSurfaceVariant,
                            fill: hx.surfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _periodTitle(library[i].period),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  library[i].partial
                                      ? 'Partial first period · '
                                            '${_reportFindings(library[i])} findings'
                                      : '${_reportFindings(library[i])} findings · '
                                            '${(_coverage(library[i]) * 100).round()}% coverage',
                                  style: sub(hx.secondary),
                                ),
                              ],
                            ),
                          ),
                          if (canExport)
                            Icon(
                              Icons.download_rounded,
                              size: 20,
                              color: hx.tertiary,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (consent.ai) ...[
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: hx.outlineVariant.withValues(alpha: 0.6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _explain(context, ref, snapshot),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 20,
                      color: hx.primaryText,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Explain with AI',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Optional · you preview the aggregate summary '
                            'before sending',
                            style: sub(hx.secondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: hx.secondary),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () async {
              try {
                await ref
                    .read(labsReportRunnerProvider)
                    .catchUp(ref.read(clockProvider).now());
                if (context.mounted) {
                  AppNotice.show(context, 'Report library is up to date.');
                }
              } catch (_) {
                if (context.mounted) {
                  AppNotice.show(
                    context,
                    'Report generation failed. You can retry.',
                    kind: AppNoticeKind.error,
                  );
                }
              }
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Check for due reports'),
          ),
        ),
      ],
    );
  }
}

/// "1–15 October" for a report period (end exclusive).
String _periodTitle(LabsPeriod p) {
  final last = p.end.subtract(const Duration(days: 1));
  return '${p.start.day}–${last.day} ${DateFormat('MMMM').format(p.start)}';
}

/// Findings that say something, not the "collecting data" placeholders.
int _reportFindings(LabsSnapshot r) =>
    r.findings.where((f) => f.delta != null || f.q != null).length;

Future<void> _sharePdf(
  BuildContext context,
  WidgetRef ref,
  LabsSnapshot report,
) async {
  final repo = ref.read(labsRepositoryProvider);
  try {
    final token = repo.consent.toJson().toString();
    final epoch = repo.privacyEpoch;
    final file = await ref.read(labsPdfProvider).save(report);
    if (repo.consent.toJson().toString() != token ||
        repo.privacyEpoch != epoch) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    if (context.mounted) {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Herculex Labs report',
        sharePositionOrigin:
            ((context.findRenderObject() as RenderBox?)?.localToGlobal(
                  Offset.zero,
                ) ??
                Offset.zero) &
            const Size(100, 100),
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppNotice.show(
        context,
        'Could not export this report. Please try again.',
        kind: AppNoticeKind.error,
      );
    }
  }
}

Future<void> _settings(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(labsRepositoryProvider),
      old = ref.read(labsConsentProvider);
  var enabled = old.enabled, history = old.history, ai = old.ai;
  final categories = {...old.categories};
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Your Labs, your choice'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Analyse selected records on this device. You can pause processing or delete Labs data at any time. Original trackers are unaffected.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Herculex Labs'),
                  value: enabled,
                  onChanged: (v) => set(() => enabled = v),
                ),
                for (final cat in LabsCategory.values)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(cat.label),
                    value: categories.contains(cat),
                    onChanged: (v) => set(
                      () => v == true
                          ? categories.add(cat)
                          : categories.remove(cat),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include older records'),
                  subtitle: const Text(
                    'Up to 180 days for exploratory comparisons. Old supplement doses remain unknown.',
                  ),
                  value: history,
                  onChanged: (v) => set(() => history = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow optional AI explanations'),
                  subtitle: const Text(
                    'Only on request, after previewing the exact summary. Raw logs, photos and notes stay on device.',
                  ),
                  value: ai,
                  onChanged: (v) => set(() => ai = v),
                ),
                TextButton(
                  onPressed: () async {
                    await repo.deleteReports();
                    await ref.read(labsPdfProvider).deleteFiles();
                    if (c.mounted) Navigator.pop(c);
                  },
                  child: const Text('Delete Labs reports'),
                ),
                TextButton(
                  onPressed: () async {
                    await repo.deleteAnalysis();
                    await ref.read(labsPdfProvider).deleteFiles();
                    if (c.mounted) Navigator.pop(c);
                  },
                  child: const Text('Delete all Labs data & disable'),
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
            onPressed: enabled && categories.isEmpty
                ? null
                : () async {
                    final narrowed =
                        !enabled ||
                        !categories.containsAll(old.categories) ||
                        (old.history && !history);
                    await repo.saveConsent(
                      LabsConsent(
                        enabled: enabled,
                        categories: categories,
                        history: history,
                        ai: ai,
                        since: old.since ?? ref.read(clockProvider).now(),
                      ),
                    );
                    if (narrowed) {
                      await repo.deleteReports();
                      await ref.read(labsPdfProvider).deleteFiles();
                    }
                    if (c.mounted) Navigator.pop(c);
                  },
            child: const Text('Save choices'),
          ),
        ],
      ),
    ),
  );
}
