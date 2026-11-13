import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/nutrition/domain/nutrient_definitions.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_presets.dart';
import 'package:herculex/features/supplements/presentation/supplement_nutrients_sheet.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _accent = Color(0xFF9B59B6);

/// Bottom sheet to configure a single supplement: dose, optional creatine
/// loading phase, reminder. New supplements arrive pre-filled from a
/// [SupplementPreset] (or blank for a custom one) as `isNewDraft`.
class SupplementEditSheet extends ConsumerStatefulWidget {
  final Supplement? existing;
  final bool isNewDraft;

  const SupplementEditSheet({
    super.key,
    this.existing,
    this.isNewDraft = false,
  });

  static Future<void> show(
    BuildContext context, {
    Supplement? existing,
    bool isNewDraft = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) =>
          SupplementEditSheet(existing: existing, isNewDraft: isNewDraft),
    );
  }

  @override
  ConsumerState<SupplementEditSheet> createState() =>
      _SupplementEditSheetState();
}

class _SupplementEditSheetState extends ConsumerState<SupplementEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _doseCtrl;
  late final TextEditingController _loadingDoseCtrl;
  late String _doseUnit;
  late SupplementSchedule _schedule;
  TimeOfDay? _time;

  // Creatine loading phase.
  late bool _loading;
  late int _loadingDays;
  late DateTime _loadingStart;

  /// Nutrient ID → amount per dose, edited via the nutrient picker.
  late Map<String, double> _nutrients;

  SupplementPreset? get _preset =>
      SupplementPreset.byKey(widget.existing?.presetKey);

  bool get _supportsLoading => _preset?.supportsLoading ?? false;

  bool get _isEditing =>
      widget.existing != null &&
      !widget.isNewDraft &&
      widget.existing!.id.isNotEmpty;

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    final preset = _preset;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _doseCtrl = TextEditingController(
      text: s?.doseAmount == null ? '' : _fmt(s!.doseAmount!),
    );
    _doseUnit = supplementDoseUnits.contains(s?.doseUnit)
        ? s!.doseUnit!
        : supplementDoseUnits.first;
    _nutrients = {...?s?.nutrients};
    _schedule = s?.schedule ?? SupplementSchedule.none;
    if (s?.timeHHMM != null) {
      final parts = s!.timeHHMM!.split(':');
      if (parts.length == 2) {
        _time = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    final today = DateUtils.dateOnly(DateTime.now());
    _loading = s?.hasLoadingPhase ?? false;
    _loadingDays = s?.loadingDays ?? preset?.loadingDays ?? 7;
    _loadingStart = s?.loadingStart ?? today;
    _loadingDoseCtrl = TextEditingController(
      text: _fmt(s?.loadingDoseAmount ?? preset?.loadingDoseAmount ?? 20),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    _loadingDoseCtrl.dispose();
    super.dispose();
  }

  /// `Zinc 30 mg · Magnesium 450 mg` — trimmed to two entries so the row stays
  /// one line on a phone.
  String _nutrientSummary() {
    final byId = {for (final d in trackedNutrients) d.id: d};
    final parts = <String>[];
    for (final e in _nutrients.entries) {
      final def = byId[e.key];
      if (def == null) continue;
      parts.add('${def.label} ${_fmt(e.value)} ${def.unit}');
    }
    if (parts.length <= 2) return parts.join(' · ');
    return '${parts.take(2).join(' · ')} +${parts.length - 2} more';
  }

  Future<void> _editNutrients() async {
    final result = await SupplementNutrientsSheet.show(context, _nutrients);
    if (result != null && mounted) setState(() => _nutrients = result);
  }

  String? get _timeHHMM {
    if (_time == null) return null;
    final h = _time!.hour.toString().padLeft(2, '0');
    final m = _time!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime() async {
    FocusScope.of(context).unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) {
      setState(() {
        _time = picked;
        _schedule = SupplementSchedule.time;
      });
    }
  }

  Future<void> _pickLoadingStart() async {
    FocusScope.of(context).unfocus();
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _loadingStart,
      firstDate: today.subtract(const Duration(days: 90)),
      lastDate: today.add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _loadingStart = DateUtils.dateOnly(picked));
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Haptics.light();
    final repo = ref.read(supplementRepositoryProvider);
    final dose = double.tryParse(_doseCtrl.text.trim());
    final hasDose = dose != null && dose > 0;
    final loadingDose = double.tryParse(_loadingDoseCtrl.text.trim());
    final saveLoading =
        _supportsLoading && _loading && loadingDose != null && loadingDose > 0;
    final existingId = widget.existing?.id;
    final supplement = Supplement(
      id: (existingId != null && existingId.isNotEmpty)
          ? existingId
          : const Uuid().v4(),
      name: name,
      brand: widget.existing?.brand,
      presetKey: widget.existing?.presetKey,
      doseAmount: hasDose ? dose : null,
      doseUnit: hasDose ? _doseUnit : null,
      loadingDoseAmount: saveLoading ? loadingDose : null,
      loadingDays: saveLoading ? _loadingDays : null,
      loadingStartIso: saveLoading ? Supplement.isoDay(_loadingStart) : null,
      nutrients: _nutrients,
      schedule: _schedule,
      timeHHMM: _schedule == SupplementSchedule.time ? _timeHHMM : null,
    );
    final existsInRepo = repo.loadSupplements().any(
      (s) => s.id == supplement.id,
    );
    if (_isEditing && existsInRepo) {
      await repo.updateSupplement(supplement);
    } else {
      await repo.addSupplement(supplement);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!_isEditing) return;
    Haptics.heavy();
    await ref
        .read(supplementRepositoryProvider)
        .deleteSupplement(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  InputDecoration _decoration(String label, {String? hint}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceVariant,
      border: border(AppColors.outlineVariant),
      enabledBorder: border(AppColors.outlineVariant),
      focusedBorder: border(AppColors.primary, 1.5),
    );
  }

  List<TextInputFormatter> get _numberOnly => [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);

    return Container(
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: mq.viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        // Guaranteed-opaque surface so the sheet is never see-through.
        color:
            theme.bottomSheetTheme.backgroundColor ??
            theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              _isEditing ? 'Edit Supplement' : 'Add Supplement',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration(
                        'Name',
                        hint: 'e.g. Creatine, Vitamin D…',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Dose amount + unit
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _doseCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: _numberOnly,
                            decoration: _decoration(
                              _supportsLoading ? 'Daily dose' : 'Dose',
                              hint: 'e.g. 5',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _doseUnit,
                            decoration: _decoration('Unit').copyWith(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            items: [
                              for (final u in supplementDoseUnits)
                                DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    u,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _doseUnit = v ?? _doseUnit),
                          ),
                        ),
                      ],
                    ),

                    if (_supportsLoading) ...[
                      const SizedBox(height: 16),
                      _buildLoadingSection(theme),
                    ],
                    const SizedBox(height: 12),

                    // Per-dose nutrient contributions
                    InkWell(
                      onTap: _editNutrients,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.science_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nutrients per dose',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    _nutrients.isEmpty
                                        ? 'Not counted towards daily totals'
                                        : _nutrientSummary(),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.secondary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: AppColors.secondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildReminderSection(theme),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        if (_isEditing) ...[
                          OutlinedButton.icon(
                            onPressed: _delete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: const StadiumBorder(),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              _isEditing ? 'Save changes' : 'Add supplement',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Creatine loading phase ────────────────────────────────────────────────

  Widget _buildLoadingSection(ThemeData theme) {
    final end = DateTime(
      _loadingStart.year,
      _loadingStart.month,
      _loadingStart.day + _loadingDays - 1,
    );
    final dateFmt = DateFormat('d MMM');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: _loading ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _accent.withValues(alpha: _loading ? 0.45 : 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _loading,
            activeThumbColor: _accent,
            title: const Text('Loading phase'),
            subtitle: Text(
              'Higher dose for the first days, then the daily dose above.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            onChanged: (v) {
              Haptics.selection();
              setState(() => _loading = v);
            },
          ),
          if (_loading) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _loadingDoseCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _numberOnly,
                    onChanged: (_) => setState(() {}),
                    decoration: _decoration(
                      'Loading dose',
                    ).copyWith(suffixText: _doseUnit),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _pickLoadingStart,
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: _decoration('Starts').copyWith(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                      ),
                      child: Text(dateFmt.format(_loadingStart)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final days in const [5, 7, 10, 14])
                  ChoiceChip(
                    label: Text('$days days'),
                    selected: _loadingDays == days,
                    selectedColor: _accent.withValues(alpha: 0.25),
                    onSelected: (_) {
                      Haptics.selection();
                      setState(() => _loadingDays = days);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${_loadingDoseCtrl.text.isEmpty ? '–' : _loadingDoseCtrl.text} '
              '$_doseUnit/day until ${dateFmt.format(end)}, then '
              '${_doseCtrl.text.isEmpty ? '–' : _doseCtrl.text} $_doseUnit/day.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Reminder ──────────────────────────────────────────────────────────────

  Widget _buildReminderSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REMINDER',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            letterSpacing: 1.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _ScheduleChip(
              label: 'None',
              icon: Icons.notifications_off_outlined,
              selected: _schedule == SupplementSchedule.none,
              onTap: () => setState(() => _schedule = SupplementSchedule.none),
            ),
            const SizedBox(width: 8),
            _ScheduleChip(
              label: 'Set time',
              icon: Icons.access_time_outlined,
              selected: _schedule == SupplementSchedule.time,
              onTap: _pickTime,
            ),
            const SizedBox(width: 8),
            _ScheduleChip(
              label: 'Post-workout',
              icon: Icons.fitness_center,
              selected: _schedule == SupplementSchedule.postWorkout,
              onTap: () =>
                  setState(() => _schedule = SupplementSchedule.postWorkout),
            ),
          ],
        ),
        if (_schedule == SupplementSchedule.time) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _time != null ? _time!.format(context) : 'Tap to set time',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_schedule == SupplementSchedule.postWorkout) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: AppColors.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "You'll be notified when your workout ends.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ScheduleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ScheduleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.outlineVariant.withValues(alpha: 0.4),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.primary : AppColors.secondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? AppColors.primary : AppColors.secondary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
