import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../domain/set_type.dart';

/// Result of the set-type menu: a type plus its serialized metadata.
class SetTypeSelection {
  final SetType type;
  final String? metaJson;
  final bool delete;
  final bool? isWarmup;

  const SetTypeSelection(this.type, [this.metaJson, this.isWarmup = false])
      : delete = false;

  const SetTypeSelection.delete()
      : type = SetType.standard,
        metaJson = null,
        delete = true,
        isWarmup = null;

  const SetTypeSelection.warmup([this.isWarmup = true])
      : type = SetType.standard,
        metaJson = null,
        delete = false;
}

/// Category grouping for the set types.
enum SetTypeCategory {
  basic('Basic & Warmup', 'Basic & Warmup'),
  hypertrophy('Hypertrophy & Intensity', 'Hypertrophy & Intensity'),
  timed('Timed & Functional', 'Timed & Functional');

  final String title;
  final String subtitle;
  const SetTypeCategory(this.title, this.subtitle);
}

/// Detailed informational metadata for each set type in Herculex.
class SetTypeInfo {
  final SetType? type;
  final bool isWarmup;
  final String id;
  final String label;
  final String badge;
  final SetTypeCategory category;
  final String shortDescription;
  final String fullExplanation;
  final String howMeasuredInApp;
  final String? volumeTonnageRule;
  final String? cnsRule;
  final Color accentColor;
  final IconData? icon;

  const SetTypeInfo({
    required this.type,
    this.isWarmup = false,
    required this.id,
    required this.label,
    required this.badge,
    required this.category,
    required this.shortDescription,
    required this.fullExplanation,
    required this.howMeasuredInApp,
    this.volumeTonnageRule,
    this.cnsRule,
    required this.accentColor,
    this.icon,
  });

