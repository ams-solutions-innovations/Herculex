import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import 'workouts_providers.dart';

/// Machine configuration entry (§11): free-form setting/value pairs (seat
/// height, angle, lever position, …) saved per exercise×gym and recalled the
/// next time the same machine is logged.
class MachineConfigSheet extends ConsumerStatefulWidget {
  final WorkoutExerciseData workoutExercise;
  final int? gymId;
  const MachineConfigSheet(
      {super.key, required this.workoutExercise, this.gymId});

  static Future<void> show(
    BuildContext context, {
    required WorkoutExerciseData workoutExercise,
    int? gymId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          MachineConfigSheet(workoutExercise: workoutExercise, gymId: gymId),
    );
  }

  @override
  ConsumerState<MachineConfigSheet> createState() => _MachineConfigSheetState();
}

class _MachineConfigSheetState extends ConsumerState<MachineConfigSheet> {
  final List<(TextEditingController, TextEditingController)> _rows = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final repo = ref.read(workoutsRepositoryProvider);
    // Current log first; otherwise last saved config for this exercise×gym.
    var json = widget.workoutExercise.machineConfigJson;
    if (json == null) {
      final recalled = await repo.recallMachineConfig(
        exerciseId: widget.workoutExercise.exerciseId,
        gymId: widget.gymId,
      );
      json = recalled?.settingsJson;
    }
    if (json != null) {
      final map = (jsonDecode(json) as Map<String, dynamic>);
      for (final e in map.entries) {
        _rows.add((
          TextEditingController(text: e.key),
          TextEditingController(text: '${e.value}'),
        ));
      }
    }
    if (_rows.isEmpty) _addRow();
    if (mounted) setState(() => _loaded = true);
  }

  void _addRow() {
    _rows.add((TextEditingController(), TextEditingController()));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final (k, v) in _rows) {
      k.dispose();
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final map = <String, String>{
      for (final (k, v) in _rows)
        if (k.text.trim().isNotEmpty) k.text.trim(): v.text.trim(),
    };
    if (map.isNotEmpty) {
      await ref.read(workoutsRepositoryProvider).setMachineConfig(
            workoutExerciseId: widget.workoutExercise.id,
            settingsJson: jsonEncode(map),
            gymId: widget.gymId,
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Keep the save button above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Text('Machine settings',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'e.g. Seat → 6, Angle → 45°. Saved per gym and recalled next time.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondary),
                ),
                const SizedBox(height: 12),
                if (!_loaded)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  for (final (k, v) in _rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: _field(k, 'Setting')),
                          const SizedBox(width: 8),
                          Expanded(child: _field(v, 'Value')),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add setting'),
                  ),
                  const SizedBox(height: 8),
                  // Primary action anchored at the bottom (§22 UI rule).
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
