part of '../labs_view.dart';

Widget _reports(BuildContext context, WidgetRef ref) {
  final repo = ref.watch(labsRepositoryProvider);
  final consent = ref.watch(labsConsentProvider);
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
  return HxCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your report library',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Two reports each month, after the 15th and the last day. Generated locally when your app next runs.',
        ),
        if (reports.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Your first report will appear after this reporting period closes.',
            ),
          ),
        for (final report in reports)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text('${report.period.id} · revision ${report.revision}'),
            subtitle: Text(
              report.partial ? 'Partial first period' : 'Completed period',
            ),
            trailing: const Icon(Icons.ios_share_rounded),
            onTap: () async {
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
                        ((context.findRenderObject() as RenderBox?)
                                ?.localToGlobal(Offset.zero) ??
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
            },
          ),
        TextButton.icon(
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
          icon: const Icon(Icons.refresh),
          label: const Text('Check for due reports'),
        ),
      ],
    ),
  );
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

IconData _icon(LabsCategory c) => switch (c) {
  LabsCategory.strength => Icons.fitness_center,
  LabsCategory.training => Icons.tune,
  LabsCategory.techniques => Icons.layers_outlined,
  LabsCategory.supplements => Icons.medication_outlined,
  LabsCategory.nutrition => Icons.restaurant_outlined,
  LabsCategory.fasting => Icons.timer_outlined,
  LabsCategory.sleep => Icons.bedtime_outlined,
  LabsCategory.physique => Icons.accessibility_new,
  LabsCategory.context => Icons.self_improvement,
};