  static final List<SetTypeInfo> all = [
    // ── Basic & Prep ────────────────────────────────────────────────────────
    const SetTypeInfo(
      type: SetType.standard,
      id: 'standard',
      label: 'Standard Set',
      badge: '—',
      category: SetTypeCategory.basic,
      shortDescription: 'Classic working set with full range of motion.',
      fullExplanation:
          'Standard working set with controlled tempo and full range of motion. '
          'Represents the core foundation of your training volume.',
      howMeasuredInApp:
          '100% of weight and reps are added to total working volume and tonnage.',
      volumeTonnageRule: '1.0× Working volume (100% load)',
      cnsRule: '1.0× Standard CNS load',
      accentColor: Color(0xFF42A5F5),
      icon: Icons.fitness_center,
    ),
    const SetTypeInfo(
      type: null,
      isWarmup: true,
      id: 'warmup',
      label: 'Warmup Set',
      badge: 'W',
      category: SetTypeCategory.basic,
      shortDescription: 'Preparatory set to warm up joints and muscles.',
      fullExplanation:
          'Warm-up set with lighter weight designed to prepare joints, muscles, '
          'and central nervous system for working sets while minimizing injury risk.',
      howMeasuredInApp:
          'Completely excluded from working volume and tonnage. Marked with flame icon 🔥 or "W" badge.',
      volumeTonnageRule: '0% Working volume (does not skew heavy set stats)',
      cnsRule: 'Negligible CNS fatigue',
      accentColor: Colors.orange,
      icon: Icons.local_fire_department,
    ),

    // ── Hypertrophy & Intensity ─────────────────────────────────────────────
    const SetTypeInfo(
      type: SetType.drop,
      id: 'drop',
      label: 'Drop Set',
      badge: 'D',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Immediate weight reduction (e.g. -20%) with zero rest to new failure.',
      fullExplanation:
          'Upon reaching muscular failure, immediately reduce weight by 10–30% '
          'and continue reps until subsequent failure for maximal metabolic stress.',
      howMeasuredInApp:
          'Allows quick selection of drop percentage (-20%, -10%, -30%). All executed reps are tracked in volume with corresponding reduced weight.',
      volumeTonnageRule: '100% of logged weight and reps',
      cnsRule: 'Elevated metabolic stress',
      accentColor: Color(0xFFE57373),
    ),
    const SetTypeInfo(
      type: SetType.downSets,
      id: 'down_sets',
      label: 'Down Sets',
      badge: 'DN',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Set chain with identical weight where reps decrease by 1 each set.',
      fullExplanation:
          'Sequential set protocol with constant weight where each successive set performs '
          '1 fewer repetition (e.g. 10 → 9 → 8 → 7...). '
          'Denoted as D1, D2, D3...',
      howMeasuredInApp:
          'Long-pressing the Down Set badge automatically generates and prefills the complete set chain.',
      volumeTonnageRule: 'Each set is recorded as full working volume',
      cnsRule: 'Progressive fatigue accumulation',
      accentColor: Color(0xFFBA68C8),
    ),
    const SetTypeInfo(
      type: SetType.restPause,
      id: 'rest_pause',
      label: 'Rest-Pause',
      badge: 'RP',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Main set to failure, 15-20s pause, then 2-3 mini-sets.',
      fullExplanation:
          'Perform set to failure, take a very brief pause (15 to 20 seconds), '
          'and immediately resume for 2–4 extra repetitions.',
      howMeasuredInApp:
          'Tracks total repetitions and pause duration in seconds. Algorithm factors in heightened fatigue.',
      volumeTonnageRule: '1.0× Tonnage',
      cnsRule: '1.2× Increased central nervous system (CNS) load',
      accentColor: Color(0xFFFFB74D),
    ),
    const SetTypeInfo(
      type: SetType.pause,
      id: 'pause',
      label: 'Pause Reps',
      badge: 'PA',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Static isometric hold for 2–5s in the hardest portion of the movement.',
      fullExplanation:
          'Each rep incorporates an intentional hold at the bottom/inflection point (2s, 3s, or 5s), '
          'eliminating stretch-shortening cycle elasticity and enhancing motor control.',
      howMeasuredInApp:
          'Quick pause duration selection (2s, 3s, 5s) stored directly in set metadata.',
      volumeTonnageRule: '1.0× Tonnage',
      cnsRule: '1.1× CNS load',
      accentColor: Color(0xFF4FC3F7),
    ),
    const SetTypeInfo(
      type: SetType.myoReps,
      id: 'myo_reps',
      label: 'Myo Reps',
      badge: 'MY',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Activation set + 3-5 micro-sets with 5 deep breaths rest.',
      fullExplanation:
          'One activation set (10–15 reps to failure or RPE 9), '
          'followed by brief rest (5 deep breaths) and 3–5 mini-sets of 3–5 reps each.',
      howMeasuredInApp:
          'Records the total count of effective high-threshold repetitions.',
      volumeTonnageRule: '100% effective repetitions',
      cnsRule: 'Optimized for high mechanical tension',
      accentColor: Color(0xFF81C784),
    ),
    const SetTypeInfo(
      type: SetType.partials,
      id: 'partials',
      label: 'Partials',
      badge: 'P½',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Partial range-of-motion reps after achieving full range failure.',
      fullExplanation:
          'Perform partial reps (e.g. top or bottom half only) '
          'when complete full-ROM repetitions can no longer be completed.',
      howMeasuredInApp:
          'Because mechanical work is halved, Herculex automatically applies a 0.5× multiplier to avoid inflating tonnage.',
      volumeTonnageRule: '0.5× Effective volume (50% tonnage adjustment)',
      cnsRule: 'Local muscular exhaustion',
      accentColor: Color(0xFFFF8A65),
    ),
    const SetTypeInfo(
      type: SetType.negatives,
      id: 'negatives',
      label: 'Negatives',
      badge: 'N',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Slow and controlled eccentric lowering phase (3–5s).',
      fullExplanation:
          'Emphasis on the eccentric (lowering) phase of movement lasting 3–5 seconds. '
          'Commonly used to overload and break through strength plateaus.',
      howMeasuredInApp:
          'Volume adjusted with 0.75× factor and elevated CNS fatigue calculation (1.3×).',
      volumeTonnageRule: '0.75× Tonnage factor',
      cnsRule: '1.3× Very high CNS load and fiber micro-trauma',
      accentColor: Color(0xFF9575CD),
    ),
    const SetTypeInfo(
      type: SetType.forced,
      id: 'forced',
      label: 'Forced Reps',
      badge: 'F',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Full reps + partner-assisted extra repetitions.',
      fullExplanation:
          'After achieving full concentric failure under own strength, a spotter assists '
          'just enough to surpass the sticking point for extra forced repetitions.',
      howMeasuredInApp:
          'Log unassisted reps in standard field, and add assisted reps as (+ Forced) badges.',
      volumeTonnageRule: '1.0× Tonnage for full and forced reps',
      cnsRule: '1.3× Maximal neural system stimulation',
      accentColor: Color(0xFFE53935),
    ),
    const SetTypeInfo(
      type: SetType.cheat,
      id: 'cheat',
      label: 'Cheat Reps',
      badge: 'CR',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Full reps + extra reps utilizing controlled body momentum.',
      fullExplanation:
          'When strict form fails, utilize slight controlled body english '
          'to pass the sticking point while sustaining heavy eccentric resistance.',
      howMeasuredInApp:
          'Log strict reps in standard field, and add momentum reps as (+ Cheat) badges.',
      volumeTonnageRule: '0.85× Tonnage factor for cheat reps',
      cnsRule: '1.25× Increased neural load',
      accentColor: Color(0xFFFF7043),
    ),
    const SetTypeInfo(
      type: SetType.pyramid,
      id: 'pyramid',
      label: 'Pyramid Set',
      badge: 'PY',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Increasing weight and decreasing reps across consecutive sets.',
      fullExplanation:
          'Classic pyramid (or reverse pyramid): each sequential set uses higher weight with fewer repetitions.',
      howMeasuredInApp: 'Standard measurement of weight and reps for each pyramid step.',
      volumeTonnageRule: '1.0× Tonnage',
      cnsRule: '1.0× Standard',
      accentColor: Color(0xFF4DD0E1),
    ),
    const SetTypeInfo(
      type: SetType.twentyOnes,
      id: 'twenty_ones',
      label: '21s',
      badge: '21',
      category: SetTypeCategory.hypertrophy,
      shortDescription: '7 lower + 7 upper + 7 full range reps without rest.',
      fullExplanation:
          'Classic 21-rep protocol in one set: 7 reps lower half, '
          '7 reps upper half, and 7 complete full-ROM repetitions.',
      howMeasuredInApp: 'Recorded as 21 reps at the chosen weight.',
      volumeTonnageRule: '1.0× Tonnage',
      cnsRule: 'Extreme muscular pump',
      accentColor: Color(0xFFAED581),
    ),
    const SetTypeInfo(
      type: SetType.mechanicalDrop,
      id: 'mechanical_drop',
      label: 'Mechanical Drop Set',
      badge: 'MD',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Change grip or body angle instead of reducing weight.',
      fullExplanation:
          'Upon reaching failure, immediately modify biomechanical leverage '
          '(e.g. from narrow to wide grip or adjusting bench incline) to continue the set.',
      howMeasuredInApp: 'Full load tracked under modified biomechanics.',
      volumeTonnageRule: '1.0× Tonnage',
      cnsRule: 'Elevated metabolic stress',
      accentColor: Color(0xFFFFD54F),
    ),
    const SetTypeInfo(
      type: SetType.preExhaustion,
      id: 'pre_exhaustion',
      label: 'Pre-Exhaustion',
      badge: 'PE',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'Isolation exercise performed immediately prior to compound lift.',
      fullExplanation:
          'Fatigue target muscle first with an isolation movement (e.g. pec deck flyes), '
          'then immediately transition to a compound movement (e.g. bench press).',
      howMeasuredInApp: 'Standard sequential logging of both movements.',
      volumeTonnageRule: '1.0× Tonnage',
      cnsRule: 'Increased primary muscle recruitment',
      accentColor: Color(0xFF90A4AE),
    ),
    const SetTypeInfo(
      type: SetType.volume20x60,
      id: 'volume_20x60',
      label: '20 Sets @ 60%',
      badge: '20x',
      category: SetTypeCategory.hypertrophy,
      shortDescription: 'German Volume Training variation (20 sets at 60% 1RM).',
      fullExplanation:
          'High-volume density protocol consisting of 20 sets at 60% of 1RM '
          'with strict, timed rest intervals.',
      howMeasuredInApp: 'App records % of 1RM parameter and total accumulated volume.',
      volumeTonnageRule: 'High volume at fixed resistance',
      cnsRule: 'High cumulative fatigue',
      accentColor: Color(0xFF7986CB),
    ),

    // ── Timed & Functional ──────────────────────────────────────────────────
    const SetTypeInfo(
      type: SetType.amrap,
      id: 'amrap',
      label: 'AMRAP',
      badge: 'AM',
      category: SetTypeCategory.timed,
      shortDescription: 'As Many Reps As Possible within a specified time cap.',
      fullExplanation:
          'Complete as many repetitions or rounds as possible within a designated time limit (e.g. 60 seconds).',
      howMeasuredInApp: 'Stores time cap (capSeconds) and completed reps/rounds.',
      volumeTonnageRule: 'Tonnage calculated from all completed repetitions',
      cnsRule: 'Cardiovascular and anaerobic demand',
      accentColor: Color(0xFF26A69A),
    ),
    const SetTypeInfo(
      type: SetType.emom,
      id: 'emom',
      label: 'EMOM',
      badge: 'EM',
      category: SetTypeCategory.timed,
      shortDescription: 'Every Minute on the Minute for target repetitions.',
      fullExplanation:
          'Start a new set at the top of every minute with prescribed reps; '
          'remaining time in each minute serves as rest.',
      howMeasuredInApp: 'Tracks total minutes and repetitions per minute interval.',
      volumeTonnageRule: 'Each minute recorded as completed mini-set',
      cnsRule: 'Pacing and anaerobic work capacity',
      accentColor: Color(0xFF00ACC1),
    ),
    const SetTypeInfo(
      type: SetType.forTime,
      id: 'for_time',
      label: 'For Time',
      badge: 'FT',
      category: SetTypeCategory.timed,
      shortDescription: 'Complete prescribed work in the shortest time possible.',
      fullExplanation:
          'Goal is to complete target repetitions or routine as fast as possible. '
          'Stopwatch tracks total elapsed duration.',
      howMeasuredInApp: 'Records elapsed time in seconds and completion status.',
      volumeTonnageRule: '1.0× Tonnage + time score',
      cnsRule: 'Maximal pacing intensity',
      accentColor: Color(0xFF00897B),
    ),
  ];

