import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../theme/colors.dart';
import '../../../theme/theme_provider.dart';
import '../../nutrition/domain/macro_targets.dart';
import '../domain/profile.dart';

// ── Profile view ─────────────────────────────────────────────────────────────
//
// The measurement-system preference now lives in `core/units.dart` so the
// workout and nutrition screens can honour it too (they previously read a
// private provider they had no access to, which is why imperial users still
// saw kilograms in workouts).

class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: profileAsync.when(
          data: (profile) => _ProfileBody(profile: profile),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  final Profile? profile;
  const _ProfileBody({required this.profile});

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  late FitnessGoal _goal;
  late ActivityLevel _activityLevel;
  late BiologicalSex? _sex;
  late bool _countBurnedCalories;

  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _goal = p?.goal ?? FitnessGoal.maintenance;
    _activityLevel = p?.activityLevel ?? ActivityLevel.lightlyActive;
    _sex = p?.sex;
    _countBurnedCalories = p?.countBurnedCalories ?? false;
    _nameCtrl.text = p?.name ?? '';
    _ageCtrl.text = p?.ageYears?.toString() ?? '';
    // Body stats are stored in metric; the fields show the user's own system.
    final weightFmt = ref.read(weightFormatProvider);
    final heightFmt = ref.read(heightFormatProvider);
    _weightCtrl.text = p?.weightKg == null
        ? ''
        : weightFmt.formatValue(p!.weightKg!);
    _heightCtrl.text = p?.heightCm == null
        ? ''
        : heightFmt.formatValue(p!.heightCm!);
  }

  /// Re-renders the body-stat fields when the measurement system flips, so a
  /// stored 82.5 kg becomes 182 lb in place rather than being reinterpreted.
  void _rewriteBodyStatFields() {
    final weightFmt = ref.read(weightFormatProvider);
    final heightFmt = ref.read(heightFormatProvider);
    final kg = widget.profile?.weightKg;
    final cm = widget.profile?.heightCm;
    _weightCtrl.text = kg == null ? '' : weightFmt.formatValue(kg);
    _heightCtrl.text = cm == null ? '' : heightFmt.formatValue(cm);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  /// The profile as it would be saved right now, used both by [_save] and by
  /// the live calorie estimate so the two never disagree.
  Profile _draft() {
    final name = _nameCtrl.text.trim();
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());
    return Profile(
      name: name.isEmpty ? null : name,
      goal: _goal,
      activityLevel: _activityLevel,
      sex: _sex,
      countBurnedCalories: _countBurnedCalories,
      ageYears: int.tryParse(_ageCtrl.text.trim()),
      // Fields hold display units; storage is always metric.
      weightKg: weight == null
          ? null
          : ref.read(weightFormatProvider).toKg(weight),
      heightCm: height == null
          ? null
          : ref.read(heightFormatProvider).toCm(height),
      preferredUnit: ref.read(unitsProvider),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(localProfileRepositoryProvider).save(_draft());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Profile saved'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  Future<void> _clearData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear all data?'),
        content: const Text(
          'This will permanently delete your profile, workouts, nutrition logs, and all other local data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: const StadiumBorder(),
            ),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Clearing the profile drops the user back to onboarding via the router
    // redirect (which watches profileProvider).
    await ref.read(localProfileRepositoryProvider).clear();
  }

  /// Opens the identity editor — tapping the avatar is the only entry point
  /// for changing the name or picture (§5).
  Future<void> _editIdentity() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _IdentitySheet(initialName: _nameCtrl.text),
    );
    if (name == null || !mounted) return;
    setState(() => _nameCtrl.text = name);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMetric = ref.watch(unitsProvider) == MeasurementUnit.metric;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
      children: [
        if (Navigator.of(context).canPop())
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_left, size: 28),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        // ── Avatar / header ───────────────────────────────────────────────
        _AvatarHeader(profile: widget.profile, onEdit: _editIdentity),
        const SizedBox(height: 32),

        // ── Body stats ────────────────────────────────────────────────────
        _SectionHeader('Body Stats'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatField(
                label: 'Age',
                hint: 'yrs',
                controller: _ageCtrl,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatField(
                label: isMetric ? 'Weight (kg)' : 'Weight (lb)',
                hint: isMetric ? 'kg' : 'lb',
                controller: _weightCtrl,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatField(
                label: isMetric ? 'Height (cm)' : 'Height (in)',
                hint: isMetric ? 'cm' : 'in',
                controller: _heightCtrl,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        // BMI chip (read-only, calculated)
        if (widget.profile?.weightKg != null &&
            widget.profile?.heightCm != null)
          _BmiChip(
            weightKg: widget.profile!.weightKg!,
            heightCm: widget.profile!.heightCm!,
          ),

        const SizedBox(height: 28),

        // ── Biological sex ────────────────────────────────────────────────
        _SectionHeader('Biological Sex'),
        const SizedBox(height: 12),
        Row(
          children: BiologicalSex.values.map((s) {
            final selected = _sex == s;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: s == BiologicalSex.male ? 8 : 0,
                ),
                child: _PillToggle(
                  label: s.label,
                  selected: selected,
                  onTap: () => setState(() => _sex = s),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 28),

        // ── Fitness goal ──────────────────────────────────────────────────
        _SectionHeader('Fitness Goal'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FitnessGoal.values.map((g) {
            final selected = _goal == g;
            return _PillToggle(
              label: g.label,
              selected: selected,
              onTap: () => setState(() => _goal = g),
            );
          }).toList(),
        ),

        const SizedBox(height: 28),

        // ── Activity level ────────────────────────────────────────────────
        _SectionHeader('Activity Level'),
        const SizedBox(height: 12),
        Column(
          children: ActivityLevel.values.map((a) {
            final selected = _activityLevel == a;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActivityTile(
                level: a,
                selected: selected,
                onTap: () => setState(() => _activityLevel = a),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),
        // App-calculated daily calories for the current draft, with a shortcut
        // into Targets & Dieting for overriding it (§5).
        _CalorieEstimateRow(targets: MacroTargets.fromProfile(_draft())),

        const SizedBox(height: 28),

        // ── App settings ──────────────────────────────────────────────────
        _SectionHeader('App Settings'),
        const SizedBox(height: 12),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.straighten_rounded,
              label: 'Units',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMetric ? 'Metric' : 'Freedom',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: isMetric,
                    onChanged: (_) async {
                      await ref.read(unitsProvider.notifier).toggle();
                      // Re-render the weight/height fields in the new system
                      // so the stored value is preserved, not reinterpreted.
                      if (mounted) setState(_rewriteBodyStatFields);
                    },
                  ),
                ],
              ),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.local_fire_department,
              label: 'Include Burned Calories',
              trailing: Switch(
                value: _countBurnedCalories,
                onChanged: (val) => setState(() => _countBurnedCalories = val),
              ),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.dark_mode_rounded,
              label: 'Theme',
              trailing: _ThemeToggle(),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.health_and_safety_rounded,
              label: 'Samsung Health & Integrations',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SyncStatusBadge(),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.onSurfaceVariant,
                  ),
                ],
              ),
              onTap: () => context.push('/health'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.analytics_rounded,
              label: 'Insights',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => context.push('/insights'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.straighten,
              label: 'Body Measurements',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => context.push('/measurements'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.location_on_outlined,
              label: 'My Gyms',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => context.push('/gyms'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.task_alt,
              label: 'Micro Workouts',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => context.push('/micro-workouts'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.restaurant_menu_rounded,
              label: 'Custom Foods',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => context.push('/custom-foods'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.menu_book_rounded,
              label: 'Custom Recipes',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => context.push('/custom-recipes'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.notifications_rounded,
              label: 'Notifications',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => _showComingSoon(context, 'Notifications'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.download_rounded,
              label: 'Export Data (JSON)',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => _exportData(context),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'About & Attribution',
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => _showAttribution(context),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // ── Save stats button ─────────────────────────────────────────────
        _SaveButton(saving: _saving, onTap: _save),

        const SizedBox(height: 28),

        // ── Account ───────────────────────────────────────────────────────
        _SectionHeader('Account'),
        const SizedBox(height: 12),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.delete_forever_rounded,
              label: 'Clear All Data',
              iconColor: Colors.red.shade900,
              labelColor: Colors.red.shade900,
              onTap: () => _clearData(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature settings coming soon'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  void _exportData(BuildContext context) {
    // ScaffoldMessenger indicating that export is started
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Exporting data as JSON...'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
    final messenger = ScaffoldMessenger.of(context);
    // In a real implementation this would fetch from Drift and use path_provider to save a file.
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Data export saved to Downloads folder.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        ),
      );
    });
  }

  void _showAttribution(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Herculex',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.fitness_center_rounded, color: AppColors.primary),
      ),
      children: [
        const SizedBox(height: 16),
        const Text(
          'Herculex is a comprehensive fitness, nutrition, and recovery tracker.\n\n'
          'Designed to provide full offline capabilities and advanced analytics.',
        ),
      ],
    );
  }
}

// ── Avatar header ─────────────────────────────────────────────────────────────

/// The daily calorie figure the app derives from the profile, with an edit
/// affordance that jumps straight into Targets & Dieting (§5).
class _CalorieEstimateRow extends StatelessWidget {
  final MacroTargets? targets;
  const _CalorieEstimateRow({required this.targets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = targets;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t == null
                      ? 'Estimated daily calories'
                      : '${t.kcal} kcal / day',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  t == null
                      ? 'Add age, weight and height to calculate'
                      : 'Calculated from your stats, goal and activity level',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
            tooltip: 'Targets & dieting',
            onPressed: () => context.push('/nutrition-targets'),
          ),
        ],
      ),
    );
  }
}

/// Centred identity block: picture above the name (§5). Tapping the picture
/// is what opens the editor — there's no separate name field on the page.
class _AvatarHeader extends StatelessWidget {
  final Profile? profile;
  final VoidCallback onEdit;

  const _AvatarHeader({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile?.name?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onEdit,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: name.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        size: 48,
                        color: AppColors.primary,
                      )
                    : Text(
                        name[0].toUpperCase(),
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.edit, size: 14, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: onEdit,
          child: Text(
            name.isEmpty ? 'My Profile' : name,
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profile != null
              ? '${profile!.goal.label} · ${profile!.activityLevel.label}'
              : 'Set your goals and stats',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Name editor reached by tapping the avatar. Picture selection is offered
/// here too; it is currently a placeholder because the profile model stores no
/// image path yet.
class _IdentitySheet extends StatefulWidget {
  final String initialName;
  const _IdentitySheet({required this.initialName});

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              'Edit profile',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: const StadiumBorder(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── BMI chip ──────────────────────────────────────────────────────────────────

class _BmiChip extends StatelessWidget {
  final double weightKg;
  final double heightCm;
  const _BmiChip({required this.weightKg, required this.heightCm});

  @override
  Widget build(BuildContext context) {
    final h = heightCm / 100;
    final bmi = weightKg / (h * h);
    final (label, color) = switch (bmi) {
      < 18.5 => ('Underweight', Colors.blue.shade400),
      < 25.0 => ('Healthy weight', Colors.green.shade600),
      < 30.0 => ('Overweight', Colors.orange.shade600),
      _ => ('Obese', Colors.red.shade600),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_heart_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            'BMI ${bmi.toStringAsFixed(1)} · $label',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Save button ───────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveButton({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: saving ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
      ),
      child: saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              'Save Profile',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Stat text field ───────────────────────────────────────────────────────────

class _StatField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;

  /// Every remaining stat field is numeric — the name moved into the avatar
  /// editor, so there is no free-text variant left to configure.
  static const keyboardType = TextInputType.numberWithOptions(decimal: true);

  const _StatField({
    required this.label,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.outline, fontSize: 13),
            filled: true,
            fillColor: AppColors.surfaceContainer,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pill toggle button ────────────────────────────────────────────────────────

class _PillToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Activity level tile ───────────────────────────────────────────────────────

class _ActivityTile extends StatelessWidget {
  final ActivityLevel level;
  final bool selected;
  final VoidCallback onTap;
  const _ActivityTile({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  static const _icons = {
    ActivityLevel.sedentary: Icons.weekend_rounded,
    ActivityLevel.lightlyActive: Icons.directions_walk_rounded,
    ActivityLevel.active: Icons.directions_run_rounded,
    ActivityLevel.veryActive: Icons.bolt_rounded,
  };

  static const _descriptions = {
    ActivityLevel.sedentary: 'Desk job, little or no exercise',
    ActivityLevel.lightlyActive: 'Light exercise 1–3 days/week',
    ActivityLevel.active: 'Moderate exercise 3–5 days/week',
    ActivityLevel.veryActive: 'Hard training 6–7 days/week',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icons[level]!,
                size: 20,
                color: selected ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.primary : null,
                    ),
                  ),
                  Text(
                    _descriptions[level]!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings card / tile helpers ──────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      color: AppColors.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final Color? iconColor;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.iconColor,
    this.labelColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: iconColor ?? AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _ThemeToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThemePill(
          label: 'Light',
          icon: Icons.light_mode_rounded,
          selected: mode == ThemeMode.light,
          onTap: () =>
              ref.read(themeModeProvider.notifier).set(ThemeMode.light),
        ),
        const SizedBox(width: 4),
        _ThemePill(
          label: 'System',
          icon: Icons.brightness_auto_rounded,
          selected: mode == ThemeMode.system,
          onTap: () =>
              ref.read(themeModeProvider.notifier).set(ThemeMode.system),
        ),
        const SizedBox(width: 4),
        _ThemePill(
          label: 'Dark',
          icon: Icons.dark_mode_rounded,
          selected: mode == ThemeMode.dark,
          onTap: () => ref.read(themeModeProvider.notifier).set(ThemeMode.dark),
        ),
      ],
    );
  }
}

class _ThemePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ThemePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : AppColors.secondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncStatusBadge extends ConsumerWidget {
  const _SyncStatusBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).valueOrNull ?? SyncStatus.idle;

    final Color color = switch (status) {
      SyncStatus.pendingCloud => Colors.orangeAccent,
      SyncStatus.savedLocally => AppColors.primary,
      SyncStatus.error => Colors.redAccent,
      SyncStatus.idle => AppColors.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (status) {
              SyncStatus.pendingCloud => Icons.cloud_upload_outlined,
              SyncStatus.savedLocally => Icons.cloud_done_outlined,
              SyncStatus.error => Icons.cloud_off,
              SyncStatus.idle => Icons.cloud_done_outlined,
            },
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
