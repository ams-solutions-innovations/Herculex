import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/labs/application/labs_providers.dart';
import 'package:herculex/features/labs/data/labs_ai_service.dart';
import 'package:herculex/features/labs/data/labs_repository.dart';
import 'package:herculex/features/labs/domain/labs_engine.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:share_plus/share_plus.dart';

part 'labs_view/_kit.part.dart';
part 'labs_view/_overview.part.dart';
part 'labs_view/_finding.part.dart';
part 'labs_view/_experiments.part.dart';
part 'labs_view/_experiment_dialogs.part.dart';
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

/// Labs in three tabs: Overview (what we found), Experiments and Reports.
/// Before Labs is set up it shows what it does and one way in.
class _LabsViewState extends ConsumerState<LabsView> {
  static const _tabs = ['Overview', 'Experiments', 'Reports'];

  int days = 30;
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(labsConsentProvider);
    if (!labsEnabled) {
      return const HxScreenShell(
        title: 'Herculex Labs',
        children: [Text('Labs is disabled in this build.')],
      );
    }
    final result = consent.enabled
        ? ref.watch(labsSnapshotProvider(days))
        : null;
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
          if (result == null)
            ..._intro(context)
          else ...[
            HxTopTabs(
              labels: _tabs,
              index: tab,
              onChanged: (i) => setState(() => tab = i),
            ),
            const SizedBox(height: 16),
            result.when(
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
              data: (snapshot) => switch (tab) {
                1 => _ExperimentsTab(snapshot: snapshot),
                2 => _ReportsTab(snapshot: snapshot),
                _ => _OverviewTab(
                  consent: consent,
                  snapshot: snapshot,
                  days: days,
                  onDays: (d) => setState(() => days = d),
                  onOpenExperiments: () => setState(() => tab = 1),
                ),
              },
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Before consent: the promise, three reasons, and the way in.
  List<Widget> _intro(BuildContext context) {
    final hx = context.hx;
    return [
      _HeroCard(
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
              style: _labsDisplay(26, letterSpacing: -0.5, height: 1.1),
            ),
            const SizedBox(height: 10),
            Text(
              'Herculex connects your training, recovery and daily habits and '
              'shows you the patterns.',
              style: TextStyle(
                color: hx.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: HxRadius.lgAll),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () => _settings(context, ref),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Set up my Labs'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
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
              _IconTile(icon: icon, color: hx.primaryText),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
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
