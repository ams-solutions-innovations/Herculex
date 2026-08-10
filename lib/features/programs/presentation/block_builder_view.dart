import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../../widgets/glass_container.dart';
import '../../../widgets/premium_button.dart';
import '../../../widgets/premium_text_field.dart';
import '../../workouts/presentation/workouts_providers.dart';
import '../domain/periodization.dart';
import '../domain/split_template.dart';
import 'programs_providers.dart';
import 'template_picker_sheet.dart';

/// Four-step block builder: basics → split → content → schedule.
///
/// Step 3 attaches *real* workout templates to each split slot. The previous
/// version offered a list of seven hardcoded strings labelled "CHOOSE TEMPLATE"
/// and wrote them into the day name, so every block it built materialized
/// sessions with no exercises at all.
class BlockBuilderView extends ConsumerStatefulWidget {
  const BlockBuilderView({super.key});

  @override
  ConsumerState<BlockBuilderView> createState() => _BlockBuilderViewState();
}

class _BlockBuilderViewState extends ConsumerState<BlockBuilderView> {
  static const _stepCount = 4;

  int _step = 1;
  bool _saving = false;

  // Step 1
  final _nameCtrl = TextEditingController();
  int _weeks = 8;
  PeriodizationModel _model = PeriodizationModel.linear;

  // Step 2
  SplitType _split = SplitType.upperLower;
  int _daysPerWeek = SplitType.upperLower.defaultDaysPerWeek;
  ScheduleMode _mode = ScheduleMode.weekly;
  int _cycleLength = 5;

  // Step 3 — template per split slot.
  final Map<int, int?> _templatesBySlot = {};

