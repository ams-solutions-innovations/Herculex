part of '../profile_view.dart';

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
  late String _herculTone;

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
    _herculTone = p?.herculTone ?? 'normal';
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
      _herculTone = p?.herculTone ?? 'normal';
      if (_nameCtrl.text != (p?.name ?? '')) {
        _nameCtrl.text = p?.name ?? '';
      }
      if (_ageCtrl.text != (p?.ageYears?.toString() ?? '')) {
        _ageCtrl.text = p?.ageYears?.toString() ?? '';
      }
      final weightFmt = ref.read(weightFormatProvider);
      final heightFmt = ref.read(heightFormatProvider);
      final weightStr = p?.weightKg == null
          ? ''
          : weightFmt.formatValue(p!.weightKg!);
      final targetKg = p?.targetWeightKg ?? ref.read(goalWeightProvider);
      final targetStr = targetKg == null ? '' : weightFmt.formatValue(targetKg);
      final heightStr = p?.heightCm == null
          ? ''
          : heightFmt.formatValue(p!.heightCm!);
      if (_weightCtrl.text != weightStr) _weightCtrl.text = weightStr;
      if (_targetWeightCtrl.text != targetStr)
        _targetWeightCtrl.text = targetStr;
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
    final targetKg =
        widget.profile?.targetWeightKg ?? ref.read(goalWeightProvider);
    final cm = widget.profile?.heightCm;
    _weightCtrl.text = kg == null ? '' : weightFmt.formatValue(kg);
    _targetWeightCtrl.text = targetKg == null
        ? ''
        : weightFmt.formatValue(targetKg);
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
      herculTone: _herculTone,
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
    ref
        .read(hxToastControllerProvider.notifier)
        .show(HxToastItem.profileSaved());
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
              icon: Icons.psychology_outlined,
              label: 'Honest Hercul (18+)',
              trailing: Switch(
                value: _herculTone == 'honest',
                onChanged: (val) async {
                  if (val) {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Enable Honest Hercul?'),
                        content: const Text(
                          'Honest Hercul uses blunt, unfiltered language about '
                          'training and consistency. It may contain profanity. '
                          'Are you 18 or older?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Yes, I am 18+'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                  }
                  setState(() => _herculTone = val ? 'honest' : 'normal');
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
              onTap: () => context.push(AppRoutes.goals),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.health_and_safety_rounded,
              label: 'Health Integrations',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.health),
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
              onTap: () => context.push(AppRoutes.insights),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.straighten,
              label: 'Body Measurements',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.measurements),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.location_on_outlined,
              label: 'My Gyms',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.gyms),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.task_alt,
              label: 'Micro Workouts',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.microWorkouts),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.fitness_center_rounded,
              label: 'Exercise Library',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.exercises),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.restaurant_menu_rounded,
              label: 'Custom Foods',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.customFoods),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.menu_book_rounded,
              label: 'Custom Recipes',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.customRecipes),
            ),
            _SettingsDivider(),
            _SettingsTile(
              icon: Icons.notifications_rounded,
              label: 'Notifications',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => context.push(AppRoutes.notifications),
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
                trailing: Icon(Icons.chevron_right, color: context.hx.primary),
                onTap: () => _showAuthSheet(context),
              ),
              _SettingsDivider(),
            ] else ...[
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                label:
                    ref.watch(authSessionProvider).valueOrNull?.email ??
                    'Signed in',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
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
      await ref
          .read(accountDeletionServiceProvider)
          .deleteAccountAndWipeDevice();
    } catch (e) {
      error = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : '$e';
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
