import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../../../features/profile/domain/profile.dart';
import '../../../services/ongoing_workout_surface_bridge.dart';
import '../../../theme/colors.dart';
import '../data/ongoing_workout_surface_capabilities_provider.dart';
import '../data/workout_quick_action_settings.dart';
import '../domain/workout_notification_command.dart';
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
    NotifierProvider<DefaultRestTimerNotifier, int>(
      DefaultRestTimerNotifier.new,
    );

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

final keepAwakeProvider = NotifierProvider<KeepAwakeNotifier, bool>(
  KeepAwakeNotifier.new,
);

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
    final weightFormat = ref.watch(weightFormatProvider);
    final restSeconds = ref.watch(defaultRestTimerProvider);
    final quickLoadStepKg = ref.watch(quickLoadStepProvider);
    final surfaceCapabilities = ref.watch(
      ongoingWorkoutSurfaceCapabilitiesProvider,
    );
    final surfaceDiagnostics = ref.watch(
      ongoingWorkoutSurfaceDiagnosticsProvider,
    );
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
            subtitle: Text('Applied when no per-exercise override is set'),
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
            secondary: Icon(
              Icons.straighten_outlined,
              color: AppColors.primary,
            ),
            title: const Text('Use Metric Units'),
            subtitle: Text(
              isMetric ? 'Weights shown in kg' : 'Weights shown in lb',
            ),
            value: isMetric,
            activeThumbColor: AppColors.primary,
            onChanged: (_) => ref.read(unitsProvider.notifier).toggle(),
          ),
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: AppColors.primary),
            title: const Text('Quick Load Step'),
            subtitle: const Text(
              'Used by notification and Now Bar load actions',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weightFormat.format(quickLoadStepKg),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: AppColors.secondary),
              ],
            ),
            onTap: () =>
                _pickQuickLoadStep(context, ref, quickLoadStepKg, weightFormat),
          ),
          Divider(height: 1, color: AppColors.outlineVariant),

          // ── Keep Awake ────────────────────────────────────────────────
          _SectionHeader(label: 'DISPLAY'),
          ListTile(
            leading: Icon(
              Icons.notifications_active_outlined,
              color: AppColors.primary,
            ),
            title: const Text('Now Bar / Live Updates'),
            subtitle: Text(
              _surfaceCapabilityLabel(surfaceCapabilities, surfaceDiagnostics),
            ),
            trailing: _surfaceCapabilityAction(ref, surfaceCapabilities),
            onTap: () => _showSurfaceDiagnostics(
              context,
              ref,
              surfaceCapabilities,
              surfaceDiagnostics,
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.light_mode_outlined,
              color: AppColors.primary,
            ),
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
            leading: Icon(
              Icons.fitness_center_outlined,
              color: AppColors.primary,
            ),
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
          _ComingSoonTile(
            icon: Icons.volume_up_outlined,
            label: 'Sounds & Alerts',
          ),
          _ComingSoonTile(
            icon: Icons.calculate_outlined,
            label: 'Warm-up Calculator',
          ),
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

  static String _surfaceCapabilityLabel(
    AsyncValue<OngoingWorkoutSurfaceCapabilities> surfaceCapabilities,
    AsyncValue<OngoingWorkoutSurfaceDiagnostics> surfaceDiagnostics,
  ) {
    final diagnostics = surfaceDiagnostics.asData?.value;
    return surfaceCapabilities.when(
      data: (capabilities) {
        if ((diagnostics?.pendingNativeActionCount ?? 0) > 0) {
          return 'Workout action queued';
        }
        if (!capabilities.notificationsEnabled) {
          return 'Workout notifications disabled';
        }
        if (diagnostics?.systemMarkedPromotedOngoing == true) {
          return 'Workout surface is live';
        }
        if (diagnostics?.posted == true &&
            diagnostics?.hasPromotableCharacteristics == true) {
          return 'Workout surface is promotable';
        }
        if (diagnostics?.posted == true &&
            diagnostics?.requestedPromotedOngoing == true) {
          return 'Workout surface requested promotion';
        }
        if (capabilities.canPostPromotedNotifications) {
          return 'Promoted workout surface available';
        }
        if (capabilities.android16Plus) {
          return 'Promoted workout surface not enabled';
        }
        return 'Fallback notification on this Android version';
      },
      error: (_, _) => 'Fallback notification active',
      loading: () => 'Checking availability',
    );
  }

  static Widget _surfaceCapabilityAction(
    WidgetRef ref,
    AsyncValue<OngoingWorkoutSurfaceCapabilities> surfaceCapabilities,
  ) {
    return surfaceCapabilities.maybeWhen(
      data: (capabilities) {
        if (capabilities.android16Plus &&
            !capabilities.canPostPromotedNotifications) {
          return IconButton(
            tooltip: 'Open settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await OngoingWorkoutSurfaceBridge.instance
                  .openPromotedNotificationSettings();
              ref.invalidate(ongoingWorkoutSurfaceCapabilitiesProvider);
              ref.invalidate(ongoingWorkoutSurfaceDiagnosticsProvider);
            },
          );
        }
        return _surfaceCapabilityRefreshAction(ref);
      },
      orElse: () => _surfaceCapabilityRefreshAction(ref),
    );
  }

  static Widget _surfaceCapabilityRefreshAction(WidgetRef ref) {
    return IconButton(
      tooltip: 'Refresh',
      icon: const Icon(Icons.refresh),
      onPressed: () {
        ref.invalidate(ongoingWorkoutSurfaceCapabilitiesProvider);
        ref.invalidate(ongoingWorkoutSurfaceDiagnosticsProvider);
      },
    );
  }

  static void _showSurfaceDiagnostics(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<OngoingWorkoutSurfaceCapabilities> surfaceCapabilities,
    AsyncValue<OngoingWorkoutSurfaceDiagnostics> surfaceDiagnostics,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).padding.bottom + 8;
        final diagnostics = surfaceDiagnostics.asData?.value;
        final capabilities = surfaceCapabilities.asData?.value;
        final rows = _surfaceDiagnosticRows(capabilities, diagnostics);
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
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Now Bar Diagnostics',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        ref.invalidate(
                          ongoingWorkoutSurfaceCapabilitiesProvider,
                        );
                        ref.invalidate(
                          ongoingWorkoutSurfaceDiagnosticsProvider,
                        );
                        Navigator.pop(ctx);
                      },
                    ),
                    if (kDebugMode && diagnostics?.sessionId != null)
                      PopupMenuButton<String>(
                        tooltip: 'Send diagnostic action',
                        icon: const Icon(Icons.bug_report_outlined),
                        onSelected: (actionId) async {
                          await _sendSurfaceDiagnosticAction(
                            ctx,
                            ref,
                            diagnostics!,
                            actionId,
                          );
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: WorkoutNotificationActionIds.repsUp,
                            child: Text('+ Rep'),
                          ),
                          PopupMenuItem(
                            value: WorkoutNotificationActionIds.weightUp,
                            child: Text('+ Load'),
                          ),
                          PopupMenuItem(
                            value: WorkoutNotificationActionIds.completeSet,
                            child: Text('Done'),
                          ),
                          PopupMenuItem(
                            value: WorkoutNotificationActionIds.repsDown,
                            child: Text('- Rep'),
                          ),
                          PopupMenuItem(
                            value: WorkoutNotificationActionIds.weightDown,
                            child: Text('- Load'),
                          ),
                        ],
                      ),
                    if (capabilities?.android16Plus == true)
                      IconButton(
                        tooltip: 'Open settings',
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () async {
                          await OngoingWorkoutSurfaceBridge.instance
                              .openPromotedNotificationSettings();
                          ref.invalidate(
                            ongoingWorkoutSurfaceCapabilitiesProvider,
                          );
                          ref.invalidate(
                            ongoingWorkoutSurfaceDiagnosticsProvider,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.outlineVariant),
              for (final row in rows)
                ListTile(
                  dense: true,
                  title: Text(row.label),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      row.value,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: row.highlight
                            ? AppColors.primary
                            : AppColors.secondary,
                        fontWeight: row.highlight
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static List<_DiagnosticsRow> _surfaceDiagnosticRows(
    OngoingWorkoutSurfaceCapabilities? capabilities,
    OngoingWorkoutSurfaceDiagnostics? diagnostics,
  ) {
    return [
      _DiagnosticsRow(
        'Summary',
        _surfaceCapabilityLabel(
          AsyncValue.data(
            capabilities ??
                const OngoingWorkoutSurfaceCapabilities.unavailable(),
          ),
          AsyncValue.data(
            diagnostics ?? const OngoingWorkoutSurfaceDiagnostics.unavailable(),
          ),
        ),
        highlight: true,
      ),
      _DiagnosticsRow(
        'Android',
        capabilities?.androidSdkInt == null
            ? 'Unavailable'
            : 'SDK ${capabilities!.androidSdkInt}',
      ),
      _DiagnosticsRow(
        'Promoted Allowed',
        _yesNo(capabilities?.canPostPromotedNotifications ?? false),
        highlight: capabilities?.canPostPromotedNotifications == true,
      ),
      _DiagnosticsRow(
        'Notifications',
        _yesNo(capabilities?.notificationsEnabled ?? false),
        highlight: capabilities?.notificationsEnabled == true,
      ),
      _DiagnosticsRow(
        'Notification Posted',
        _yesNo(diagnostics?.posted ?? false),
        highlight: diagnostics?.posted == true,
      ),
      _DiagnosticsRow(
        'Requested Promoted',
        _yesNo(diagnostics?.requestedPromotedOngoing ?? false),
        highlight: diagnostics?.requestedPromotedOngoing == true,
      ),
      _DiagnosticsRow(
        'Promotable',
        _yesNo(diagnostics?.hasPromotableCharacteristics ?? false),
        highlight: diagnostics?.hasPromotableCharacteristics == true,
      ),
      _DiagnosticsRow(
        'System Promoted',
        _yesNo(diagnostics?.systemMarkedPromotedOngoing ?? false),
        highlight: diagnostics?.systemMarkedPromotedOngoing == true,
      ),
      _DiagnosticsRow(
        'Actions',
        '${diagnostics?.actionCount ?? 0} shown',
        highlight: (diagnostics?.actionCount ?? 0) > 0,
      ),
      _DiagnosticsRow(
        'Controls',
        '${diagnostics?.controlCount ?? 0} steppers',
        highlight: (diagnostics?.controlCount ?? 0) > 0,
      ),
      _DiagnosticsRow(
        'Action Contract',
        _yesNo(diagnostics?.actionContractAligned ?? false),
        highlight: diagnostics?.actionContractAligned == true,
      ),
      _DiagnosticsRow(
        'Diagnostic Actions',
        _yesNo(diagnostics?.diagnosticActionsAvailable ?? false),
        highlight: diagnostics?.diagnosticActionsAvailable == true,
      ),
      _DiagnosticsRow(
        'Channel',
        diagnostics?.channelImportanceName?.trim().isNotEmpty == true
            ? diagnostics!.channelImportanceName!
            : 'Unavailable',
        highlight:
            diagnostics?.channelImportanceName == 'low' ||
            diagnostics?.channelImportanceName == 'default' ||
            diagnostics?.channelImportanceName == 'high',
      ),
      _DiagnosticsRow(
        'Ongoing Flag',
        _yesNo(diagnostics?.ongoingEventFlag ?? false),
        highlight: diagnostics?.ongoingEventFlag == true,
      ),
      _DiagnosticsRow(
        'Chronometer',
        _yesNo(diagnostics?.usesChronometer ?? false),
        highlight: diagnostics?.usesChronometer == true,
      ),
      _DiagnosticsRow(
        'Pending Native',
        '${diagnostics?.pendingNativeActionCount ?? 0}',
        highlight: (diagnostics?.pendingNativeActionCount ?? 0) > 0,
      ),
      _DiagnosticsRow(
        'Dropped Native',
        '${diagnostics?.droppedNativeActionCount ?? 0}',
        highlight: (diagnostics?.droppedNativeActionCount ?? 0) > 0,
      ),
      _DiagnosticsRow(
        'Rejected Native',
        '${diagnostics?.rejectedNativeActionCount ?? 0}',
        highlight: (diagnostics?.rejectedNativeActionCount ?? 0) > 0,
      ),
      _DiagnosticsRow(
        'Rejected Action',
        diagnostics?.lastRejectedNativeActionId?.trim().isNotEmpty == true
            ? diagnostics!.lastRejectedNativeActionId!
            : 'None',
        highlight: diagnostics?.lastRejectedNativeActionId != null,
      ),
      _DiagnosticsRow(
        'Rejected Reason',
        diagnostics?.lastRejectedNativeActionReason?.trim().isNotEmpty == true
            ? diagnostics!.lastRejectedNativeActionReason!
            : 'None',
        highlight: diagnostics?.lastRejectedNativeActionReason != null,
      ),
      _DiagnosticsRow(
        'Target',
        diagnostics?.collapsedValue?.trim().isNotEmpty == true
            ? diagnostics!.collapsedValue!
            : 'None',
      ),
      _DiagnosticsRow(
        'Target Set',
        diagnostics?.targetSetId == null
            ? 'None'
            : '#${diagnostics!.targetSetId}',
      ),
      _DiagnosticsRow(
        'Last Action',
        diagnostics?.lastNativeActionId?.trim().isNotEmpty == true
            ? diagnostics!.lastNativeActionId!
            : 'None',
        highlight: diagnostics?.lastNativeActionId != null,
      ),
      _DiagnosticsRow(
        'Last Feedback',
        diagnostics?.lastNativeFeedbackPosted == null
            ? 'None'
            : _yesNo(diagnostics!.lastNativeFeedbackPosted!),
        highlight: diagnostics?.lastNativeFeedbackPosted == true,
      ),
    ];
  }

  static String _yesNo(bool value) => value ? 'Yes' : 'No';

  static Future<void> _sendSurfaceDiagnosticAction(
    BuildContext context,
    WidgetRef ref,
    OngoingWorkoutSurfaceDiagnostics diagnostics,
    String actionId,
  ) async {
    await OngoingWorkoutSurfaceBridge.instance.sendDiagnosticAction(
      actionId: actionId,
      sessionId: diagnostics.sessionId,
      setId: diagnostics.targetSetId,
    );
    ref.invalidate(ongoingWorkoutSurfaceDiagnosticsProvider);
    if (context.mounted) Navigator.pop(context);
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
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                        )
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

  void _pickQuickLoadStep(
    BuildContext context,
    WidgetRef ref,
    double currentKg,
    WeightFormat weightFormat,
  ) {
    final optionsKg = weightFormat.isMetric
        ? const [1.25, 2.5, 5.0, 10.0]
        : [Units.lbToKg(2.5), Units.lbToKg(5), Units.lbToKg(10)];
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
                  'Quick Load Step',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...optionsKg.map((stepKg) {
                final selected = (stepKg - currentKg).abs() < 0.001;
                return ListTile(
                  title: Text(weightFormat.format(stepKg)),
                  trailing: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                  tileColor: selected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : null,
                  onTap: () async {
                    await ref.read(quickLoadStepProvider.notifier).set(stepKg);
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

class _DiagnosticsRow {
  final String label;
  final String value;
  final bool highlight;

  const _DiagnosticsRow(this.label, this.value, {this.highlight = false});
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ComingSoonTile({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.secondary.withValues(alpha: 0.45)),
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
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.secondary),
        ),
      ),
    );
  }
}