  // Step 4
  DateTime _startDate = _today();
  DateTimeRange? _vacation;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  SplitPlan get _plan => SplitTemplates.generate(
    type: _split,
    daysPerWeek: _daysPerWeek,
    mode: _mode,
    cycleLength: _mode == ScheduleMode.cycle ? _cycleLength : null,
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _effectiveName {
    final typed = _nameCtrl.text.trim();
    if (typed.isNotEmpty) return typed;
    return '$_weeks-week ${_split.label}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'New block',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          _stepIndicator(theme),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                switch (_step) {
                  1 => _stepBasics(theme),
                  2 => _stepSplit(theme),
                  3 => _stepContent(theme),
                  _ => _stepSchedule(theme),
                },
              ],
            ),
          ),
          _footer(theme),
        ],
      ),
    );
  }

  Widget _stepIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          for (var i = 1; i <= _stepCount; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i == _stepCount ? 0 : 6),
                decoration: BoxDecoration(
                  color: i <= _step
                      ? AppColors.primary
                      : AppColors.outlineVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Step 1: basics ─────────────────────────────────────────────────────────

  Widget _stepBasics(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(theme, 'Basics', 'Name it and choose how long it runs.'),
        _sectionLabel(theme, 'Block name'),
        PremiumTextField(controller: _nameCtrl, hintText: _effectiveName),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Length'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in const [4, 6, 8, 12, 16, 24])
              _choiceChip(
                label: '$w weeks',
                selected: _weeks == w,
                onTap: () => setState(() => _weeks = w),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Periodization'),
        for (final model in PeriodizationModel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _radioCard(
              theme,
              title: model.label,
              subtitle: _modelDescriptions[model]!,
              selected: _model == model,
              onTap: () => setState(() => _model = model),
            ),
          ),
      ],
    );
  }

  static const _modelDescriptions = {
    PeriodizationModel.none:
        'Flat load across all weeks. You control progression manually.',
    PeriodizationModel.linear:
        'Intensity rises ~2.5%/week; volume tapers. Deload every 4th week.',
    PeriodizationModel.concurrent:
        'All qualities trained together on a heavy/medium/light wave.',
    PeriodizationModel.block:
        'Accumulation → Transmutation → Realization, peaking to high intensity.',
    PeriodizationModel.maxEffort:
        'Westside-style: work up to a heavy single each session; rotate the lift.',
  };

  // ── Step 2: split ──────────────────────────────────────────────────────────

  Widget _stepSplit(ThemeData theme) {
    final plan = _plan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          'Split',
          'Pick the shape of the week — or a rotation that ignores weekdays.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in SplitType.values)
              _choiceChip(
                label: type.label,
                selected: _split == type,
                onTap: () => setState(() {
                  _split = type;
                  _daysPerWeek = type.defaultDaysPerWeek;
                  _templatesBySlot.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionLabel(
          theme,
          _mode == ScheduleMode.weekly
              ? 'Training days per week'
              : 'Training days per cycle',
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: _daysPerWeek <= 1
                  ? null
                  : () => setState(() {
                      _daysPerWeek--;
                      _templatesBySlot.clear();
                    }),
            ),
            Expanded(
              child: Text(
                '$_daysPerWeek',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed:
                  _daysPerWeek >= (_mode == ScheduleMode.weekly ? 7 : 10)
                  ? null
                  : () => setState(() {
                      _daysPerWeek++;
                      if (_cycleLength <= _daysPerWeek) {
                        _cycleLength = _daysPerWeek + 1;
                      }
                      _templatesBySlot.clear();
                    }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel(theme, 'Repeat'),
        Row(
          children: [
            Expanded(
              child: _radioCard(
                theme,
                title: 'Weekly',
                subtitle: 'Fixed weekdays, repeating every 7 days.',
                selected: _mode == ScheduleMode.weekly,
                onTap: () => setState(() => _mode = ScheduleMode.weekly),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _radioCard(
                theme,
                title: 'Cycle',
                subtitle: 'N-on / N-off, drifting across the calendar.',
                selected: _mode == ScheduleMode.cycle,
                onTap: () => setState(() {
                  _mode = ScheduleMode.cycle;
                  if (_cycleLength <= _daysPerWeek) {
                    _cycleLength = _daysPerWeek + 1;
                  }
                }),
              ),
            ),
          ],
        ),
        if (_mode == ScheduleMode.cycle) ...[
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Cycle length'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var len = _daysPerWeek; len <= _daysPerWeek + 4; len++)
                if (len >= 1)
                  _choiceChip(
                    label: '$len days',
                    selected: _cycleLength == len,
                    onTap: () => setState(() => _cycleLength = len),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_daysPerWeek on, ${_cycleLength - _daysPerWeek} off — repeating '
            'every $_cycleLength days regardless of the weekday.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Preview'),
        _planPreview(theme, plan),
      ],
    );
  }

  Widget _planPreview(ThemeData theme, SplitPlan plan) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          if (plan.mode == ScheduleMode.weekly)
            for (var i = 0; i < 7; i++)
              _previewRow(
                theme,
                weekdays[i],
                plan.days
                    .where((d) => d.index == i)
                    .map((d) => d.label)
                    .join(', '),
              )
          else
            for (final day in plan.days)
              _previewRow(
                theme,
                'Day ${day.index + 1}',
                day.isRest ? '' : day.label,
              ),
        ],
      ),
    );
  }

  Widget _previewRow(ThemeData theme, String slot, String label) {
    final isRest = label.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              slot,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              isRest ? 'Rest' : label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isRest ? FontWeight.w400 : FontWeight.w600,
                color: isRest ? AppColors.outlineVariant : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: content ────────────────────────────────────────────────────────

  Widget _stepContent(ThemeData theme) {
    final slots = _plan.slotSummary;
    final templates = ref.watch(workoutTemplatesProvider(-1)).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          'Content',
          'Attach one of your templates to each day. The link stays live — edit '
              'the template later and every future session follows.',
        ),
        for (final slot in slots)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _slotCard(theme, slot, templates),
          ),
        const SizedBox(height: 8),
        Text(
          'You can leave a day empty and fill it in later from the block '
          'editor.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _slotCard(
    ThemeData theme,
    ({int slotIndex, String label}) slot,
    List<WorkoutTemplateData> templates,
  ) {
    final templateId = _templatesBySlot[slot.slotIndex];
    final template = templateId == null
        ? null
        : templates.where((t) => t.id == templateId).firstOrNull;
    final repeats = _plan.trainingDays
        .where((d) => d.slotIndex == slot.slotIndex)
        .length;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final picked = await TemplatePickerSheet.show(context);
        if (picked == null) return;
        setState(() => _templatesBySlot[slot.slotIndex] = picked.id);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: template != null
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: template != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template?.name ??
                        'Tap to link a template'
                            '${repeats > 1 ? ' · used $repeats× per week' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: template != null
                          ? AppColors.primary
                          : AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (template != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: AppColors.secondary),
                onPressed: () =>
                    setState(() => _templatesBySlot.remove(slot.slotIndex)),
              )
            else
              Icon(Icons.add_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ── Step 4: schedule ───────────────────────────────────────────────────────

  Widget _stepSchedule(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(theme, 'Schedule', 'When does week 1 begin?'),
        _radioCard(
          theme,
          title: DateFormat('EEEE, MMMM d, yyyy').format(_startDate),
          subtitle: 'Start date',
          selected: true,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _startDate,
              firstDate: _today().subtract(const Duration(days: 30)),
              lastDate: _today().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _startDate = picked);
          },
        ),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Planned break (optional)'),
        GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.beach_access, color: AppColors.primary, size: 34),
              const SizedBox(height: 12),
              Text(
                'Sessions in this range are marked skipped instead of quietly '
                'piling up as missed.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 18),
              PremiumButton(
                text: _vacation == null
                    ? 'Select trip dates'
                    : '${DateFormat('MMM d').format(_vacation!.start)} – '
                          '${DateFormat('MMM d').format(_vacation!.end)}',
                isPrimary: false,
                icon: Icons.date_range,
                onTap: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: _startDate,
                    lastDate: _startDate.add(const Duration(days: 365)),
                  );
                  if (range != null) setState(() => _vacation = range);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _summaryCard(theme),
      ],
    );
  }

  Widget _summaryCard(ThemeData theme) {
    final plan = _plan;
    final linked = plan.slotSummary
        .where((s) => _templatesBySlot[s.slotIndex] != null)
        .length;
    final total = plan.slotSummary.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _effectiveName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_split.label} · $_weeks weeks · '
            '${plan.trainingDayCount} sessions per '
            '${_mode == ScheduleMode.weekly ? 'week' : 'cycle'} · '
            '${_model.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                linked == total
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: linked == total ? AppColors.primary : AppColors.tertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  linked == total
                      ? 'All $total days have a template.'
                      : '$linked of $total days have a template — the rest '
                            'start empty.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: linked == total
                        ? AppColors.primary
                        : AppColors.tertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Shared bits ────────────────────────────────────────────────────────────

  Widget _title(ThemeData theme, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.secondary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _radioCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_step > 1)
            TextButton(
              onPressed: _saving ? null : () => setState(() => _step--),
              child: const Text('Back'),
            )
          else
            Text(
              'Step $_step of $_stepCount',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          const Spacer(),
          PremiumButton(
            text: _saving
                ? 'Creating…'
                : _step == _stepCount
                ? 'Create block'
                : 'Continue',
            onTap: _saving
                ? () {}
                : () {
                    if (_step < _stepCount) {
                      setState(() => _step++);
                    } else {
                      _create();
                    }
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    final repo = ref.read(programsRepositoryProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final programId = await repo.createProgramFromSplit(
        name: _effectiveName,
        description: '${_model.label} periodization.',
        weeks: _weeks,
        plan: _plan,
        startDate: _startDate,
        periodizationModel: _model.id,
        templateIdsBySlot: _templatesBySlot,
      );

      if (_vacation != null) {
        await repo.addExternalEvent(
          from: _vacation!.start,
          to: _vacation!.end,
          type: 'vacation',
        );
      }

      // Focus the Blocks tab on the day the block starts.
      ref.read(selectedBlockDateProvider.notifier).state = _startDate;
      if (programId > 0) Haptics.success();
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create the block: $e')),
      );
    }
  }
}
