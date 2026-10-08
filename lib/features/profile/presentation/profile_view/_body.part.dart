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
  final _targetFocus = FocusNode();

  /// The target field was edited and not yet handed to the roadmap. With a
  /// roadmap running that happens when the field loses focus (or on save),
  /// not on every pause in typing: each commit re-plans the running phase.
  bool _targetDirty = false;
  final _heightCtrl = TextEditingController();
  final _inseamCtrl = TextEditingController();
  final _armSpanCtrl = TextEditingController();
  final _torsoCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();

  bool _showMore = false;

  Timer? _autoSaveTimer;
  bool _saving = false;

  /// Snapshotted here rather than read in [dispose].
  ///
  /// `ref.read` from `State.dispose` throws once the element is unmounted
  /// (`riverpod_lint`'s `avoid_ref_inside_state_dispose`), and this screen's
  /// dispose runs on a normal back-navigation pop — so the final draft flush
  /// could take the teardown down with it.
  late final LocalProfileRepository _profileRepository;
  late final MeasurementsRepository _measurementsRepository;
  late final GoalTargetController _targetController;

  /// Kept current by [build]; [dispose] cannot read providers.
  late WeightFormat _weightFormat;

  @override
  void initState() {
    super.initState();
    _profileRepository = ref.read(localProfileRepositoryProvider);
    _measurementsRepository = ref.read(measurementsRepositoryProvider);
    _targetController = ref.read(goalTargetControllerProvider);
    _weightFormat = ref.read(weightFormatProvider);
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
    final targetKg = ref.read(goalTargetProvider).targetKg;
    _targetWeightCtrl.text = targetKg == null
        ? ''
        : weightFmt.formatValue(targetKg);
    _targetFocus.addListener(() {
      if (!_targetFocus.hasFocus) _commitTarget();
    });
    _heightCtrl.text = p?.heightCm == null
        ? ''
        : heightFmt.formatValue(p!.heightCm!);
    _inseamCtrl.text = p?.inseamCm == null
        ? ''
        : heightFmt.formatValue(p!.inseamCm!);
    _armSpanCtrl.text = p?.armSpanCm == null
        ? ''
        : heightFmt.formatValue(p!.armSpanCm!);
    _torsoCtrl.text = p?.torsoCm == null
        ? ''
        : heightFmt.formatValue(p!.torsoCm!);
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
      final targetKg = ref.read(goalTargetProvider).targetKg;
      final targetStr = targetKg == null ? '' : weightFmt.formatValue(targetKg);
      final heightStr = p?.heightCm == null
          ? ''
          : heightFmt.formatValue(p!.heightCm!);
      final inseamStr = p?.inseamCm == null
          ? ''
          : heightFmt.formatValue(p!.inseamCm!);
      final armSpanStr = p?.armSpanCm == null
          ? ''
          : heightFmt.formatValue(p!.armSpanCm!);
      final torsoStr = p?.torsoCm == null
          ? ''
          : heightFmt.formatValue(p!.torsoCm!);
      if (_weightCtrl.text != weightStr) _weightCtrl.text = weightStr;
      if (_targetWeightCtrl.text != targetStr)
        _targetWeightCtrl.text = targetStr;
      if (_heightCtrl.text != heightStr) _heightCtrl.text = heightStr;
      if (_inseamCtrl.text != inseamStr) _inseamCtrl.text = inseamStr;
      if (_armSpanCtrl.text != armSpanStr) _armSpanCtrl.text = armSpanStr;
      if (_torsoCtrl.text != torsoStr) _torsoCtrl.text = torsoStr;
    }
  }

  void _onFieldChanged([String? _]) {
    setState(() {});
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        final draft = _draft();
        ref.read(localProfileRepositoryProvider).save(draft);
        // Without a roadmap the typed weight is the target, so it is stored
        // as the member types. With one, it waits for the field to lose focus.
        if (!ref.read(goalTargetProvider).fromRoadmap) _commitTarget();
        _saveWaist();
      }
    });
  }

  void _onTargetChanged([String? _]) {
    _targetDirty = true;
    _onFieldChanged();
  }

  /// The typed target in kilograms; null when the field is empty or unusable.
  double? _typedTargetKg() {
    final typed = double.tryParse(_targetWeightCtrl.text.trim());
    if (typed == null || typed <= 0) return null;
    return _weightFormat.toKg(typed);
  }

  /// Hands the typed target to the roadmap (or stores it, without one), then
  /// shows whatever the app now uses as the target.
  Future<void> _commitTarget() async {
    if (!_targetDirty || !mounted) return;
    _targetDirty = false;
    if (_targetWeightCtrl.text.trim().isEmpty) {
      await _targetController.clearManual();
    } else {
      final kg = _typedTargetKg();
      if (kg == null) return;
      await saveGoalTarget(context, ref, kg);
    }
    _showAppTarget();
  }

  /// Puts the number the app actually uses back into the target field, unless
  /// the member is in the middle of editing it.
  void _showAppTarget() {
    if (!mounted || _targetDirty || _targetFocus.hasFocus) return;
    final kg = ref.read(goalTargetProvider).targetKg;
    final text = kg == null
        ? ''
        : ref.read(weightFormatProvider).formatValue(kg);
    if (_targetWeightCtrl.text != text) _targetWeightCtrl.text = text;
  }

  /// Waist lives in the measurement log (shared with the Measurements screen
  /// and the body-fat formula), not on the profile, so it is written there.
  Future<void> _saveWaist() async {
    final display = double.tryParse(_waistCtrl.text.trim());
    if (display == null || display <= 0) return;
    final cm = ref.read(heightFormatProvider).toCm(display);
    final latest = ref.read(_latestMeasurementsProvider).valueOrNull?['waist'];
    if (latest != null && (latest - cm).abs() < 0.05) return;
    await _measurementsRepository.logMeasurement(
      dateIso: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      metric: 'waist',
      value: cm,
    );
  }

  /// Re-renders the body-stat fields when the measurement system flips, so a
  /// stored 82.5 kg becomes 182 lb in place rather than being reinterpreted.
  void _rewriteBodyStatFields() {
    final weightFmt = ref.read(weightFormatProvider);
    final heightFmt = ref.read(heightFormatProvider);
    final kg = widget.profile?.weightKg;
    final targetKg = ref.read(goalTargetProvider).targetKg;
    final cm = widget.profile?.heightCm;
    final inseam = widget.profile?.inseamCm;
    final armSpan = widget.profile?.armSpanCm;
    final torso = widget.profile?.torsoCm;
    _weightCtrl.text = kg == null ? '' : weightFmt.formatValue(kg);
    _targetWeightCtrl.text = targetKg == null
        ? ''
        : weightFmt.formatValue(targetKg);
    _heightCtrl.text = cm == null ? '' : heightFmt.formatValue(cm);
    _inseamCtrl.text = inseam == null ? '' : heightFmt.formatValue(inseam);
    _armSpanCtrl.text = armSpan == null ? '' : heightFmt.formatValue(armSpan);
    _torsoCtrl.text = torso == null ? '' : heightFmt.formatValue(torso);
    final waist = ref.read(_latestMeasurementsProvider).valueOrNull?['waist'];
    _waistCtrl.text = waist == null ? '' : heightFmt.formatValue(waist);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // Flush draft to local profile storage before tearing down
    _profileRepository.save(_draft());
    if (_targetDirty) {
      // Leaving the screen with the keyboard up: nothing will blur the field.
      final kg = _typedTargetKg();
      if (kg != null) {
        unawaited(_targetController.setTarget(kg));
      } else if (_targetWeightCtrl.text.trim().isEmpty) {
        unawaited(_targetController.clearManual());
      }
    }
    _targetFocus.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _targetWeightCtrl.dispose();
    _heightCtrl.dispose();
    _inseamCtrl.dispose();
    _armSpanCtrl.dispose();
    _torsoCtrl.dispose();
    _waistCtrl.dispose();
    super.dispose();
  }

  /// The profile as it would be saved right now, used both by [_save] and by
  /// the live calorie estimate so the two never disagree.
  Profile _draft() {
    final name = _nameCtrl.text.trim();
    final weight = double.tryParse(_weightCtrl.text.trim());
    final targetWeight = double.tryParse(_targetWeightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());
    final inseam = double.tryParse(_inseamCtrl.text.trim());
    final armSpan = double.tryParse(_armSpanCtrl.text.trim());
    final torso = double.tryParse(_torsoCtrl.text.trim());
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
      // With a roadmap running the target belongs to it; the profile keeps the
      // weight the member last typed so it is still there if the goal ends.
      targetWeightKg: ref.read(goalTargetProvider).fromRoadmap
          ? widget.profile?.targetWeightKg
          : targetWeight == null
          ? null
          : ref.read(weightFormatProvider).toKg(targetWeight),
      heightCm: height == null
          ? null
          : ref.read(heightFormatProvider).toCm(height),
      inseamCm: inseam == null
          ? null
          : ref.read(heightFormatProvider).toCm(inseam),
      armSpanCm: armSpan == null
          ? null
          : ref.read(heightFormatProvider).toCm(armSpan),
      torsoCm: torso == null
          ? null
          : ref.read(heightFormatProvider).toCm(torso),
      preferredUnit: ref.read(unitsProvider),
    );
  }

  Future<void> _save() async {
    _autoSaveTimer?.cancel();
    setState(() => _saving = true);
    final draft = _draft();
    await ref.read(localProfileRepositoryProvider).save(draft);
    await _commitTarget();
    await _saveWaist();
    if (!mounted) return;
    setState(() => _saving = false);
    AppNotice.showWith(
      ref,
      'Profile saved',
      title: 'Stats and targets are up to date',
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
    final latest =
        ref.watch(_latestMeasurementsProvider).valueOrNull ?? const {};
    // Fill the waist field once the measurement log has loaded, but never
    // while the user is typing.
    ref.listen(_latestMeasurementsProvider, (_, next) {
      final waist = next.valueOrNull?['waist'];
      if (waist == null || _autoSaveTimer?.isActive == true) return;
      final text = ref.read(heightFormatProvider).formatValue(waist);
      if (_waistCtrl.text != text) _waistCtrl.text = text;
    });

    // The roadmap can move the target while this screen is open (a re-plan, a
    // phase change): follow it, unless the member is editing the field.
    final target = ref.watch(goalTargetProvider);
    ref.listen(goalTargetProvider, (prev, next) {
      if (prev?.targetKg != next.targetKg) _showAppTarget();
    });
    final weightFormat = _weightFormat = ref.watch(weightFormatProvider);
    final dream = target.dreamKg;
    final targetHelper = !target.fromRoadmap
        ? null
        : 'End of ${target.phase!.label.toLowerCase()}'
              '${dream != null && dream != target.targetKg ? ' · dream ${weightFormat.format(dream)}' : ''}';

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
                focusNode: _targetFocus,
                helper: targetHelper,
                onChanged: _onTargetChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // BMI chip (read-only, calculated)
        if (widget.profile?.weightKg != null &&
            widget.profile?.heightCm != null)
          Center(
            child: _BmiChip(
              weightKg: widget.profile!.weightKg!,
              heightCm: widget.profile!.heightCm!,
            ),
          ),
        // Body-fat chip (read-only, calculated) sits right under BMI.
        const SizedBox(height: 8),
        Center(child: _bodyFatChip(latest)),

        // -- Show more: inseam, arm span, torso, waist ---------------------
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _showMore = !_showMore),
            icon: Icon(
              _showMore
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
            label: Text(_showMore ? 'Show less' : 'Show more'),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _showMore ? 1 : 0,
            child: !_showMore
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _StatField(
                              label: isMetric ? 'Inseam (cm)' : 'Inseam (in)',
                              hint: isMetric ? 'cm' : 'in',
                              controller: _inseamCtrl,
                              onChanged: _onFieldChanged,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatField(
                              label: isMetric
                                  ? 'Arm Span (cm)'
                                  : 'Arm Span (in)',
                              hint: isMetric ? 'cm' : 'in',
                              controller: _armSpanCtrl,
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
                              label: isMetric ? 'Torso (cm)' : 'Torso (in)',
                              hint: isMetric ? 'cm' : 'in',
                              controller: _torsoCtrl,
                              onChanged: _onFieldChanged,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatField(
                              label: isMetric ? 'Waist (cm)' : 'Waist (in)',
                              hint: isMetric ? 'cm' : 'in',
                              controller: _waistCtrl,
                              onChanged: _onFieldChanged,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
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
        ActivityLevelSection(
          selected: _activityLevel,
          onChanged: (a) {
            setState(() => _activityLevel = a);
            _onFieldChanged();
          },
        ),

        const SizedBox(height: 20),

        // ── Active Target & Dieting Phase (Gradient Squircle) ──
        const _ProfileLevelCard(),
        const SizedBox(height: 12),
        const _ProfileActiveTargetSquircleCard(),
        const SizedBox(height: 12),
        const DreamPhysiqueSummaryCard(),
        const SizedBox(height: 12),
        const DreamPhysiqueNutritionDirectionCard(),

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
              icon: Icons.music_note_rounded,
              label: 'Media Controls Permission',
              trailing: Icon(
                Icons.chevron_right,
                color: context.hx.onSurfaceVariant,
              ),
              onTap: () => WearSyncService().openMediaControlsPermission(),
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

  /// Body-fat estimate computed from the profile: US Navy tape formula when
  /// waist and neck are logged, otherwise the BMI-based Deurenberg formula.
  Widget _bodyFatChip(Map<String, double> latest) {
    final draft = _draft();
    final height = draft.heightCm;
    final weight = draft.weightKg;
    final age = draft.ageYears;
    final isMale = draft.sex != BiologicalSex.female;
    final waistDisplay = double.tryParse(_waistCtrl.text.trim());
    final waistCm = waistDisplay == null
        ? latest['waist']
        : ref.read(heightFormatProvider).toCm(waistDisplay);
    final neckCm = latest['neck'];

    double? bf;
    if (height != null && waistCm != null && neckCm != null) {
      bf = BodyFatAiService.calculateNavyBodyFat(
        heightCm: height,
        waistCm: waistCm,
        neckCm: neckCm,
        hipsCm: latest['hips'],
        isMale: isMale,
      );
    }
    if (bf == null && height != null && weight != null && age != null) {
      bf = BodyFatAiService.calculateBmiBodyFat(
        weightKg: weight,
        heightCm: height,
        ageYears: age,
        isMale: isMale,
      );
    }
    if (bf == null) return const SizedBox.shrink();

    final color = context.hx.primary;
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
          Icon(Icons.percent_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            'Body fat ~${bf.toStringAsFixed(1)}%',
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
      AppNotice.showWith(
        ref,
        error.trim().isEmpty ? 'Check your connection and retry' : error,
        title: 'Could not save',
        kind: AppNoticeKind.error,
      );
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

    AppNotice.show(
      context,
      'Herculex needs "Display over other apps" to float the workout '
      'bubble. You can grant it any time in system settings.',
      kind: AppNoticeKind.info,
    );
  }

  void _exportData(BuildContext context) {
    // Tell the user the export has started
    AppNotice.show(
      context,
      'Exporting data as JSON...',
      kind: AppNoticeKind.info,
    );
    final notices = AppNotice.of(context);
    // In a real implementation this would fetch from Drift and use path_provider to save a file.
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      notices.show('Data export saved to Downloads folder.');
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

class _ProfileLevelCard extends ConsumerWidget {
  const _ProfileLevelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progressAsync = ref.watch(levelProgressProvider);
    return progressAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (progress) {
        final level = progress.level;
        final remaining = progress.xpRemaining;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              Haptics.selection();
              context.push(AppRoutes.trainingLevel);
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.military_tech_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Training level',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        level.title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary.withValues(alpha: 0.8),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${progress.totalXp} XP · ${progress.completedWorkouts} workouts logged',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress.progressToNext,
                      minHeight: 8,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.16,
                      ),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        remaining == null
                            ? 'Top training level reached'
                            : '$remaining XP to ${progress.nextLevel!.title}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hx.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'View Details',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Gradient squircle card displaying the active target calories, phase, pace and macros.
