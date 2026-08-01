import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../data/carb_cycle_service.dart';
import '../domain/carb_cycling.dart';
import '../domain/diet_phase.dart';
import '../domain/macro_targets.dart';
import 'nutrition_providers.dart';

/// Hub for everything target-related (§5). Each of the three areas is a
/// screen of its own rather than a section of one long page, so the hub stays
/// a short, centred menu.
class NutritionTargetsView extends ConsumerWidget {
  const NutritionTargetsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final targets = ref.watch(nutritionTargetsProvider).asData?.value;
    final schedule = ref.watch(activeDietScheduleProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Targets & Dieting'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              'Set what you\'re aiming for, automate how it changes, and shape '
              'your carbs around training.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 28),
            _HubTile(
              icon: Icons.flag_outlined,
              title: 'Daily Targets',
              subtitle: targets == null || targets.isEmpty
                  ? 'Using profile-calculated targets'
                  : '${targets.length} custom target'
                        '${targets.length == 1 ? '' : 's'}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DailyTargetsView()),
              ),
            ),
            const SizedBox(height: 12),
            _HubTile(
              icon: Icons.timeline,
              title: 'Active Schedule',
              subtitle: schedule == null
                  ? 'No automated calorie change running'
                  : schedule.reducePct < 0
                  ? 'Bulk · +${(-schedule.reducePct).toStringAsFixed(1)}% '
                        'every ${schedule.intervalDays} days'
                  : 'Cut · −${schedule.reducePct.toStringAsFixed(1)}% '
                        'every ${schedule.intervalDays} days',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActiveScheduleView()),
              ),
            ),
            const SizedBox(height: 12),
            _HubTile(
              icon: Icons.bakery_dining_outlined,
              title: 'Carb Cycle',
              subtitle: 'Hardest training days get the most carbs',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CarbCycleView())),
            ),
          ],
        ),
      ),
    );
  }
}

/// One centred entry on the Targets & Dieting hub.
class _HubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Daily Targets screen ────────────────────────────────────────────────────

class DailyTargetsView extends ConsumerWidget {
  const DailyTargetsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final targets = ref.watch(nutritionTargetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Targets'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          children: [
            Text(
              'The most specific scope wins: date > weekday > training/rest '
              'day > global.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            targets.when(
              data: (rows) => rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No custom targets yet — using the calories calculated '
                        'from your profile.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final t in rows)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                Icons.flag_outlined,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              title: Text(
                                t.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${t.kcal} kcal · P${t.proteinG}g  C${t.carbsG}g  F${t.fatG}g'
                                '${t.fiberG != null ? '  Fi${t.fiberG}g' : ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                onPressed: () => ref
                                    .read(nutritionRepositoryProvider)
                                    .deleteTarget(t.id),
                              ),
                            ),
                          ),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TargetEditorView()),
              ),
              child: const Text('Add / Edit Target'),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Active Schedule screen ──────────────────────────────────────────────────

