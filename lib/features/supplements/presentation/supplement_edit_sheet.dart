import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../../nutrition/domain/nutrient_definitions.dart';
import '../../nutrition/presentation/barcode_scanner_view.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../domain/supplement.dart';
import '../presentation/supplement_providers.dart';
import 'supplement_nutrients_sheet.dart';

/// Bottom sheet to add or edit a single supplement.
class SupplementEditSheet extends ConsumerStatefulWidget {
  final Supplement? existing;

  const SupplementEditSheet({super.key, this.existing});

  static Future<void> show(BuildContext context, {Supplement? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => SupplementEditSheet(existing: existing),
    );
  }

  @override
  ConsumerState<SupplementEditSheet> createState() =>
      _SupplementEditSheetState();
}

class _SupplementEditSheetState extends ConsumerState<SupplementEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _doseCtrl;
  late String _doseUnit;
  late SupplementSchedule _schedule;
  TimeOfDay? _time;

  String? _barcode;
  bool _scanning = false;
  String? _scanMessage;

  /// Nutrient ID → amount per dose, edited via the nutrient picker.
  late Map<String, double> _nutrients;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _brandCtrl = TextEditingController(text: s?.brand ?? '');
    _doseCtrl = TextEditingController(
      text: s?.doseAmount == null
          ? ''
          : s!.doseAmount!.truncateToDouble() == s.doseAmount
              ? s.doseAmount!.toStringAsFixed(0)
              : s.doseAmount!.toStringAsFixed(1),
    );
    _doseUnit = supplementDoseUnits.contains(s?.doseUnit)
        ? s!.doseUnit!
        : supplementDoseUnits.first;
    _barcode = s?.barcode;
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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _doseCtrl.dispose();
    super.dispose();
  }

  /// Scans a barcode and pre-fills name/brand from OpenFoodFacts. A lookup
  /// miss still keeps the code — many supplement tubs aren't in the food
  /// database, and the barcode alone is useful for re-scanning later.
  Future<void> _scanBarcode() async {
    final code = await BarcodeScannerView.show(context);
    if (code == null || !mounted) return;

    setState(() {
      _barcode = code;
      _scanning = true;
      _scanMessage = null;
    });

    try {
      final product =
          await ref.read(openFoodFactsClientProvider).lookupBarcode(code);
      if (!mounted) return;
      setState(() {
        if (product == null) {
          _scanMessage = 'Barcode saved — no product match, fill in the rest.';
        } else {
          if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = product.name;
          if (product.brand != null && _brandCtrl.text.trim().isEmpty) {
            _brandCtrl.text = product.brand!;
          }
          _scanMessage = 'Matched "${product.name}".';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanMessage = 'Lookup failed — barcode saved anyway.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// `Creatine 5 g · Vitamin D 25 µg` — trimmed to two entries so the row
  /// stays one line on a phone.
  String _nutrientSummary() {
    final byId = {for (final d in trackedNutrients) d.id: d};
    final parts = <String>[];
    for (final e in _nutrients.entries) {
      final def = byId[e.key];
      if (def == null) continue;
      final v = e.value;
      final fmt = v.truncateToDouble() == v
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1);
      parts.add('${def.label} $fmt ${def.unit}');
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

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Haptics.light();
    final repo = ref.read(supplementRepositoryProvider);
    final brand = _brandCtrl.text.trim();
    final dose = double.tryParse(_doseCtrl.text.trim());
    final supplement = Supplement(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name,
      brand: brand.isEmpty ? null : brand,
      barcode: _barcode,
      doseAmount: dose != null && dose > 0 ? dose : null,
      doseUnit: dose != null && dose > 0 ? _doseUnit : null,
      nutrients: _nutrients,
      schedule: _schedule,
      timeHHMM: _schedule == SupplementSchedule.time ? _timeHHMM : null,
    );
    if (_isEditing) {
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
        // Use a guaranteed-opaque surface colour so the sheet is never
        // see-through regardless of theme configuration.
        color: theme.bottomSheetTheme.backgroundColor ??
               theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barcode scan
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _scanning ? null : _scanBarcode,
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.qr_code_scanner, size: 18),
                        label: Text(_barcode == null
                            ? 'Scan barcode'
                            : 'Barcode $_barcode — rescan'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.4)),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                    if (_scanMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(_scanMessage!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondary)),
                    ],
                    const SizedBox(height: 16),

                    // Name field
                    TextField(
                      controller: _nameCtrl,
                      autofocus: false,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. Creatine, Vitamin D…',
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Brand
                    TextField(
                      controller: _brandCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Brand (optional)',
                        hintText: 'e.g. Optimum Nutrition',
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
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
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Dose',
                              hintText: 'e.g. 5',
                              filled: true,
                              fillColor: AppColors.surfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: AppColors.outlineVariant),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: AppColors.outlineVariant),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _doseUnit,
                            decoration: InputDecoration(
                              labelText: 'Unit',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: AppColors.outlineVariant),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: AppColors.outlineVariant),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
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
                    const SizedBox(height: 12),

                    // Per-dose nutrient contributions
                    InkWell(
                      onTap: _editNutrients,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.science_outlined,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Nutrients per dose',
                                      style: theme.textTheme.bodyMedium),
                                  Text(
                                    _nutrients.isEmpty
                                        ? 'Not counted towards daily totals'
                                        : _nutrientSummary(),
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: AppColors.secondary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.secondary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Schedule selector
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
                          onTap: () => _pickTime(),
                        ),
                        const SizedBox(width: 8),
                        _ScheduleChip(
                          label: 'Post-workout',
                          icon: Icons.fitness_center,
                          selected: _schedule == SupplementSchedule.postWorkout,
                          onTap: () => setState(
                              () => _schedule = SupplementSchedule.postWorkout),
                        ),
                      ],
                    ),

                    // Time display / tap to change
                    if (_schedule == SupplementSchedule.time) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _time != null
                                    ? _time!.format(context)
                                    : 'Tap to set time',
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
                          Icon(Icons.info_outline,
                              size: 14, color: AppColors.secondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'You\'ll be notified when your workout ends.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.secondary),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action buttons
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
                                  horizontal: 20, vertical: 14),
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
                              style: const TextStyle(fontWeight: FontWeight.bold),
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
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
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