  static SetTypeInfo? find(SetType? type, {bool isWarmup = false}) {
    if (isWarmup) {
      return all.firstWhere((i) => i.isWarmup, orElse: () => all[1]);
    }
    return all.firstWhere((i) => i.type == type, orElse: () => all[0]);
  }
}

/// One-tap set-type switcher. Tapping a set's index cell opens this sheet;
/// selection is instantaneous, with inline quick-picks and squircle cards.
class SetTypeMenu extends StatelessWidget {
  final SetType current;
  final bool isWarmup;

  const SetTypeMenu({
    super.key,
    required this.current,
    this.isWarmup = false,
  });

  static Future<SetTypeSelection?> show(
    BuildContext context, {
    required SetType current,
    bool isWarmup = false,
  }) {
    return showModalBottomSheet<SetTypeSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetTypeMenu(current: current, isWarmup: isWarmup),
    );
  }

  /// Short badge shown in the set-index cell (e.g. "D" for drop set, "W" for warmup).
  static String badge(SetType type) => switch (type) {
    SetType.standard => '',
    SetType.drop => 'D',
    SetType.restPause => 'RP',
    SetType.partials => 'P½',
    SetType.myoReps => 'MY',
    SetType.pyramid => 'PY',
    SetType.forced => 'F',
    SetType.cheat => 'CR',
    SetType.negatives => 'N',
    SetType.pause => 'PA',
    SetType.mechanicalDrop => 'MD',
    SetType.giant => 'G',
    SetType.preExhaustion => 'PE',
    SetType.twentyOnes => '21',
    SetType.volume20x60 => '20x',
    SetType.downSets => 'DN',
    SetType.amrap => 'AM',
    SetType.emom => 'EM',
    SetType.forTime => 'FT',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group items by category
    final basicItems = SetTypeInfo.all
        .where((i) => i.category == SetTypeCategory.basic)
        .toList();
    final hypertrophyItems = SetTypeInfo.all
        .where((i) => i.category == SetTypeCategory.hypertrophy)
        .toList();
    final timedItems = SetTypeInfo.all
        .where((i) => i.category == SetTypeCategory.timed)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color:
              theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Header with Title + Question Mark Explanation Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Set Type',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                SetTypesGuideSheet.show(
                                  context,
                                  initialHighlight: isWarmup
                                      ? 'warmup'
                                      : current.id,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.help_outline_rounded,
                                      size: 15,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Guide & Info',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select a set type by tapping a squircle card',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),

            // Scrollable List of Squircle Categories and Items
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // Category 1: Basic & Warmup
                  _CategoryHeader(category: SetTypeCategory.basic),
                  const SizedBox(height: 6),
                  for (final item in basicItems)
                    _SquircleSetTypeTile(
                      info: item,
                      isSelected: item.isWarmup
                          ? isWarmup
                          : (!isWarmup && item.type == current),
                      onTap: () {
                        if (item.isWarmup) {
                          Navigator.of(context).pop(const SetTypeSelection.warmup(true));
                        } else {
                          Navigator.of(context).pop(SetTypeSelection(item.type!));
                        }
                      },
                      onHelpTap: () => SetTypeDetailDialog.show(context, item),
                    ),

                  const SizedBox(height: 14),

                  // Category 2: Hypertrophy & Intensity
                  _CategoryHeader(category: SetTypeCategory.hypertrophy),
                  const SizedBox(height: 6),
                  for (final item in hypertrophyItems)
                    _SquircleSetTypeTile(
                      info: item,
                      isSelected: !isWarmup && item.type == current,
                      onTap: () => Navigator.of(context).pop(SetTypeSelection(item.type!)),
                      onHelpTap: () => SetTypeDetailDialog.show(context, item),
                    ),

                  const SizedBox(height: 14),

                  // Category 3: Timed & Functional
                  _CategoryHeader(category: SetTypeCategory.timed),
                  const SizedBox(height: 6),
                  for (final item in timedItems)
                    _SquircleSetTypeTile(
                      info: item,
                      isSelected: !isWarmup && item.type == current,
                      onTap: () => Navigator.of(context).pop(SetTypeSelection(item.type!)),
                      onHelpTap: () => SetTypeDetailDialog.show(context, item),
                    ),

                  const SizedBox(height: 14),

                  // Delete Set Action Squircle
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).pop(const SetTypeSelection.delete()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Delete this set',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Permanently remove this set row from exercise',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: Colors.redAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category section title in the SetTypeMenu list.
class _CategoryHeader extends StatelessWidget {
  final SetTypeCategory category;
  const _CategoryHeader({required this.category});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Text(
            category.title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: AppColors.outlineVariant.withValues(alpha: 0.4),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A squircle tile representing a single Set Type option.
class _SquircleSetTypeTile extends StatefulWidget {
  final SetTypeInfo info;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onHelpTap;

  const _SquircleSetTypeTile({
    required this.info,
    required this.isSelected,
    required this.onTap,
    required this.onHelpTap,
  });

  @override
  State<_SquircleSetTypeTile> createState() => _SquircleSetTypeTileState();
}

class _SquircleSetTypeTileState extends State<_SquircleSetTypeTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final isSelected = widget.isSelected;

    final _QuickPickConfig? quickConfig = switch (info.type) {
      SetType.pause => const _QuickPickConfig(
          metaKey: 'pauseSeconds',
          defaultValue: 3,
          defaultLabel: '3s',
          alternates: [2, 5],
          alternateLabel: _secondsLabel,
        ),
      SetType.drop => const _QuickPickConfig(
          metaKey: 'dropPercent',
          defaultValue: 20,
          defaultLabel: '20%',
          alternates: [10, 30],
          alternateLabel: _dropPercentLabel,
        ),
      _ => null,
    };

    void confirmQuick(int value) {
      Navigator.of(context).pop(
        SetTypeSelection(
          info.type!,
          jsonEncode({quickConfig!.metaKey: value}),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: isSelected
            ? info.accentColor.withValues(alpha: 0.12)
            : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? info.accentColor
              : AppColors.outlineVariant.withValues(alpha: 0.2),
          width: isSelected ? 1.8 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: quickConfig != null && isSelected
                ? () => confirmQuick(quickConfig.defaultValue)
                : widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Badge / Icon Squircle
                  _SquircleBadge(
                    badge: info.badge,
                    icon: info.icon,
                    accentColor: info.accentColor,
                    selected: isSelected,
                  ),
                  const SizedBox(width: 12),

                  // Label and Short Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                info.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isSelected ? info.accentColor : null,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (info.isWarmup) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '0% vol',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          info.shortDescription,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Quick picks if applicable
                  if (quickConfig != null) ...[
                    _QuickPick(
                      label: quickConfig.defaultLabel,
                      onTap: () => confirmQuick(quickConfig.defaultValue),
                    ),
                    IconButton(
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  ],

                  // Question Mark Help Button
                  IconButton(
                    icon: Icon(
                      Icons.help_outline_rounded,
                      size: 19,
                      color: isSelected
                          ? info.accentColor
                          : AppColors.secondary.withValues(alpha: 0.7),
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Razlaga za ${info.label}',
                    onPressed: widget.onHelpTap,
                  ),

                  // Selected Indicator Check
                  if (isSelected && quickConfig == null) ...[
                    const SizedBox(width: 2),
                    Icon(
                      Icons.check_circle_rounded,
                      color: info.accentColor,
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expanded alternates for quick-picks
          if (quickConfig != null && _expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final alt in quickConfig.alternates)
                      _QuickPick(
                        label: quickConfig.alternateLabel(alt),
                        onTap: () => confirmQuick(alt),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Squircle Badge for Set Types
class _SquircleBadge extends StatelessWidget {
  final String badge;
  final IconData? icon;
  final Color accentColor;
  final bool selected;

  const _SquircleBadge({
    required this.badge,
    this.icon,
    required this.accentColor,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? accentColor.withValues(alpha: 0.22)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? accentColor.withValues(alpha: 0.6)
              : AppColors.outlineVariant.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: icon != null
          ? Icon(
              icon,
              size: 18,
              color: selected ? accentColor : AppColors.onSurfaceVariant,
            )
          : (badge.isEmpty || badge == '—'
              ? Icon(
                  Icons.horizontal_rule_rounded,
                  size: 16,
                  color: selected ? accentColor : AppColors.secondary,
                )
              : Text(
                  badge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: selected ? accentColor : AppColors.onSurfaceVariant,
                  ),
                )),
    );
  }
}

/// Default value + alternates for a metadata-carrying set type's quick-pick.
class _QuickPickConfig {
  final String metaKey;
  final int defaultValue;
  final String defaultLabel;
  final List<int> alternates;
  final String Function(int) alternateLabel;

  const _QuickPickConfig({
    required this.metaKey,
    required this.defaultValue,
    required this.defaultLabel,
    required this.alternates,
    required this.alternateLabel,
  });
}

String _secondsLabel(int s) => '${s}s';
String _dropPercentLabel(int pct) => '-$pct%';

/// Small pill-shaped quick-pick (drop %, pause seconds).
class _QuickPick extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickPick({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: AppColors.surfaceVariant,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── SET TYPES GUIDE & NATIVE UI MOCKUP SHEET ────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────

/// Full interactive guide explaining all set types with native Flutter UI mockups
/// showing exactly how each set type behaves and is measured in Herculex.
class SetTypesGuideSheet extends StatefulWidget {
  final String? initialHighlight;

  const SetTypesGuideSheet({super.key, this.initialHighlight});

  static Future<void> show(BuildContext context, {String? initialHighlight}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SetTypesGuideSheet(initialHighlight: initialHighlight),
    );
  }

  @override
  State<SetTypesGuideSheet> createState() => _SetTypesGuideSheetState();
}

class _SetTypesGuideSheetState extends State<SetTypesGuideSheet> {
  String _selectedCategory = 'all';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filtered = SetTypeInfo.all.where((item) {
      if (_selectedCategory == 'basic' && item.category != SetTypeCategory.basic) {
        return false;
      }
      if (_selectedCategory == 'hypertrophy' &&
          item.category != SetTypeCategory.hypertrophy) {
        return false;
      }
      if (_selectedCategory == 'timed' && item.category != SetTypeCategory.timed) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return item.label.toLowerCase().contains(query) ||
            item.shortDescription.toLowerCase().contains(query) ||
            item.fullExplanation.toLowerCase().contains(query) ||
            item.badge.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color:
              theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Sheet Title & Close
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set Types Guide',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Technique explanations, volume impact & UI indicators',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Search Bar + Filter Chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search set type (e.g. Drop set, Rest-pause, AMRAP)...',
                  hintStyle: TextStyle(fontSize: 13, color: AppColors.secondary),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All (${SetTypeInfo.all.length})',
                    selected: _selectedCategory == 'all',
                    onTap: () => setState(() => _selectedCategory = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Basic & Warmup',
                    selected: _selectedCategory == 'basic',
                    onTap: () => setState(() => _selectedCategory = 'basic'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Hypertrophy & Intensity',
                    selected: _selectedCategory == 'hypertrophy',
                    onTap: () => setState(() => _selectedCategory = 'hypertrophy'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Timed & Functional',
                    selected: _selectedCategory == 'timed',
                    onTap: () => setState(() => _selectedCategory = 'timed'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),

            // Cards list with UI mockups
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final info = filtered[index];
                  final isInitial = widget.initialHighlight != null &&
                      (widget.initialHighlight == info.id ||
                          (widget.initialHighlight == 'warmup' && info.isWarmup));

                  return _GuideDetailCard(info: info, isHighlighted: isInitial);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary
          : AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.black : AppColors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Detailed card in the Guide containing full explanations, metric rules,
/// and a native visual UI mockup representing how the set row looks in the app.
class _GuideDetailCard extends StatelessWidget {
  final SetTypeInfo info;
  final bool isHighlighted;

  const _GuideDetailCard({
    required this.info,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted
              ? info.accentColor
              : AppColors.outlineVariant.withValues(alpha: 0.25),
          width: isHighlighted ? 2.0 : 1.0,
        ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: info.accentColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Badge + Title + Category Chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SquircleBadge(
                badge: info.badge,
                icon: info.icon,
                accentColor: info.accentColor,
                selected: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.category.title,
                      style: TextStyle(
                        fontSize: 11,
                        color: info.accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (info.badge.isNotEmpty && info.badge != '—')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: info.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: info.accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Koda: ${info.badge}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: info.accentColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 1. Definition / Explanation
          Text(
            info.fullExplanation,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              height: 1.4,
              color: AppColors.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),

          // 2. How it's measured in Herculex (Impact Box)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      size: 15,
                      color: info.accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Merjenje v aplikaciji Herculex',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: info.accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  info.howMeasuredInApp,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                if (info.volumeTonnageRule != null || info.cnsRule != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (info.volumeTonnageRule != null)
                        _TagChip(
                          icon: Icons.scale_rounded,
                          text: info.volumeTonnageRule!,
                          color: Colors.blueAccent,
                        ),
                      if (info.cnsRule != null)
                        _TagChip(
                          icon: Icons.bolt_rounded,
                          text: info.cnsRule!,
                          color: Colors.amberAccent,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Native Visual UI Mockup (Simulating in-app Set Row)
          Row(
            children: [
              Icon(Icons.remove_red_eye_outlined, size: 14, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                'In-workout visual preview:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _NativeSetRowMockup(info: info),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _TagChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Native Flutter visual UI simulation of how this set row appears during an active workout.
class _NativeSetRowMockup extends StatelessWidget {
  final SetTypeInfo info;

  const _NativeSetRowMockup({required this.info});

  @override
  Widget build(BuildContext context) {
    final isWarmup = info.isWarmup;
    final badgeText = isWarmup ? 'W' : (info.badge.isEmpty ? '1' : info.badge);
    final weightText = switch (info.id) {
      'warmup' => '40 kg',
      'drop' => '64 kg (-20%)',
      'volume_20x60' => '60 kg (60%)',
      _ => '80 kg',
    };
    final repsText = switch (info.id) {
      'warmup' => '12 reps',
      'down_sets' => '9 reps (D2)',
      'pause' => '8 reps (3s)',
      'partials' => '6 + 4 partials',
      'amrap' => '15 reps (1m)',
      'emom' => '5 reps/min',
      'for_time' => '20 reps (45s)',
      _ => '8 reps',
    };
    final rpeText = isWarmup ? 'RPE 5.0' : (info.id == 'forced' ? 'RPE 10' : 'RPE 8.5');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWarmup
              ? Colors.orange.withValues(alpha: 0.4)
              : (info.type != SetType.standard
                  ? info.accentColor.withValues(alpha: 0.4)
                  : AppColors.outlineVariant.withValues(alpha: 0.3)),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          // Index Badge
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isWarmup
                  ? Colors.orange.withValues(alpha: 0.18)
                  : (info.type != SetType.standard
                      ? info.accentColor.withValues(alpha: 0.18)
                      : AppColors.surfaceVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isWarmup
                ? const Icon(Icons.local_fire_department, size: 16, color: Colors.orange)
                : Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: info.type != SetType.standard
                          ? info.accentColor
                          : AppColors.onSurface,
                    ),
                  ),
          ),
          const SizedBox(width: 10),

          // Weight Mock Field
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                weightText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Reps Mock Field
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                repsText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // RPE Badge Mock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rpeText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Checkmark Mock
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class SetTypeDetailDialog extends StatelessWidget {
  final SetTypeInfo info;

  const SetTypeDetailDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, SetTypeInfo info) {
    return showDialog<void>(
      context: context,
      builder: (_) => SetTypeDetailDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      backgroundColor: AppColors.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Badge + Title + Close Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SquircleBadge(
                  badge: info.badge,
                  icon: info.icon,
                  accentColor: info.accentColor,
                  selected: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.category.title,
                        style: TextStyle(
                          fontSize: 11,
                          color: info.accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Definition / Explanation
                    Text(
                      info.fullExplanation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // How it's measured in Herculex
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.analytics_outlined,
                                size: 15,
                                color: info.accentColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Merjenje v aplikaciji Herculex',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: info.accentColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            info.howMeasuredInApp,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          if (info.volumeTonnageRule != null || info.cnsRule != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (info.volumeTonnageRule != null)
                                  _TagChip(
                                    icon: Icons.scale_rounded,
                                    text: info.volumeTonnageRule!,
                                    color: Colors.blueAccent,
                                  ),
                                if (info.cnsRule != null)
                                  _TagChip(
                                    icon: Icons.bolt_rounded,
                                    text: info.cnsRule!,
                                    color: Colors.amberAccent,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Visual UI Mockup
                    Row(
                      children: [
                        Icon(Icons.remove_red_eye_outlined, size: 14, color: AppColors.secondary),
                        const SizedBox(width: 6),
                        Text(
                          'In-workout visual preview:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _NativeSetRowMockup(info: info),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Close Button
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: info.accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
