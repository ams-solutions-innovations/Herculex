import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/presentation/level_band_style.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Static explainer for the rank rules. The standards table is rendered from
/// [strengthStandards], the same list the evaluator reads.
class LevelSystemView extends ConsumerStatefulWidget {
  const LevelSystemView({super.key});

  @override
  ConsumerState<LevelSystemView> createState() => _LevelSystemViewState();
}

class _LevelSystemViewState extends ConsumerState<LevelSystemView> {
  BiologicalSex? _sex;

  @override
  Widget build(BuildContext context) {
    final sex =
        _sex ??
        ref.watch(profileProvider).valueOrNull?.sex ??
        BiologicalSex.male;

    return HxScreenShell(
      title: 'How levels work',
      children: [
        const SizedBox(height: HxSpace.x2),
        const _Section(
          icon: Icons.layers_rounded,
          title: 'Two parts to every rank',
          body:
              'The band — Novice, Intermediate, Advanced, Elite — comes from '
              'how strong you are. The rank inside it, I to V, comes from how '
              'much you train. Training alone cannot lift you out of a band, '
              'and strength alone does not fill one.',
        ),
        const SizedBox(height: HxSpace.x4),
        _Section(
          icon: Icons.fitness_center_rounded,
          title: 'Band = strength',
          body:
              'Enter a band by meeting its standard on any '
              '$liftsNeededPerBand benchmark lifts. Barbell and calisthenics '
              'mix freely. Barbell lifts use your estimated 1RM from any set '
              'of 1–12 reps, divided by bodyweight. Calisthenics counts '
              'strict, unassisted reps in one set.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: HxSpace.x4),
              HxTopTabs(
                labels: const ['Men', 'Women'],
                index: sex == BiologicalSex.female ? 1 : 0,
                onChanged: (i) {
                  Haptics.selection();
                  setState(() => _sex = BiologicalSex.values[i]);
                },
              ),
              const SizedBox(height: HxSpace.x3),
              _StandardsTable(sex: sex),
            ],
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        const _Section(
          icon: Icons.trending_up_rounded,
          title: 'Rank I–V = training',
          body:
              'Every finished workout earns training points: 40 for the '
              'session, 2 per working set up to 20, up to 15 for a heavy set '
              'relative to your bodyweight, and 10 for training again within '
              'one to four days. Each new band starts back at I. At V the bar '
              'stays full until your lifts open the next band.',
        ),
        const SizedBox(height: HxSpace.x4),
        const _Section(
          icon: Icons.fact_check_rounded,
          title: 'Where your numbers come from',
          body:
              'Every logged set of a benchmark lift counts, with or without a '
              'program. The strength check from onboarding counts too, but '
              'only up to Advanced: Elite needs both lifts logged in '
              'Herculex.',
        ),
        const SizedBox(height: HxSpace.x4),
        const _Section(
          icon: Icons.public_rounded,
          title: 'Top % of lifters and worldwide',
          body:
              'The percentages follow the same standards: Intermediate is the '
              'median lifter (top 50%), Advanced the top 20%, Elite the top '
              '5%, with a straight line between. Only logged sets count, so '
              'the number moves when you lift more. "Worldwide" also counts '
              'people who never train the lift, so it is a rough estimate '
              'for fun, not a measurement.',
        ),
        const SizedBox(height: HxSpace.x4),
        const _Section(
          icon: Icons.lock_rounded,
          title: 'Bands never go down',
          body:
              'Once you have earned a band it stays yours, even after a break '
              'or a change in bodyweight.',
        ),
        const SizedBox(height: HxSpace.x4),
        const _Section(
          icon: Icons.info_outline_rounded,
          title: 'Your rank is not your program level',
          body:
              'Programs set volume and effort from how you train — '
              'consistency, technique and how you respond — not from numbers '
              'on the bar. The rank is a game; the program follows you.',
        ),
        const SizedBox(height: HxSpace.x8),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.body,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: hx.primary),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x2),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hx.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

class _StandardsTable extends StatelessWidget {
  const _StandardsTable({required this.sex});

  final BiologicalSex sex;

  static const _bands = [
    LevelBand.intermediate,
    LevelBand.advanced,
    LevelBand.elite,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
    );

    Widget cell(String text, {TextStyle? style, bool alignStart = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: HxSpace.x2),
          child: Text(
            text,
            textAlign: alignStart ? TextAlign.start : TextAlign.center,
            style: style ?? theme.textTheme.bodySmall,
          ),
        );

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.6)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: hx.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      children: [
        TableRow(
          children: [
            cell('Lift', style: headerStyle, alignStart: true),
            for (final band in _bands)
              cell(
                band.label,
                style: headerStyle?.copyWith(color: band.color(context)),
              ),
          ],
        ),
        for (final standard in strengthStandards)
          TableRow(
            children: [
              cell(
                standard.lift.label,
                alignStart: true,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final band in _bands)
                cell(
                  _format(standard.lift, standard.listedThreshold(band, sex)),
                ),
            ],
          ),
      ],
    );
  }

  String _format(StrengthLift lift, double? value) {
    if (value == null) return '–';
    return switch (lift.measure) {
      StrengthMeasure.bodyweightRatio => '${value.toStringAsFixed(2)}×',
      StrengthMeasure.reps => '${value.round()}',
    };
  }
}
