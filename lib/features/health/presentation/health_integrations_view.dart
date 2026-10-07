import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/health/application/cycle_providers.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/health/domain/health_read_state.dart';
import 'package:herculex/features/health/presentation/health_platform_detail_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/application/calendar_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';

class HealthIntegrationsView extends ConsumerStatefulWidget {
  const HealthIntegrationsView({super.key});

  @override
  ConsumerState<HealthIntegrationsView> createState() =>
      _HealthIntegrationsViewState();
}

class _HealthIntegrationsViewState
    extends ConsumerState<HealthIntegrationsView> {
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _hydratePermissionStatus(),
    );
  }

  /// Reconciles the "connected" toggles with the real OS grant. The status
  /// map is in-memory only, so on every app start it forgets whatever was
  /// actually authorized in Health Connect / HealthKit previously.
  Future<void> _hydratePermissionStatus() async {
    final granted = await ref.read(healthServiceProvider).checkHasPermissions();
    if (!mounted) return;
    final current = ref.read(healthPermissionStatusProvider);
    final updated = {...current};
    if (Platform.isAndroid) {
      updated['samsung'] = granted;
      updated['google'] = granted;
    } else if (Platform.isIOS) {
      updated['apple'] = granted;
    }
    ref.read(healthPermissionStatusProvider.notifier).state = updated;
    if (granted) {
      _syncAllData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = ref.watch(healthPermissionStatusProvider);
    final autoAdjust = ref.watch(autoAdjustGymVolumeProvider);
    final samplesAsync = ref.watch(todayHealthSamplesProvider);
    final adjustmentAsync = ref.watch(activityBasedAdjustmentProvider);
    final lastSyncTime = ref.watch(lastHealthSyncTimestampProvider);
    final lastDailyRead = ref.watch(lastDailyHealthReadProvider);

    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;
    final isFemale = profile?.sex == BiologicalSex.female;

    return HxScreenShell(
      title: 'Health & Sync',
      children: [
        // ── Activity impact card ───────────────────────────────────────
        adjustmentAsync.when(
          data: (adj) => _buildImpactCard(
            theme,
            adj.message,
            adj.statusLabel,
            adj.volumeFactor < 1.0,
          ),
          loading: () => const Center(child: LinearProgressIndicator()),
          error: (err, stack) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 32),

        // ── Biological sex ────────────────────────────────────────────
        Center(
          child: Text(
            'BIOLOGICAL SEX',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSexSelectorCard(theme, profile),
        const SizedBox(height: 32),

        // ── Integrations header ───────────────────────────────────────
        Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'INTEGRACIJE',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 1.0,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _isSyncing
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        Icons.sync_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      onPressed: _syncAllData,
                      tooltip: 'Sync all',
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Platform cards ─────────────────────────────────────────────
        _buildPlatformCard(
          theme: theme,
          platform: HealthPlatform.apple,
          name: 'Apple Health',
          subtitle: 'HealthKit API · iOS / watchOS',
          icon: Icons.health_and_safety_rounded,
          accentColor: const Color(0xFFFF375F),
          isConnected: permissions['apple'] ?? false,
          permKey: 'apple',
          lastSync: lastSyncTime,
          route: '/health/apple',
        ),
        const SizedBox(height: 12),
        _buildPlatformCard(
          theme: theme,
          platform: HealthPlatform.google,
          name: 'Google Health Connect',
          subtitle: 'Health Connect API · Android',
          icon: Icons.monitor_heart_rounded,
          accentColor: const Color(0xFF4285F4),
          isConnected: permissions['google'] ?? false,
          permKey: 'google',
          lastSync: lastSyncTime,
          route: '/health/google',
        ),
        const SizedBox(height: 12),
        _buildCalendarSyncCard(theme),
        const SizedBox(height: 32),

        // ── Cycle sync (females only) ──────────────────────────────────
        if (isFemale) ...[
          Center(
            child: Text(
              'CYCLE SYNC',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildCycleSyncSection(theme),
          const SizedBox(height: 32),
        ],

        // ── Auto-adjustments ──────────────────────────────────────────
        Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'AUTO-ADJUSTMENTS',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.secondary,
                letterSpacing: 1.0,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Switch(
                value: autoAdjust,
                onChanged: (val) {
                  ref.read(autoAdjustGymVolumeProvider.notifier).state = val;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'When enabled, Herculex adjusts daily set recommendations based on sleep depth, resting heart rate, and cardiovascular stress.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 32),

        // ── Today's biometrics ────────────────────────────────────────
        Center(
          child: Text(
            "TODAY'S BIOMETRICS",
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        samplesAsync.when(
          data: (samples) {
            if (samples.isEmpty && lastDailyRead == null) {
              return _buildEmptyBiometricsCard(theme);
            }
            return _buildBiometricsGrid(theme, samples, lastDailyRead);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        ),
      ],
    );
  }

  // ─── Platform card ────────────────────────────────────────────────────────

  Widget _buildPlatformCard({
    required ThemeData theme,
    required HealthPlatform platform,
    required String name,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isConnected,
    required String permKey,
    required DateTime? lastSync,
    required String route,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: InkWell(
        onTap: () => context.push(route),
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Platform icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 16),
            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isConnected
                              ? Colors.green
                              : AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isConnected
                              ? (lastSync != null
                                    ? 'Sync ${_formatTime(lastSync)}'
                                    : 'Connected')
                              : 'Not connected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '· $subtitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.tertiary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Toggle
            Switch(
              value: isConnected,
              activeThumbColor: accentColor,
              onChanged: (val) => _togglePermission(permKey, val),
            ),
            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Calendar Sync Card ───────────────────────────────────────────────────

  Widget _buildCalendarSyncCard(ThemeData theme) {
    final isSyncEnabled = ref.watch(calendarSyncEnabledProvider);
    final lastSync = ref.watch(lastCalendarSyncTimestampProvider);
    final syncState = ref.watch(calendarSyncControllerProvider);
    final selectedCalId = ref.watch(selectedCalendarIdProvider);
    final availableCals =
        ref.watch(availableCalendarsProvider).valueOrNull ?? [];

    final selectedCalName = selectedCalId == null
        ? 'Herculex Training'
        : (availableCals.firstWhereOrNull((c) => c.id == selectedCalId)?.name ??
              'Selected Calendar');

    const accentColor = Color(0xFF6750A4);

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google / Device Calendar',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSyncEnabled
                                ? Colors.green
                                : AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isSyncEnabled
                                ? (lastSync != null
                                      ? 'Sync ${_formatTime(lastSync)}'
                                      : '2-Way Sync Active')
                                : 'Disabled',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '· 2-Way Sync',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.tertiary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Toggle
              Switch(
                value: isSyncEnabled,
                activeThumbColor: accentColor,
                onChanged: (val) async {
                  if (val) {
                    final granted = await ref
                        .read(calendarServiceProvider)
                        .requestPermissions();
                    if (granted) {
                      await ref
                          .read(calendarSyncEnabledProvider.notifier)
                          .toggle(true);
                      await ref
                          .read(calendarSyncControllerProvider.notifier)
                          .syncNow();
                    }
                  } else {
                    await ref
                        .read(calendarSyncEnabledProvider.notifier)
                        .toggle(false);
                  }
                },
              ),
            ],
          ),
          if (isSyncEnabled) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 12),
            // Target calendar selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Calendar',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedCalName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _showCalendarPickerSheet(context),
                  icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                  label: const Text('Change'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Sync now button & info
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Moving workouts in Google Calendar updates Herculex and vice-versa.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.tertiary,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: syncState.isSyncing
                      ? null
                      : () async {
                          final res = await ref
                              .read(calendarSyncControllerProvider.notifier)
                              .syncNow();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  res.success
                                      ? 'Calendar synced (${res.pushedCount} pushed, ${res.pulledCount} pulled)'
                                      : 'Sync error: ${res.error}',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                  icon: syncState.isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: Text(syncState.isSyncing ? 'Syncing...' : 'Sync Now'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showCalendarPickerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final theme = Theme.of(ctx);
            final calsAsync = ref.watch(availableCalendarsProvider);
            final currentSelected = ref.watch(selectedCalendarIdProvider);

            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Calendar for Workouts',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose which calendar on your device should hold Herculex workouts.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: currentSelected == null
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : null,
                    leading: const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFF6750A4),
                    ),
                    title: const Text('Herculex Training (Dedicated)'),
                    subtitle: const Text('Creates a separate clean calendar'),
                    trailing: currentSelected == null
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFF6750A4),
                          )
                        : null,
                    onTap: () {
                      ref
                          .read(selectedCalendarIdProvider.notifier)
                          .setCalendarId(null);
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 16),
                  calsAsync.when(
                    data: (cals) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: cals.map((cal) {
                          final isSelected = currentSelected == cal.id;
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            tileColor: isSelected
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : null,
                            leading: Icon(
                              Icons.calendar_today_rounded,
                              color: cal.color != null
                                  ? Color(cal.color!)
                                  : AppColors.secondary,
                            ),
                            title: Text(cal.name ?? 'Unnamed Calendar'),
                            subtitle: Text(cal.accountName ?? 'Local Account'),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF6750A4),
                                  )
                                : null,
                            onTap: () {
                              ref
                                  .read(selectedCalendarIdProvider.notifier)
                                  .setCalendarId(cal.id);
                              Navigator.pop(ctx);
                            },
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => Text('Could not load calendars: $e'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Sex selector ─────────────────────────────────────────────────────────

  Widget _buildSexSelectorCard(ThemeData theme, Profile? profile) {
    final currentSex = profile?.sex;
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Select Sex',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              _buildSexPill('Male', BiologicalSex.male, currentSex, profile),
              const SizedBox(width: 8),
              _buildSexPill(
                'Female',
                BiologicalSex.female,
                currentSex,
                profile,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSexPill(
    String label,
    BiologicalSex sex,
    BiologicalSex? selectedSex,
    Profile? profile,
  ) {
    final isSelected = selectedSex == sex;
    return InkWell(
      onTap: () {
        if (profile != null) {
          final updated = profile.copyWith(sex: sex);
          ref.read(localProfileRepositoryProvider).save(updated);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ─── Impact card ──────────────────────────────────────────────────────────

  Widget _buildImpactCard(
    ThemeData theme,
    String message,
    String label,
    bool isWarning,
  ) {
    return GlassContainer(
      color: isWarning
          ? theme.colorScheme.secondary.withValues(alpha: 0.1)
          : AppColors.primaryContainer.withValues(alpha: 0.2),
      border: Border.all(
        color: isWarning
            ? theme.colorScheme.secondary
            : AppColors.primaryContainer,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isWarning
                  ? theme.colorScheme.secondary.withValues(alpha: 0.2)
                  : AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isWarning ? Icons.warning_amber_rounded : Icons.offline_bolt,
              color: isWarning
                  ? theme.colorScheme.secondary
                  : AppColors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isWarning
                        ? theme.colorScheme.secondary
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(message, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Cycle sync ───────────────────────────────────────────────────────────

  Widget _buildCycleSyncSection(ThemeData theme) {
    final adjustmentAsync = ref.watch(cycleAdjustmentProvider);
    final syncState = ref.watch(cycleSyncNotifierProvider);

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current predicted phase',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              adjustmentAsync.when(
                data: (adj) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    adj.phase.id.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                loading: () => const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, _) => const Text('-'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          adjustmentAsync.when(
            data: (adj) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adj.trainingRecommendation,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Impact: ${adj.statusLabel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: syncState.isSyncingHealth
                      ? null
                      : () async {
                          await ref
                              .read(cycleSyncNotifierProvider.notifier)
                              .syncFromHealthApps();
                        },
                  icon: syncState.isSyncingHealth
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: const Text('Sync Flo / Health'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutes.cycle),
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Open Tracker'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Biometrics ───────────────────────────────────────────────────────────

  Widget _buildEmptyBiometricsCard(ThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.monitor_heart_outlined,
            size: 36,
            color: AppColors.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'No Synced Data Yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Connect at least one integration above to sync biometric data.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricsGrid(
    ThemeData theme,
    List<HealthSampleData> samples,
    DailyHealthRead? lastRead,
  ) {
    double? val(String kind) {
      final read = lastRead?.readForKind(kind);
      if (read != null && !read.isAvailable) return null;
      return samples.where((s) => s.kind == kind).firstOrNull?.value;
    }

    String? status(String kind) {
      final read = lastRead?.readForKind(kind);
      if (read == null || read.isAvailable) return null;
      return _statusText(read.status);
    }

    final steps = val('steps');
    final sleep = val('sleep_hours');
    final kcal = val('active_kcal');
    final hr = val('resting_hr');
    final water = val('water_ml');
    final food = val('food_kcal');

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.3,
      children: [
        _buildMetricCard(
          'ACTIVE STEPS',
          steps == null ? null : '${steps.round()} steps',
          Icons.directions_walk,
          Colors.orange,
          theme,
          status: status('steps'),
        ),
        _buildMetricCard(
          'SLEEP DEPTH',
          sleep == null ? null : '${sleep.toStringAsFixed(1)} hrs',
          Icons.bedtime,
          Colors.indigo,
          theme,
          status: status('sleep_hours'),
        ),
        _buildMetricCard(
          'WATER INTAKE',
          water == null ? null : '${water.round()} ml',
          Icons.water_drop,
          Colors.blue,
          theme,
          status: status('water_ml'),
        ),
        _buildMetricCard(
          'FOOD ENERGY',
          food == null ? null : '${food.round()} kcal',
          Icons.restaurant,
          Colors.green,
          theme,
          status: status('food_kcal'),
        ),
        _buildMetricCard(
          'ACTIVE KCAL',
          kcal == null ? null : '${kcal.round()} kcal',
          Icons.local_fire_department,
          Colors.red,
          theme,
          status: status('active_kcal'),
        ),
        _buildMetricCard(
          'RESTING HR',
          hr == null ? null : '${hr.round()} bpm',
          Icons.favorite,
          Colors.teal,
          theme,
          status: status('resting_hr'),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String label,
    String? value,
    IconData icon,
    Color color,
    ThemeData theme, {
    String? status,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          Text(
            value ?? status ?? 'No data',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: value == null ? 16 : null,
              color: value == null ? AppColors.secondary : null,
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(HealthReadStatus status) {
    switch (status) {
      case HealthReadStatus.available:
        return 'Available';
      case HealthReadStatus.denied:
        return 'Permission denied';
      case HealthReadStatus.unavailable:
        return 'Unavailable';
      case HealthReadStatus.error:
        return 'Read error';
      case HealthReadStatus.empty:
        return 'No data';
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _togglePermission(String key, bool connect) async {
    if (connect) {
      final success = await ref
          .read(healthServiceProvider)
          .requestPermissions(key);
      if (success) {
        final current = ref.read(healthPermissionStatusProvider);
        ref.read(healthPermissionStatusProvider.notifier).state = {
          ...current,
          key: true,
        };
        _syncAllData();
      }
    } else {
      final current = ref.read(healthPermissionStatusProvider);
      ref.read(healthPermissionStatusProvider.notifier).state = {
        ...current,
        key: false,
      };
    }
  }

  Future<void> _syncAllData() async {
    setState(() => _isSyncing = true);
    final result = await ref.read(healthServiceProvider).runDailySync();
    ref.read(lastDailyHealthReadProvider.notifier).state = result;
    ref.read(lastHealthSyncTimestampProvider.notifier).state = DateTime.now();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_syncMessage(result)),
        backgroundColor: result.hasAnyAvailableMetric
            ? AppColors.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _syncMessage(DailyHealthRead result) {
    if (result.hasAnyAvailableMetric) {
      final parts = <String>[];
      if (result.steps.isAvailable && result.steps.value != null) {
        parts.add('${result.steps.value!.round()} steps');
      }
      if (result.activeKcal.isAvailable && result.activeKcal.value != null) {
        parts.add('${result.activeKcal.value!.round()} kcal');
      }
      if (result.sleepHours.isAvailable && result.sleepHours.value != null) {
        parts.add('${result.sleepHours.value!.toStringAsFixed(1)}h sleep');
      }
      if (parts.isNotEmpty) {
        return 'Synced: ${parts.join(', ')}';
      }
      return 'Health data synced.';
    }
    switch (result.overallStatus) {
      case HealthReadStatus.denied:
        return 'Access to health data was denied.';
      case HealthReadStatus.unavailable:
        return 'Health data is not available on this device.';
      case HealthReadStatus.error:
        return 'Failed to read health data.';
      case HealthReadStatus.empty:
        return 'No new health data in Health Connect for today.';
      case HealthReadStatus.available:
        return 'Health data synced.';
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
