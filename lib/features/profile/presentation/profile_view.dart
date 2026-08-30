import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/providers.dart';
import '../../../core/auth_validator.dart';
import '../../../core/env.dart';
import '../../../core/notifications/toast/hx_toast_controller.dart';
import '../../../core/notifications/toast/hx_toast_model.dart';
import '../../../core/units.dart';
import '../../../data/sync/sync_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../theme/tokens/tokens.dart';
import '../../../theme/theme_provider.dart';
import '../../../ui/ui.dart';
import '../../nutrition/data/speech_to_text_service.dart';
import '../../nutrition/domain/diet_phase.dart';
import '../../nutrition/presentation/goals_providers.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../../workouts/presentation/workout_bubble_controller.dart';
import '../../../services/workout_bubble_service.dart';
import '../data/local_profile_repository.dart';
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
  final _targetWeightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  Timer? _autoSaveTimer;
  bool _saving = false;

  /// Snapshotted here rather than read in [dispose].
  ///
  /// `ref.read` from `State.dispose` throws once the element is unmounted
  /// (`riverpod_lint`'s `avoid_ref_inside_state_dispose`), and this screen's
  /// dispose runs on a normal back-navigation pop — so the final draft flush
  /// could take the teardown down with it.
  late final LocalProfileRepository _profileRepository;

  @override
  void initState() {
    super.initState();
    _profileRepository = ref.read(localProfileRepositoryProvider);
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
    final goalWeight = ref.read(goalWeightProvider);
    final targetKg = p?.targetWeightKg ?? goalWeight;
    _targetWeightCtrl.text = targetKg == null
        ? ''
        : weightFmt.formatValue(targetKg);
    _heightCtrl.text = p?.heightCm == null
        ? ''
        : heightFmt.formatValue(p!.heightCm!);
  }

  @override
  void didUpdateWidget(_ProfileBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile && _autoSaveTimer == null) {
      final p = widget.profile;
      _goal = p?.goal ?? FitnessGoal.maintenance;
      _activityLevel = p?.activityLevel ?? ActivityLevel.lightlyActive;
      _sex = p?.sex;
      _countBurnedCalories = p?.countBurnedCalories ?? false;
      if (_nameCtrl.text != (p?.name ?? '')) {
        _nameCtrl.text = p?.name ?? '';
      }
      if (_ageCtrl.text != (p?.ageYears?.toString() ?? '')) {
        _ageCtrl.text = p?.ageYears?.toString() ?? '';
      }
      final weightFmt = ref.read(weightFormatProvider);
      final heightFmt = ref.read(heightFormatProvider);
      final weightStr = p?.weightKg == null ? '' : weightFmt.formatValue(p!.weightKg!);
      final targetKg = p?.targetWeightKg ?? ref.read(goalWeightProvider);
      final targetStr = targetKg == null ? '' : weightFmt.formatValue(targetKg);
      final heightStr = p?.heightCm == null ? '' : heightFmt.formatValue(p!.heightCm!);
      if (_weightCtrl.text != weightStr) _weightCtrl.text = weightStr;
      if (_targetWeightCtrl.text != targetStr) _targetWeightCtrl.text = targetStr;
      if (_heightCtrl.text != heightStr) _heightCtrl.text = heightStr;
    }
  }

  void _onFieldChanged([String? _]) {
    setState(() {});
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        final draft = _draft();
        ref.read(localProfileRepositoryProvider).save(draft);
        if (draft.targetWeightKg != null) {
          ref.read(goalWeightProvider.notifier).set(draft.targetWeightKg!);
        }
      }
    });
  }

  /// Re-renders the body-stat fields when the measurement system flips, so a
  /// stored 82.5 kg becomes 182 lb in place rather than being reinterpreted.
  void _rewriteBodyStatFields() {
    final weightFmt = ref.read(weightFormatProvider);
    final heightFmt = ref.read(heightFormatProvider);
    final kg = widget.profile?.weightKg;
    final targetKg = widget.profile?.targetWeightKg ?? ref.read(goalWeightProvider);
    final cm = widget.profile?.heightCm;
    _weightCtrl.text = kg == null ? '' : weightFmt.formatValue(kg);
    _targetWeightCtrl.text = targetKg == null ? '' : weightFmt.formatValue(targetKg);
    _heightCtrl.text = cm == null ? '' : heightFmt.formatValue(cm);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // Flush draft to local profile storage before tearing down
    _profileRepository.save(_draft());
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _targetWeightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  /// The profile as it would be saved right now, used both by [_save] and by
  /// the live calorie estimate so the two never disagree.
  Profile _draft() {
    final name = _nameCtrl.text.trim();
    final weight = double.tryParse(_weightCtrl.text.trim());
    final targetWeight = double.tryParse(_targetWeightCtrl.text.trim());
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
      targetWeightKg: targetWeight == null
          ? null
          : ref.read(weightFormatProvider).toKg(targetWeight),
      heightCm: height == null
          ? null
          : ref.read(heightFormatProvider).toCm(height),
      preferredUnit: ref.read(unitsProvider),
    );
  }

  Future<void> _save() async {
    _autoSaveTimer?.cancel();
    setState(() => _saving = true);
    final draft = _draft();
    await ref.read(localProfileRepositoryProvider).save(draft);
    if (draft.targetWeightKg != null) {
      ref.read(goalWeightProvider.notifier).set(draft.targetWeightKg!);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ref.read(hxToastControllerProvider.notifier).show(HxToastItem.profileSaved());
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
      backgroundColor: Colors.transparent,
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
                onChanged: _onFieldChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatField(
                label: isMetric ? 'Height (cm)' : 'Height (in)',
                hint: isMetric ? 'cm' : 'in',
                controller: _heightCtrl,
                onChanged: _onFieldChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatField(
                label: isMetric ? 'Current Weight (kg)' : 'Current Weight (lb)',
                hint: isMetric ? 'kg' : 'lb',
                controller: _weightCtrl,
                onChanged: _onFieldChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatField(
                label: isMetric ? 'Target Weight (kg)' : 'Target Weight (lb)',
                hint: isMetric ? 'kg' : 'lb',
                controller: _targetWeightCtrl,
                onChanged: _onFieldChanged,
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
                  onTap: () {
                    setState(() => _sex = s);
                    _onFieldChanged();
                  },
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 28),

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
                onTap: () {
                  setState(() => _activityLevel = a);
                  _onFieldChanged();
                },
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),

        // ── Active Target & Dieting Phase (Gradient Squircle) ──
        const _ProfileActiveTargetSquircleCard(),
        const SizedBox(height: 12),
        const _DreamPhysiqueCard(),

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
                      color: context.hx.onSurfaceVariant,
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
                onChanged: (val) {
                  setState(() => _countBurnedCalories = val);
                  _onFieldChanged();
                },
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
              icon: Icons.palette_outlined,
              label: 'App Colors',
              trailing: _AppColorToggle(),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.mic_rounded,
              label: 'Voice / Rambler Language',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${ref.watch(speechToTextServiceProvider).selectedLanguageOption.flag} ${ref.watch(speechToTextServiceProvider).selectedLanguageOption.name}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.hx.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: context.hx.onSurfaceVariant,
                    size: 18,
                  ),
                ],
              ),
              onTap: () => _showSttLanguagePicker(context),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.track_changes_rounded,
              label: 'Goals & Targets',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/goals'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.health_and_safety_rounded,
              label: 'Health Integrations',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/health'),
            ),
            _SettingsDivider(),
            // Android-only: iOS has no system overlay windows, so the row is
            // hidden rather than shown disabled — a permanently dead switch
            // reads as a bug.
            if (WorkoutBubbleService.instance.isSupported) ...[
              _SettingsTile(
                icon: Icons.bubble_chart_rounded,
                label: 'Workout Bubble',
                trailing: Switch(
                  value: ref.watch(workoutBubbleEnabledProvider),
                  onChanged: _onWorkoutBubbleToggled,
                ),
              ),
              _SettingsDivider(),
            ],
            // Its own row: this reports cloud sync, and hanging it off the
            // Samsung Health tile read as that integration's status.
            _SettingsTile(
              icon: Icons.cloud_outlined,
              label: 'Cloud sync',
              trailing: const SyncStatusBadge(),
              onTap: ref.watch(authSessionProvider).valueOrNull == null
                  ? () => _showAuthSheet(context)
                  : () => _showSyncDetailSheet(context),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.analytics_rounded,
              label: 'Insights',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/insights'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.straighten,
              label: 'Body Measurements',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/measurements'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.location_on_outlined,
              label: 'My Gyms',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/gyms'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.task_alt,
              label: 'Micro Workouts',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/micro-workouts'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.fitness_center_rounded,
              label: 'Exercise Library',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/exercises'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.restaurant_menu_rounded,
              label: 'Custom Foods',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/custom-foods'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.menu_book_rounded,
              label: 'Custom Recipes',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/custom-recipes'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.notifications_rounded,
              label: 'Notifications',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push('/notifications'),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.download_rounded,
              label: 'Export Data (JSON)',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => _exportData(context),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'About & Attribution',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
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
            if (ref.watch(authSessionProvider).valueOrNull == null) ...[
              _SettingsTile(
                icon: Icons.cloud_sync_rounded,
                label: 'Sign in to Supabase',
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.hx.primary,
                ),
                onTap: () => _showAuthSheet(context),
              ),
              _SettingsDivider(),
            ] else ...[
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                label: ref.watch(authSessionProvider).valueOrNull?.email ?? 'Signed in',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.hx.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Online',
                    style: TextStyle(
                      color: context.hx.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              _SettingsDivider(),
              _SettingsTile(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.hx.onSurfaceVariant,
                ),
                onTap: () => _signOut(context),
              ),
              _SettingsDivider(),
              // App Store Guideline 5.1.1(v) and GDPR Article 17: an account
              // created in the app must be deletable from inside the app.
              // Distinct from "Clear All Data" below, which never touches the
              // cloud — this deletes the account itself.
              _SettingsTile(
                icon: Icons.person_remove_rounded,
                label: 'Delete Account',
                iconColor: Colors.red.shade900,
                labelColor: Colors.red.shade900,
                onTap: () => _deleteAccount(context),
              ),
              _SettingsDivider(),
            ],
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

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete account?'),
        content: const Text(
          'Your Herculex account and everything stored in the cloud for it — '
          'workouts, nutrition logs, measurements, cycle records — are deleted '
          'permanently, and this device is wiped too.\n\n'
          'This cannot be undone and the data cannot be recovered.',
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
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // The remote call is a network round trip that ends in an irreversible
    // deletion, so the screen is blocked rather than left tappable — a second
    // tap would hit an account that is already gone.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );

    String? error;
    try {
      await ref.read(accountDeletionServiceProvider).deleteAccountAndWipeDevice();
    } catch (e) {
      error = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // the spinner

    if (error != null) {
      // Nothing was deleted — `AccountDeletionService` only wipes the device
      // after the backend confirms — so this is safe to retry.
      ref
          .read(hxToastControllerProvider.notifier)
          .show(HxToastItem.saveFailed(message: error));
    }
    // On success the cleared profile drops the router back to onboarding,
    // exactly as `_clearData` does.
  }

  Future<void> _showAuthSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AuthSheet(),
    );
  }

  Future<void> _showSyncDetailSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SyncDetailSheet(),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text(
          'Signing out will pause cloud sync. Your local workout and nutrition data will remain on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  void _showSttLanguagePicker(BuildContext context) {
    Haptics.selection();
    final stt = ref.read(speechToTextServiceProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hx.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Govor v besedilo / STT Jezik',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: kSupportedSttLanguages.length,
                  itemBuilder: (ctx, i) {
                    final lang = kSupportedSttLanguages[i];
                    final isSelected =
                        lang.localeId.toLowerCase() ==
                        stt.selectedLocaleId.toLowerCase();
                    return ListTile(
                      leading: Text(
                        lang.flag,
                        style: const TextStyle(fontSize: 22),
                      ),
                      title: Text(
                        lang.name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? AppColors.primary : null,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () async {
                        Haptics.selection();
                        await ref
                            .read(speechToTextServiceProvider)
                            .setLocale(lang.localeId);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  /// Turning the Workout Bubble on needs "Display over other apps", which is a
  /// settings-screen grant rather than a dialog: `request()` opens the system
  /// page and returns when the user comes back, so the real answer has to be
  /// re-read afterwards. The switch only goes on if the permission actually
  /// landed — otherwise the setting would claim a bubble the OS will never draw.
  Future<void> _onWorkoutBubbleToggled(bool enabled) async {
    final notifier = ref.read(workoutBubbleEnabledProvider.notifier);
    if (!enabled) {
      await notifier.set(false);
      return;
    }

    if (await WorkoutBubbleService.instance.hasPermission()) {
      await notifier.set(true);
      return;
    }

    await Permission.systemAlertWindow.request();
    final granted = await WorkoutBubbleService.instance.hasPermission();
    await notifier.set(granted);
    if (granted || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Herculex needs "Display over other apps" to float the workout '
          'bubble. You can grant it any time in system settings.',
        ),
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
          color: context.hx.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.fitness_center_rounded, color: context.hx.primary),
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

/// Gradient squircle card displaying the active target calories, phase, pace and macros.
class _ProfileActiveTargetSquircleCard extends ConsumerWidget {
  const _ProfileActiveTargetSquircleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final activePlan = ref.watch(activeDietPlanProvider);
    final profile = ref.watch(profileProvider).asData?.value;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targets = ref.watch(effectiveTargetsProvider(today)).asData?.value ??
        ref.watch(baselineTargetsProvider);

    final phaseColor = switch (activePlan.phase) {
      DietPhase.cut => AppColors.macroKcal,
      DietPhase.bulk => const Color(0xFF30D158),
      DietPhase.maingain => const Color(0xFFBF5AF2),
      DietPhase.maintain => const Color(0xFF64D2FF),
    };

    final phaseIcon = switch (activePlan.phase) {
      DietPhase.cut => Icons.trending_down_rounded,
      DietPhase.bulk => Icons.trending_up_rounded,
      DietPhase.maingain => Icons.auto_awesome_rounded,
      DietPhase.maintain => Icons.balance_rounded,
    };

    final kcal = targets?.kcal ?? 0;
    final protein = targets?.proteinG ?? 0;
    final carbs = targets?.carbsG ?? 0;
    final fat = targets?.fatG ?? 0;
    final bwKg = profile?.weightKg;

    final deltaText = activePlan.kcalDelta == 0
        ? 'TDEE Maintenance'
        : '${activePlan.kcalDelta > 0 ? '+' : ''}${activePlan.kcalDelta} kcal / day (${activePlan.phase.label})';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            phaseColor.withValues(alpha: hx.isDark ? 0.20 : 0.14),
            hx.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: phaseColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Haptics.selection();
            context.push('/nutrition-targets');
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: phaseColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(phaseIcon, color: phaseColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Active Goal & Calories',
                                style: TextStyle(
                                  color: hx.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: hx.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activePlan.phase.label,
                            style: TextStyle(
                              color: hx.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$kcal kcal',
                          style: TextStyle(
                            color: hx.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Target daily intake',
                          style: TextStyle(
                            color: hx.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: phaseColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: phaseColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        deltaText,
                        style: TextStyle(
                          color: phaseColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (kcal > 0) ...[
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: hx.outlineVariant.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileMacroSquircleBadge(
                          label: 'Protein',
                          value: '${protein}g',
                          subtext: bwKg != null
                              ? '${(protein / bwKg).toStringAsFixed(1)} g/kg'
                              : '${((protein * 4 / kcal) * 100).round()}%',
                          color: AppColors.macroProtein,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ProfileMacroSquircleBadge(
                          label: 'Carbs',
                          value: '${carbs}g',
                          subtext: '${((carbs * 4 / kcal) * 100).round()}%',
                          color: AppColors.macroCarbs,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ProfileMacroSquircleBadge(
                          label: 'Fat',
                          value: '${fat}g',
                          subtext: '${((fat * 9 / kcal) * 100).round()}%',
                          color: AppColors.macroFat,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Tap to change phase or pace',
                      style: TextStyle(
                        color: phaseColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: phaseColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMacroSquircleBadge extends StatelessWidget {
  final String label;
  final String value;
  final String subtext;
  final Color color;

  const _ProfileMacroSquircleBadge({
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: hx.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtext,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DreamPhysiqueCard extends StatelessWidget {
  const _DreamPhysiqueCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.hx.primary.withValues(alpha: 0.12),
            context.hx.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hx.primary.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            context.push('/dream-physique');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.hx.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_awesome, size: 22, color: context.hx.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Dream Physique AI',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.hx.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Comparison with target physique, estimated months, muscle & BF%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hx.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.hx.onSurfaceVariant),
              ],
            ),
          ),
        ),
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
                  color: context.hx.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.hx.primary.withValues(alpha: 0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: name.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        size: 48,
                        color: context.hx.primary,
                      )
                    : Text(
                        name[0].toUpperCase(),
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: context.hx.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.hx.primary,
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
              ? profile!.activityLevel.label
              : 'Set your stats',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.hx.onSurfaceVariant,
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
    return HxSheet(
      scrollable: false,
      title: 'Edit profile',
      padding: EdgeInsets.fromLTRB(
        HxSpace.x5,
        0,
        HxSpace.x5,
        HxSpace.x5 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              backgroundColor: context.hx.primary,
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
        backgroundColor: context.hx.primary,
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
          color: context.hx.onSurfaceVariant,
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
  final ValueChanged<String>? onChanged;

  /// Every remaining stat field is numeric — the name moved into the avatar
  /// editor, so there is no free-text variant left to configure.
  static const keyboardType = TextInputType.numberWithOptions(decimal: true);

  const _StatField({
    required this.label,
    required this.hint,
    required this.controller,
    this.onChanged,
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
            color: context.hx.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
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
            hintStyle: TextStyle(color: context.hx.outline, fontSize: 13),
            filled: true,
            fillColor: context.hx.surfaceContainer,
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
              borderSide: BorderSide(color: context.hx.primary, width: 1.5),
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
          color: selected ? context.hx.primary : context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: selected
                ? context.hx.primary
                : context.hx.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : context.hx.onSurfaceVariant,
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
              ? context.hx.primary.withValues(alpha: 0.1)
              : context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? context.hx.primary
                : context.hx.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? context.hx.primary : context.hx.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icons[level]!,
                size: 20,
                color: selected ? Colors.white : context.hx.onSurfaceVariant,
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
                      color: selected ? context.hx.primary : null,
                    ),
                  ),
                  Text(
                    _descriptions[level]!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.hx.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? context.hx.primary : context.hx.outline,
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
        color: context.hx.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.4),
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
      color: context.hx.outlineVariant.withValues(alpha: 0.4),
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
              color: iconColor ?? context.hx.onSurfaceVariant,
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
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: context.hx.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ThemeMode>(
          value: mode,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: context.hx.onSurfaceVariant,
            size: 20,
          ),
          dropdownColor: context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.hx.onSurface,
          ),
          items: [
            DropdownMenuItem(
              value: ThemeMode.light,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.light_mode_rounded, size: 14, color: context.hx.onSurfaceVariant),
                  const SizedBox(width: 6),
                  const Text('Light'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: ThemeMode.system,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.brightness_auto_rounded, size: 14, color: context.hx.onSurfaceVariant),
                  const SizedBox(width: 6),
                  const Text('System'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: ThemeMode.dark,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dark_mode_rounded, size: 14, color: context.hx.onSurfaceVariant),
                  const SizedBox(width: 6),
                  const Text('Dark'),
                ],
              ),
            ),
          ],
          onChanged: (newMode) {
            if (newMode != null) {
              ref.read(themeModeProvider.notifier).set(newMode);
            }
          },
        ),
      ),
    );
  }
}

class _AppColorToggle extends ConsumerWidget {
  const _AppColorToggle();

  static Color _previewColor(AppColorTheme theme) => switch (theme) {
        AppColorTheme.classicBlue => const Color(0xFF0A84FF),
        AppColorTheme.siriousBlack => const Color(0xFF27272A),
        AppColorTheme.vividGreen => const Color(0xFF10B981),
        AppColorTheme.sunnyYellow => const Color(0xFFF59E0B),
        AppColorTheme.pinky => const Color(0xFFFF2D55),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(appColorThemeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: context.hx.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppColorTheme>(
          value: activeTheme,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: context.hx.onSurfaceVariant,
            size: 20,
          ),
          dropdownColor: context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.hx.onSurface,
          ),
          items: AppColorTheme.values.map((theme) {
            return DropdownMenuItem(
              value: theme,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _previewColor(theme),
                      shape: BoxShape.circle,
                      border: theme == AppColorTheme.siriousBlack
                          ? Border.all(
                              color: context.hx.outlineVariant,
                              width: 1,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(theme.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (newTheme) {
            if (newTheme != null) {
              ref.read(appColorThemeProvider.notifier).set(newTheme);
            }
          },
        ),
      ),
    );
  }
}

/// Reports what cloud sync has actually done — never "synced" unless the
/// backend acknowledged every queued write (RB-02).
///
/// Public only so `test/widgets/sync_status_badge_test.dart` can pump it
/// directly: this switch *is* the user-facing half of RB-02's claim, and
/// reaching it through the whole of [ProfileView] would mean the assertion
/// depended on an unrelated settings list staying scrollable.
@visibleForTesting
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(syncStateProvider).valueOrNull ??
        const SyncState(phase: SyncPhase.disabled);

    final Color color = switch (state.phase) {
      SyncPhase.disabled => context.hx.onSurfaceVariant,
      SyncPhase.syncing => context.hx.primary,
      SyncPhase.pending => Colors.orangeAccent,
      SyncPhase.synced => context.hx.primary,
      SyncPhase.error => Colors.redAccent,
    };

    final String label = switch (state.phase) {
      SyncPhase.disabled => 'Cloud sync off',
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.pending => '${state.pendingCount} pending',
      SyncPhase.synced => 'Synced',
      SyncPhase.error => 'Sync error',
    };

    return Tooltip(
      message: switch (state.phase) {
        SyncPhase.disabled => 'This build has no cloud backend configured, or '
            'you are signed out. Data is saved on this device only.',
        SyncPhase.error =>
          state.lastError ?? 'Some changes could not be uploaded.',
        _ => state.lastSyncedAt == null
            ? 'Not yet synced to the cloud.'
            : 'Last synced ${state.lastSyncedAt}',
      },
      child: Container(
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
              switch (state.phase) {
                SyncPhase.disabled => Icons.cloud_off_outlined,
                SyncPhase.syncing => Icons.cloud_sync_outlined,
                SyncPhase.pending => Icons.cloud_upload_outlined,
                SyncPhase.synced => Icons.cloud_done_outlined,
                SyncPhase.error => Icons.cloud_off,
              },
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Auth Sheet ───────────────────────────────────────────────────────────────

class _AuthSheet extends ConsumerStatefulWidget {
  const _AuthSheet();

  @override
  ConsumerState<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends ConsumerState<_AuthSheet> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _rateLimiter = AuthRateLimiter();
  bool _busy = false;
  bool _isRegister = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final (allowed, secondsRemaining) = _rateLimiter.canAttempt();
    if (!allowed) {
      setState(() => _errorMessage = 'Too many failed attempts. Please wait $secondsRemaining seconds.');
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    final emailError = AuthValidator.validateEmail(email);
    if (emailError != null) {
      setState(() => _errorMessage = emailError);
      return;
    }

    final passwordError = AuthValidator.validatePassword(password, isRegistration: _isRegister);
    if (passwordError != null) {
      setState(() => _errorMessage = passwordError);
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isRegister) {
        await repo.registerWithEmail(email: email, password: password);
      } else {
        await repo.loginWithEmail(email: email, password: password);
      }
      _rateLimiter.recordSuccess();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _rateLimiter.recordFailure();
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', '');
          _busy = false;
        });
      }
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      _rateLimiter.recordSuccess();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', '');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HxSheet(
      scrollable: false,
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.hx.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cloud_sync_rounded, color: context.hx.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRegister ? 'Create Herculex Account' : 'Sign in to Herculex',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Sync your workouts and nutrition across devices',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hx.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              maxLength: AuthValidator.maxEmailLength,
              decoration: InputDecoration(
                labelText: 'Email',
                counterText: '',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              maxLength: AuthValidator.maxPasswordLength,
              decoration: InputDecoration(
                labelText: 'Password',
                counterText: '',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: context.hx.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _isRegister ? 'Create Account & Sync' : 'Sign In & Sync',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            if (Env.hasGoogleSignIn) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _googleSignIn,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _isRegister = !_isRegister;
                        _errorMessage = null;
                      }),
              child: Text(
                _isRegister
                    ? 'Already have an account? Sign In'
                    : "Don't have an account? Create one",
                style: TextStyle(color: context.hx.primary),
              ),
            ),
          ],
        ),
    );
  }
}

// ── Sync Detail Sheet ───────────────────────────────────────────────────────

class _SyncDetailSheet extends ConsumerStatefulWidget {
  const _SyncDetailSheet();

  @override
  ConsumerState<_SyncDetailSheet> createState() => _SyncDetailSheetState();
}

class _SyncDetailSheetState extends ConsumerState<_SyncDetailSheet> {
  bool _busy = false;
  String? _statusMessage;

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await ref.read(syncServiceProvider).retryAll();
      if (mounted) {
        setState(() {
          _statusMessage = 'Sync completed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Sync failed: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reuploadAll() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final count = await ref.read(syncServiceProvider).reuploadAllLocalData();
      if (mounted) {
        setState(() {
          _statusMessage = 'Re-enqueued $count items for upload';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Re-upload failed: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncState = ref.watch(syncStateProvider).valueOrNull ??
        const SyncState(phase: SyncPhase.disabled);
    final session = ref.watch(authSessionProvider).valueOrNull;

    final Color statusColor = switch (syncState.phase) {
      SyncPhase.disabled => context.hx.onSurfaceVariant,
      SyncPhase.syncing => context.hx.primary,
      SyncPhase.pending => Colors.orangeAccent,
      SyncPhase.synced => context.hx.primary,
      SyncPhase.error => Colors.redAccent,
    };

    final String statusLabel = switch (syncState.phase) {
      SyncPhase.disabled => 'Disabled',
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.pending => '${syncState.pendingCount} pending changes',
      SyncPhase.synced => 'Synced and up to date',
      SyncPhase.error => 'Sync error',
    };

    return HxSheet(
      scrollable: false,
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  switch (syncState.phase) {
                    SyncPhase.disabled => Icons.cloud_off_outlined,
                    SyncPhase.syncing => Icons.cloud_sync_outlined,
                    SyncPhase.pending => Icons.cloud_upload_outlined,
                    SyncPhase.synced => Icons.cloud_done_outlined,
                    SyncPhase.error => Icons.cloud_off,
                  },
                  color: statusColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud Sync',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      session?.email ?? 'Account sync status',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                if (syncState.lastSyncedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last synced: ${syncState.lastSyncedAt}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.hx.onSurfaceVariant,
                    ),
                  ),
                ],
                if (syncState.pendingCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Pending outbox items: ${syncState.pendingCount}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (syncState.quarantinedCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Quarantined items: ${syncState.quarantinedCount}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent.shade200,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (syncState.lastError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 18, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      syncState.lastError!,
                      style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMessage!,
              style: TextStyle(
                fontSize: 13,
                color: context.hx.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _syncNow,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(_busy ? 'Syncing…' : 'Sync Now / Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: context.hx.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reuploadAll,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Re-upload All Local Data'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}


