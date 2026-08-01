import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../../../features/profile/domain/profile.dart';
import '../../../theme/colors.dart';
import 'plate_calculator_sheet.dart';

// ── Default Rest Timer preference ──────────────────────────────────────────

/// Global default rest timer duration (seconds) stored in SharedPreferences.
/// Used as the app-wide fallback when no per-exercise override is set.
class DefaultRestTimerNotifier extends Notifier<int> {
  static const prefsKey = 'default_rest_seconds';
  static const _default = 120;

  @override
  int build() =>
      ref.watch(sharedPreferencesProvider).getInt(prefsKey) ?? _default;

  Future<void> set(int seconds) async {
    await ref.read(sharedPreferencesProvider).setInt(prefsKey, seconds);
    state = seconds;
  }
}

final defaultRestTimerProvider =
    NotifierProvider<DefaultRestTimerNotifier, int>(DefaultRestTimerNotifier.new);

// ── Keep Awake preference ───────────────────────────────────────────────────

/// Whether the screen should stay on during an active workout.
/// Persisted in SharedPreferences; applied/released by [ActiveWorkoutView].
class KeepAwakeNotifier extends Notifier<bool> {
  static const prefsKey = 'keep_awake_workout';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(prefsKey) ?? true;

  Future<void> set(bool enabled) async {
    await ref.read(sharedPreferencesProvider).setBool(prefsKey, enabled);
    state = enabled;
    await WakelockPlus.toggle(enable: enabled);
  }
}

final keepAwakeProvider =
    NotifierProvider<KeepAwakeNotifier, bool>(KeepAwakeNotifier.new);

// ── Sheet ───────────────────────────────────────────────────────────────────

/// Bottom sheet shown when the user taps the ⚙ icon during a workout.
class WorkoutSettingsSheet extends ConsumerWidget {
  const WorkoutSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WorkoutSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMetric = ref.watch(unitsProvider) == MeasurementUnit.metric;
    final restSeconds = ref.watch(defaultRestTimerProvider);
    final bottomPad = MediaQuery.of(context).padding.bottom + 12;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.outlineVariant),
          left: BorderSide(color: AppColors.outlineVariant),
          right: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Workout Settings',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.outlineVariant),

          // ── Rest Timer ────────────────────────────────────────────────
          _SectionHeader(label: 'REST TIMER'),
          ListTile(
            leading: Icon(Icons.timer_outlined, color: AppColors.primary),
            title: const Text('Default Rest Duration'),
            subtitle:
                Text('Applied when no per-exercise override is set'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmtDuration(restSeconds),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: AppColors.secondary),
              ],
            ),
            onTap: () => _pickRestTimer(context, ref, restSeconds),
          ),
          Divider(height: 1, color: AppColors.outlineVariant),

          // ── Units ─────────────────────────────────────────────────────
          _SectionHeader(label: 'UNITS'),
          SwitchListTile(
            secondary: Icon(Icons.straighten_outlined, color: AppColors.primary),
            title: const Text('Use Metric Units'),
            subtitle: Text(isMetric ? 'Weights shown in kg' : 'Weights shown in lb'),
            value: isMetric,
            activeThumbColor: AppColors.primary,
            onChanged: (_) => ref.read(unitsProvider.notifier).toggle(),
          ),
          Divider(height: 1, color: AppColors.outlineVariant),

          // ── Keep Awake ────────────────────────────────────────────────
          _SectionHeader(label: 'DISPLAY'),
          SwitchListTile(
            secondary: Icon(Icons.light_mode_outlined, color: AppColors.primary),
            title: const Text('Keep Screen Awake'),
            subtitle: const Text('Prevent screen from sleeping during workout'),
            value: ref.watch(keepAwakeProvider),
            activeThumbColor: AppColors.primary,
            onChanged: (v) => ref.read(keepAwakeProvider.notifier).set(v),
          ),
          Divider(height: 1, color: AppColors.outlineVariant),

          // ── Coming Soon ───────────────────────────────────────────────
          _SectionHeader(label: 'TOOLS'),
          // Plate Calculator — real feature
          ListTile(
            leading: Icon(Icons.fitness_center_outlined, color: AppColors.primary),
            title: const Text('Plate Calculator'),
            subtitle: const Text('See which plates to load on each side'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).pop();
              PlateCalculatorSheet.show(context);
            },
          ),
          Divider(height: 1, color: AppColors.outlineVariant),
          _SectionHeader(label: 'COMING SOON'),
          _ComingSoonTile(icon: Icons.volume_up_outlined, label: 'Sounds & Alerts'),
          _ComingSoonTile(
              icon: Icons.calculate_outlined, label: 'Warm-up Calculator'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _fmtDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  void _pickRestTimer(BuildContext context, WidgetRef ref, int current) {
    const options = [30, 45, 60, 90, 120, 150, 180, 240, 300];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).padding.bottom + 8;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          padding: EdgeInsets.only(bottom: bottomPad),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.outlineVariant),
              left: BorderSide(color: AppColors.outlineVariant),
              right: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Default Rest Duration',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ...options.map((s) {
                final selected = s == current;
                return ListTile(
                  title: Text(_fmtDuration(s)),
                  trailing: selected
                      ? Icon(Icons.check_circle_rounded,
                          color: AppColors.primary)
                      : null,
                  tileColor: selected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : null,
                  onTap: () async {
                    await ref.read(defaultRestTimerProvider.notifier).set(s);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
        ),
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ComingSoonTile({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          Icon(icon, color: AppColors.secondary.withValues(alpha: 0.45)),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.secondary.withValues(alpha: 0.55),
            ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Soon',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
              ),
        ),
      ),
    );
  }
}