class ActiveScheduleView extends ConsumerWidget {
  const ActiveScheduleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final schedule = ref.watch(activeDietScheduleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Schedule'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          children: [
            Text(
              'A schedule steps your calories up or down automatically at a '
              'fixed interval, so you don\'t have to re-enter targets.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            schedule.when(
              data: (s) {
                if (s == null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Nothing running. Start a cut or a bulk below.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  );
                }
                final isBulk = s.reducePct < 0;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      isBulk ? Icons.trending_up : Icons.trending_down,
                      color: isBulk ? Colors.green : AppColors.primary,
                    ),
                    title: Text(
                      isBulk
                          ? '+${(-s.reducePct).toStringAsFixed(1)}% every ${s.intervalDays} days (Bulk)'
                          : '−${s.reducePct.toStringAsFixed(1)}% every ${s.intervalDays} days (Cut)',
                    ),
                    subtitle: Text('Started ${s.startDateIso}'),
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(nutritionRepositoryProvider)
                          .stopDietSchedules(),
                      child: const Text('Stop'),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _showCutBulkSheet(context, ref, isBulk: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text('Start Cut'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      _showCutBulkSheet(context, ref, isBulk: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                  ),
                  child: const Text('Start Bulk'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCutBulkSheet(
    BuildContext context,
    WidgetRef ref, {
    required bool isBulk,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CutBulkSheet(ref: ref, isBulk: isBulk),
    );
  }
}

// ── Carb Cycle screen ───────────────────────────────────────────────────────

class CarbCycleView extends ConsumerWidget {
  const CarbCycleView({super.key});

  static DateTime _mondayOf(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return local.subtract(Duration(days: local.weekday - DateTime.monday));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final carbCycle = ref.watch(
      generatedCarbCycleProvider(DateTime(today.year, today.month, today.day)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Carb Cycle'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          children: [
            Text(
              'Generated from your training: the hardest days get the most '
              'carbs.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 24),
            carbCycle.when(
              data: (levels) => _CarbCycleRow(levels: levels),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Save this week\'s plan'),
              onPressed: () async {
                final levels = carbCycle.asData?.value;
                if (levels == null) return;
                await ref
                    .read(nutritionRepositoryProvider)
                    .saveCarbCyclePlan(
                      weekStart: _mondayOf(today),
                      dayLevelsJson: CarbCycleService.encodeLevels(levels),
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Carb cycle saved')),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Add / Edit Target screen ───────────────────────────────────────────────

/// Which macro input mode the user is working in.
enum _MacroMode { grams, percent, perLb }

/// Full-screen target editor (§5). A dieting phase can be applied on top of a
/// maintenance figure, which rewrites the calorie and macro fields in place.
class TargetEditorView extends ConsumerStatefulWidget {
  const TargetEditorView({super.key});

  @override
  ConsumerState<TargetEditorView> createState() => _TargetEditorViewState();
}

class _TargetEditorViewState extends ConsumerState<TargetEditorView> {
  String _scope = 'global';
  int? _weekday;
  _MacroMode _mode = _MacroMode.grams;

  /// The dieting phase the entered numbers represent (§5).
  DietPhase _phase = DietPhase.maintain;

  /// Maintenance calories the phase adjustment is derived from. Seeded from
  /// the profile so picking "Cut" works before the user types anything.
  final _maintenanceKcal = TextEditingController();

  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fiber = TextEditingController();
  // % mode
  final _proteinPct = TextEditingController(text: '30');
  final _carbsPct = TextEditingController(text: '40');
  final _fatPct = TextEditingController(text: '30');
  // g/lb mode
  final _proteinPerLb = TextEditingController(text: '1.0');

  @override
  void initState() {
    super.initState();
    // Seed maintenance from the profile-derived TDEE so the phase buttons do
    // something useful immediately.
    final profile = ref.read(profileProvider).asData?.value;
    final baseline = profile == null ? null : MacroTargets.fromProfile(profile);
    if (baseline != null) _maintenanceKcal.text = baseline.kcal.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _maintenanceKcal,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fiber,
      _proteinPct,
      _carbsPct,
      _fatPct,
      _proteinPerLb,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Returns bodyweight in kg from profile, or null.
  double? get _bodyweightKg =>
      ref.read(profileProvider).asData?.value?.weightKg;

  /// Recomputes every field from the maintenance figure for [_phase] (§5).
  /// Switching phase is meant to move the whole target, not just relabel it,
  /// so this drops the editor into grams mode and writes the numbers.
  void _applyPhase(DietPhase phase) {
    final baseline = int.tryParse(_maintenanceKcal.text.trim());
    setState(() {
      _phase = phase;
      if (baseline == null || baseline <= 0) return;
      final t = DietPhaseCalculator.apply(
        phase: phase,
        baselineKcal: baseline,
        bodyweightKg: _bodyweightKg,
      );
      _mode = _MacroMode.grams;
      _kcal.text = t.kcal.toString();
      _protein.text = t.proteinG.toString();
      _carbs.text = t.carbsG.toString();
      _fat.text = t.fatG.toString();
    });
  }

  // Converts current mode inputs into final gram values. Returns null if inputs incomplete.
  ({int kcal, int protein, int carbs, int fat})? _resolve() {
    final kcal = int.tryParse(_kcal.text);
    if (kcal == null || kcal <= 0) return null;

    if (_mode == _MacroMode.grams) {
      final p = int.tryParse(_protein.text);
      final c = int.tryParse(_carbs.text);
      final f = int.tryParse(_fat.text);
      if (p == null || c == null || f == null) return null;
      return (kcal: kcal, protein: p, carbs: c, fat: f);
    }

    if (_mode == _MacroMode.percent) {
      final pp = double.tryParse(_proteinPct.text) ?? 0;
      final cp = double.tryParse(_carbsPct.text) ?? 0;
      final fp = double.tryParse(_fatPct.text) ?? 0;
      if ((pp + cp + fp - 100).abs() > 1) return null;
      final p = (kcal * pp / 100 / 4).round();
      final c = (kcal * cp / 100 / 4).round();
      final f = (kcal * fp / 100 / 9).round();
      return (kcal: kcal, protein: p, carbs: c, fat: f);
    }

    // _MacroMode.perLb
    final bwKg = _bodyweightKg;
    if (bwKg == null) return null;
    final bwLb = bwKg * 2.20462;
    final gPerLb = double.tryParse(_proteinPerLb.text) ?? 1.0;
    final p = (bwLb * gPerLb).round();
    // Remaining kcal split 40% carbs / rest fat.
    final remainingKcal = kcal - p * 4;
    if (remainingKcal < 0) return null;
    final c = (remainingKcal * 0.55 / 4).round();
    final f = ((remainingKcal - c * 4) / 9).round().clamp(0, 9999).toInt();
    return (kcal: kcal, protein: p, carbs: c, fat: f);
  }

  double get _pctSum =>
      (double.tryParse(_proteinPct.text) ?? 0) +
      (double.tryParse(_carbsPct.text) ?? 0) +
      (double.tryParse(_fatPct.text) ?? 0);

  String get _scopeKey {
    if (_scope == 'weekday' && _weekday != null) return 'weekday:$_weekday';
    return _scope;
  }

  String get _scopeLabel {
    if (_scope == 'global') return 'Global';
    if (_scope == 'training_day') return 'Training day';
    if (_scope == 'rest_day') return 'Rest day';
    if (_scope == 'weekday' && _weekday != null) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[(_weekday! - 1).clamp(0, 6)];
    }
    return _scope;
  }

  Future<void> _save() async {
    final resolved = _resolve();
    if (resolved == null) {
      String msg = 'Please fill in calories and all macro fields.';
      if (_mode == _MacroMode.percent && (_pctSum - 100).abs() > 1) {
        msg =
            'Macro percentages must add up to 100% (currently ${_pctSum.round()}%).';
      } else if (_mode == _MacroMode.perLb && _bodyweightKg == null) {
        msg = 'Add your bodyweight in profile first.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    await ref
        .read(nutritionRepositoryProvider)
        .upsertTarget(
          label: _scopeLabel,
          appliesTo: _scopeKey,
          kcal: resolved.kcal,
          proteinG: resolved.protein,
          carbsG: resolved.carbs,
          fatG: resolved.fat,
          fiberG: int.tryParse(_fiber.text),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final bwKg = _bodyweightKg;
    final bwLb = bwKg != null ? bwKg * 2.20462 : null;

    // Live preview of resolved grams for % and g/lb modes.
    final kcalVal = int.tryParse(_kcal.text) ?? 0;
    final resolved = kcalVal > 0 ? _resolve() : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Add / Edit Target'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, mq.viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Text(
                    'Saving the same scope replaces the existing target.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Dieting phase (§5) ──
                Text(
                  'PHASE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final phase in DietPhase.values)
                      ChoiceChip(
                        label: Text(phase.label),
                        selected: _phase == phase,
                        onSelected: (_) => _applyPhase(phase),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _NumField(
                  controller: _maintenanceKcal,
                  label: 'Maintenance calories (kcal)',
                  onChanged: (_) => _applyPhase(_phase),
                ),
                const SizedBox(height: 6),
                Text(
                  _phase == DietPhase.maintain
                      ? 'Pick Cut or Bulk to shift the numbers below automatically.'
                      : _phase == DietPhase.cut
                      ? 'Cut applies a ${DietPhaseCalculator.defaultCutPct.round()}% '
                            'deficit and raises protein to protect lean mass.'
                      : 'Bulk applies a ${DietPhaseCalculator.defaultBulkPct.round()}% '
                            'surplus, with the extra going to carbs.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Scope ──
                Text(
                  'APPLIES TO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in {
                      'global': 'Global',
                      'training_day': 'Training day',
                      'rest_day': 'Rest day',
                      'weekday': 'Specific day',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _scope == entry.key,
                        onSelected: (_) => setState(() {
                          _scope = entry.key;
                          _weekday ??= 1;
                        }),
                      ),
                  ],
                ),
                if (_scope == 'weekday') ...[
                  const SizedBox(height: 10),
                  Text(
                    'WEEKDAY',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var i = 1; i <= 7; i++)
                        ChoiceChip(
                          label: Text(
                            [
                              'Mon',
                              'Tue',
                              'Wed',
                              'Thu',
                              'Fri',
                              'Sat',
                              'Sun',
                            ][i - 1],
                          ),
                          selected: _weekday == i,
                          onSelected: (_) => setState(() => _weekday = i),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // ── Calories ──
                Text(
                  'CALORIES',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                _NumField(
                  controller: _kcal,
                  label: 'Daily calories (kcal)',
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 20),

                // ── Macro input mode ──
                Text(
                  'MACRO INPUT METHOD',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Grams'),
                      selected: _mode == _MacroMode.grams,
                      onSelected: (_) =>
                          setState(() => _mode = _MacroMode.grams),
                    ),
                    ChoiceChip(
                      label: const Text('% of calories'),
                      selected: _mode == _MacroMode.percent,
                      onSelected: (_) =>
                          setState(() => _mode = _MacroMode.percent),
                    ),
                    ChoiceChip(
                      label: const Text('g / lb bodyweight'),
                      selected: _mode == _MacroMode.perLb,
                      onSelected: (_) =>
                          setState(() => _mode = _MacroMode.perLb),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Mode-specific inputs ──
                if (_mode == _MacroMode.grams) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _NumField(
                          controller: _protein,
                          label: 'Protein (g)',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumField(
                          controller: _carbs,
                          label: 'Carbs (g)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _NumField(controller: _fat, label: 'Fat (g)'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumField(
                          controller: _fiber,
                          label: 'Fiber (g) optional',
                        ),
                      ),
                    ],
                  ),
                ],

                if (_mode == _MacroMode.percent) ...[
                  Text(
                    'Set the % of total calories for each macro. Must add up to 100%.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _NumField(
                          controller: _proteinPct,
                          label: 'Protein %',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumField(
                          controller: _carbsPct,
                          label: 'Carbs %',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumField(
                          controller: _fatPct,
                          label: 'Fat %',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Total: ${_pctSum.round()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: (_pctSum - 100).abs() <= 1
                              ? Colors.green
                              : Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 140,
                        child: _NumField(
                          controller: _fiber,
                          label: 'Fiber (g) optional',
                        ),
                      ),
                    ],
                  ),
                ],

                if (_mode == _MacroMode.perLb) ...[
                  if (bwLb != null)
                    Text(
                      'Your bodyweight: ${bwLb.toStringAsFixed(1)} lb (${bwKg!.toStringAsFixed(1)} kg)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    )
                  else
                    Text(
                      'Add bodyweight in your profile to use this mode.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _NumField(
                          controller: _proteinPerLb,
                          label: 'Protein (g / lb)',
                          hint: '1.0',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumField(
                          controller: _fiber,
                          label: 'Fiber (g) optional',
                        ),
                      ),
                    ],
                  ),
                  if (bwLb != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Suggested: 1 g/lb = ${(bwLb * 1.0).round()} g protein',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                  Text(
                    'Remaining calories split: 55% carbs / 45% fat.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],

                // ── Live preview ──
                if (resolved != null && _mode != _MacroMode.grams) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _PreviewMacro(
                          'Protein',
                          resolved.protein,
                          'g',
                          AppColors.macroProtein,
                          theme,
                        ),
                        _PreviewMacro(
                          'Carbs',
                          resolved.carbs,
                          'g',
                          AppColors.macroCarbs,
                          theme,
                        ),
                        _PreviewMacro(
                          'Fat',
                          resolved.fat,
                          'g',
                          AppColors.macroFat,
                          theme,
                        ),
                        _PreviewMacro(
                          'Kcal',
                          resolved.kcal,
                          '',
                          AppColors.macroKcal,
                          theme,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    // "Save Cut" / "Save Bulk" / "Save Target" (§5).
                    child: Text(_phase.saveLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewMacro extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final Color color;
  final ThemeData theme;
  const _PreviewMacro(
    this.label,
    this.value,
    this.unit,
    this.color,
    this.theme,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value$unit',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }
}

// ── Cut / Bulk schedule sheet ──────────────────────────────────────────────

class _CutBulkSheet extends StatefulWidget {
  final WidgetRef ref;
  final bool isBulk;
  const _CutBulkSheet({required this.ref, required this.isBulk});

  @override
  State<_CutBulkSheet> createState() => _CutBulkSheetState();
}

class _CutBulkSheetState extends State<_CutBulkSheet> {
  final _pct = TextEditingController();
  final _interval = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pct.text = widget.isBulk ? '3' : '5';
    _interval.text = '14';
  }

  @override
  void dispose() {
    _pct.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final pct = double.tryParse(_pct.text);
    final interval = int.tryParse(_interval.text);
    if (pct == null || interval == null || pct <= 0 || interval <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid positive numbers')),
      );
      return;
    }
    // Bulk = negative reducePct (calories go UP by pct each interval).
    final effectivePct = widget.isBulk ? -pct : pct;
    await widget.ref
        .read(nutritionRepositoryProvider)
        .startDietSchedule(
          startDate: DateTime.now(),
          reducePct: effectivePct,
          intervalDays: interval,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final color = widget.isBulk ? Colors.green : AppColors.primary;
    final title = widget.isBulk ? 'Start Bulk' : 'Start Cut';
    final verb = widget.isBulk ? 'Increase' : 'Reduce';

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  widget.isBulk ? Icons.trending_up : Icons.trending_down,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.isBulk
                  ? 'Calories increase by the set % every interval. Protein is preserved; surplus goes to carbs and fat.'
                  : 'Calories reduce by the set % every interval. Protein is preserved; deficit comes from carbs and fat.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _NumField(
                    controller: _pct,
                    label: '$verb by (%)',
                    hint: widget.isBulk ? '3' : '5',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumField(
                    controller: _interval,
                    label: 'Every (days)',
                    hint: '14',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: _start,
                child: Text(title),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;

  const _NumField({
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

class _CarbCycleRow extends StatelessWidget {
  final List<CarbLevel> levels;
  const _CarbCycleRow({required this.levels});

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < levels.length && i < 7; i++)
          Expanded(
            child: Column(
              children: [
                Text(
                  days[i],
                  style: TextStyle(fontSize: 11, color: AppColors.secondary),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _color(levels[i]).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _color(levels[i])),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    levels[i].label[0],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _color(levels[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _color(CarbLevel l) => switch (l) {
    CarbLevel.high => Colors.green,
    CarbLevel.medium => Colors.amber,
    CarbLevel.low => Colors.redAccent,
  };
}
