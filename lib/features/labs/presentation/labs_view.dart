import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/labs/application/labs_providers.dart';
import 'package:herculex/features/labs/data/labs_ai_service.dart';
import 'package:herculex/features/labs/data/labs_repository.dart';
import 'package:herculex/features/labs/domain/labs_engine.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:share_plus/share_plus.dart';

part 'labs_view/_finding.part.dart';
part 'labs_view/_experiments.part.dart';
part 'labs_view/_logging.part.dart';
part 'labs_view/_library.part.dart';
part 'labs_view/_ai.part.dart';

class LabsEntryCard extends ConsumerWidget {
  const LabsEntryCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!labsEnabled) return const SizedBox.shrink();
    final consent = ref.watch(labsConsentProvider);
    final data = consent.enabled
        ? ref.watch(labsSnapshotProvider(30)).valueOrNull
        : null;
    return dashboardCard(
      accent: context.hx.primary,
      onTap: () => context.push(AppRoutes.labs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, color: context.hx.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Herculex Labs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            !consent.enabled
                ? 'Discover what works for you. Your data, your personal laboratory.'
                : data?.findings
                          .where((f) => f.delta != null || f.q != null)
                          .firstOrNull
                          ?.title ??
                      'Building your personal baseline',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            consent.enabled
                ? 'Local analysis · ${consent.categories.length} categories'
                : 'Optional · Private · Science informed',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class LabsView extends ConsumerStatefulWidget {
  const LabsView({super.key});
  @override
  ConsumerState<LabsView> createState() => _LabsViewState();
}

/// Labs leads with a short answer — what we found and one thing to do — and
/// keeps the research tooling (periods, categories, experiments, timeline,
/// report library, methods) under "More details".
class _LabsViewState extends ConsumerState<LabsView> {
  int days = 30;
  LabsCategory? category;
  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(labsConsentProvider);
    final theme = Theme.of(context);
    if (!labsEnabled) {
      return const HxScreenShell(
        title: 'Herculex Labs',
        children: [Text('Labs is disabled in this build.')],
      );
    }
    final result = consent.enabled
        ? ref.watch(labsSnapshotProvider(days))
        : null;
    final snapshot = result?.valueOrNull;
    return _LabsTheme(
      child: HxScreenShell(
        title: 'Herculex Labs',
        titleIcon: Icons.science_outlined,
        actions: [
          IconButton(
            tooltip: 'Privacy & categories',
            onPressed: () => _settings(context, ref),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
        children: [
          HxCard(
            accent: context.hx.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Learn what works for your body.',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  consent.enabled
                      ? snapshot == null
                            ? 'Analysing your last $days days on this device…'
                            : 'Last $days days · ${(_coverage(snapshot) * 100).round()}% of days have data · analysed on this device'
                      : 'Herculex connects your training, recovery and daily habits and shows you the patterns.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.hx.secondary,
                  ),
                ),
                if (!consent.enabled) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _settings(context, ref),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Set up my Labs'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!consent.enabled) ...[
            for (final (icon, text) in const [
              (
                Icons.insights_rounded,
                'See what changed in your training, sleep and body over time.',
              ),
              (
                Icons.lock_outline_rounded,
                'Private: everything is analysed on your phone.',
              ),
              (Icons.tune_rounded, 'You choose which categories are included.'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(icon, color: context.hx.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ] else
            result!.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Column(
                children: [
                  const Text(
                    'Labs could not load your records. Your existing logs are safe.',
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(labsSnapshotProvider(days)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
              data: (snapshot) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What we found', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (snapshot.findings.isEmpty)
                    const Text(
                      'Keep logging — your first findings appear after a couple of weeks of data.',
                    ),
                  for (final f in snapshot.findings.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _simpleFindingTile(context, f, snapshot),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: consent.allows(LabsCategory.context)
                        ? FilledButton.icon(
                            onPressed: () => _checkIn(context, ref),
                            icon: const Icon(Icons.mood_rounded),
                            label: const Text('Daily check-in'),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: () => _change(context, ref),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Record a change'),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'More details',
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: const Text(
                        'Time range, all findings, experiments, timeline and reports',
                      ),
                      children: [
                        _details(context, consent, snapshot),
                        const SizedBox(height: 16),
                        _reports(context, ref),
                        const SizedBox(height: 16),
                        ExpansionTile(
                          title: const Text('Methods & evidence'),
                          children: [
                            const ListTile(
                              title: Text(
                                'Descriptive comparisons: 3 observed days in each half. Exploratory signals: at least 8 weekly blocks, time adjustment and multiple-comparison correction. These screening thresholds do not establish causality.',
                              ),
                            ),
                            for (final e in labsSources.entries)
                              ListTile(
                                title: Text(e.key),
                                subtitle: SelectableText(e.value),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Everything below the headline findings, unchanged in substance.
  Widget _details(
    BuildContext context,
    LabsConsent consent,
    LabsSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in [15, 30, 90, 180])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$d days'),
                    selected: days == d,
                    onSelected: (_) => setState(() => days = d),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _quality(context, snapshot),
        if (consent.ai)
          TextButton.icon(
            onPressed: () => _explain(context, ref, snapshot),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Explain selected summary with AI'),
          ),
        const SizedBox(height: 16),
        Text('All findings', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Changes describe your records. Associations are exploratory and do not prove a cause.',
        ),
        const SizedBox(height: 12),
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
        for (final f in snapshot.findings.where(
          (f) => category == null || f.category == category,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _findingTile(context, f, snapshot),
          ),
        const SizedBox(height: 16),
        _experiments(context, ref, snapshot),
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
      ],
    );
  }
}

/// Average calendar coverage across recorded metrics, 0..1.
double _coverage(LabsSnapshot s) {
  final nonempty = s.findings
      .where((f) => f.points.isNotEmpty && f.p == null)
      .toList();
  return nonempty.isEmpty
      ? 0.0
      : nonempty.fold(0.0, (sum, f) => sum + f.coverage) / nonempty.length;
}

Widget _quality(BuildContext context, LabsSnapshot s) {
  final average = _coverage(s);
  return HxCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Data coverage', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: average),
        const SizedBox(height: 8),
        Text(
          '${(average * 100).round()}% average calendar coverage across recorded metrics',
        ),
        const SizedBox(height: 5),
        const Text(
          'Training is not expected every day. Coverage describes availability, not a health score.',
        ),
      ],
    ),
  );
}
