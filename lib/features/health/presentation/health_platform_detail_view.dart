import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/health/domain/health_read_state.dart';
import 'package:herculex/features/health/presentation/health_providers.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/ui/ui.dart';
import 'package:herculex/widgets/glass_container.dart';

enum HealthPlatform { samsung, apple, google }

class HealthPlatformDetailView extends ConsumerStatefulWidget {
  final HealthPlatform platform;
  const HealthPlatformDetailView({super.key, required this.platform});

  @override
  ConsumerState<HealthPlatformDetailView> createState() =>
      _HealthPlatformDetailViewState();
}

class _HealthPlatformDetailViewState
    extends ConsumerState<HealthPlatformDetailView> {
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _hydratePermissionStatus(),
    );
  }

  /// Reconciles this platform's "connected" toggle with the real OS grant,
  /// since the status map isn't persisted and resets to false on every launch.
  Future<void> _hydratePermissionStatus() async {
    final granted = await ref.read(healthServiceProvider).checkHasPermissions();
    if (!mounted) return;
    final platformKey = widget.platform.name;
    final appliesToThisScreen =
        (Platform.isAndroid &&
            (platformKey == 'samsung' || platformKey == 'google')) ||
        (Platform.isIOS && platformKey == 'apple');
    if (!appliesToThisScreen) return;
    final current = ref.read(healthPermissionStatusProvider);
    ref.read(healthPermissionStatusProvider.notifier).state = {
      ...current,
      platformKey: granted,
    };
  }

  // ─── Platform meta ────────────────────────────────────────────────────────

  String get _title {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return 'Samsung Health';
      case HealthPlatform.apple:
        return 'Apple Health';
      case HealthPlatform.google:
        return 'Health Connect';
    }
  }

  Color get _accentColor {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return const Color(0xFF1428A0); // Samsung blue
      case HealthPlatform.apple:
        return const Color(0xFFFF375F); // Apple red
      case HealthPlatform.google:
        return const Color(0xFF4285F4); // Google blue
    }
  }

  IconData get _icon {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return Icons.watch_rounded;
      case HealthPlatform.apple:
        return Icons.health_and_safety_rounded;
      case HealthPlatform.google:
        return Icons.monitor_heart_rounded;
    }
  }

  String get _description {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return 'Two-way sync via Samsung Health SDK and Health Connect API.';
      case HealthPlatform.apple:
        return 'Sync via HealthKit API on iPhone and Apple Watch.';
      case HealthPlatform.google:
        return 'Sync via Google Health Connect on Android devices.';
    }
  }

  // ─── Categories config ────────────────────────────────────────────────────

  List<_CategoryItem> get _categories {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return [
          _CategoryItem(
            'Food and macronutrients',
            Icons.restaurant_rounded,
            samsungHealthSyncFoodProvider,
          ),
          _CategoryItem(
            'Water and hydration',
            Icons.water_drop_rounded,
            samsungHealthSyncWaterProvider,
          ),
          _CategoryItem(
            'Daily steps',
            Icons.directions_walk_rounded,
            samsungHealthSyncStepsProvider,
          ),
          _CategoryItem(
            'Workouts and cardio',
            Icons.fitness_center_rounded,
            samsungHealthSyncWorkoutsProvider,
          ),
          _CategoryItem(
            'Sleep and sleep stages',
            Icons.bedtime_rounded,
            samsungHealthSyncSleepProvider,
          ),
          _CategoryItem(
            'Heart rate, HRV and biometrics',
            Icons.favorite_rounded,
            samsungHealthSyncBiometricsProvider,
          ),
          _CategoryItem(
            'Body weight',
            Icons.monitor_weight_rounded,
            samsungHealthSyncWeightProvider,
          ),
        ];
      case HealthPlatform.apple:
        return [
          _CategoryItem(
            'Food and macronutrients',
            Icons.restaurant_rounded,
            appleHealthSyncFoodProvider,
          ),
          _CategoryItem(
            'Water and hydration',
            Icons.water_drop_rounded,
            appleHealthSyncWaterProvider,
          ),
          _CategoryItem(
            'Daily steps',
            Icons.directions_walk_rounded,
            appleHealthSyncStepsProvider,
          ),
          _CategoryItem(
            'Workouts and cardio',
            Icons.fitness_center_rounded,
            appleHealthSyncWorkoutsProvider,
          ),
          _CategoryItem(
            'Sleep and sleep stages',
            Icons.bedtime_rounded,
            appleHealthSyncSleepProvider,
          ),
          _CategoryItem(
            'Heart rate, HRV and biometrics',
            Icons.favorite_rounded,
            appleHealthSyncBiometricsProvider,
          ),
          _CategoryItem(
            'Body weight',
            Icons.monitor_weight_rounded,
            appleHealthSyncWeightProvider,
          ),
          _CategoryItem(
            'Mindfulness and breathing',
            Icons.self_improvement_rounded,
            appleHealthSyncMindfulnessProvider,
          ),
        ];
      case HealthPlatform.google:
        return [
          _CategoryItem(
            'Food and macronutrients',
            Icons.restaurant_rounded,
            googleHealthSyncFoodProvider,
          ),
          _CategoryItem(
            'Water and hydration',
            Icons.water_drop_rounded,
            googleHealthSyncWaterProvider,
          ),
          _CategoryItem(
            'Daily steps',
            Icons.directions_walk_rounded,
            googleHealthSyncStepsProvider,
          ),
          _CategoryItem(
            'Workouts and cardio',
            Icons.fitness_center_rounded,
            googleHealthSyncWorkoutsProvider,
          ),
          _CategoryItem(
            'Sleep and sleep stages',
            Icons.bedtime_rounded,
            googleHealthSyncSleepProvider,
          ),
          _CategoryItem(
            'Heart rate, HRV and biometrics',
            Icons.favorite_rounded,
            googleHealthSyncBiometricsProvider,
          ),
          _CategoryItem(
            'Body weight',
            Icons.monitor_weight_rounded,
            googleHealthSyncWeightProvider,
          ),
          _CategoryItem(
            'Blood oxygen saturation (SpO₂)',
            Icons.air_rounded,
            googleHealthSyncBloodOxygenProvider,
          ),
        ];
    }
  }

  StateProvider<bool> get _autoSyncProvider {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return samsungHealthAutoSync3xProvider;
      case HealthPlatform.apple:
        return appleHealthAutoSyncProvider;
      case HealthPlatform.google:
        return googleHealthAutoSyncProvider;
    }
  }

  StateProvider<bool> get _bidirectionalProvider {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return samsungHealthBidirectionalProvider;
      case HealthPlatform.apple:
        return appleHealthBidirectionalProvider;
      case HealthPlatform.google:
        return googleHealthBidirectionalProvider;
    }
  }

  String get _autoSyncLabel {
    switch (widget.platform) {
      case HealthPlatform.samsung:
        return 'Automatic sync (3× / day)';
      case HealthPlatform.apple:
        return 'Automatic background sync';
      case HealthPlatform.google:
        return 'Automatic background sync';
    }
  }

  // ─── Sync action ──────────────────────────────────────────────────────────

  Future<void> _syncNow() async {
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
            ? _accentColor
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
        return '$_title synced: ${parts.join(', ')}';
      }
      return '$_title synced.';
    }
    switch (result.overallStatus) {
      case HealthReadStatus.denied:
        return 'Access to $_title was denied.';
      case HealthReadStatus.unavailable:
        return '$_title is not available on this device.';
      case HealthReadStatus.error:
        return 'Failed to read from $_title.';
      case HealthReadStatus.empty:
        return 'No data for today in $_title.';
      case HealthReadStatus.available:
        return '$_title synced.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = ref.watch(healthPermissionStatusProvider);
    final platformKey = widget.platform.name;
    final isConnected = permissions[platformKey] ?? false;
    final autoSync = ref.watch(_autoSyncProvider);
    final bidirectional = ref.watch(_bidirectionalProvider);
    final lastSync = ref.watch(lastHealthSyncTimestampProvider);

    return HxScreenShell(
      title: _title,
      children: [
        // ── Header card ───────────────────────────────────────────────────
          _buildHeaderCard(theme, isConnected, lastSync, platformKey),
          const SizedBox(height: 24),

          if (isConnected) ...[
            // ── Categories ────────────────────────────────────────────────
            _buildSectionLabel('SYNC CATEGORIES', theme),
            const SizedBox(height: 12),
            _buildCategoriesCard(theme),
            const SizedBox(height: 24),

            // ── Sync settings ─────────────────────────────────────────────
            _buildSectionLabel('SYNC SETTINGS', theme),
            const SizedBox(height: 12),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildSettingRow(
                    theme,
                    _autoSyncLabel,
                    'Automatically import and export data',
                    Icons.sync_rounded,
                    autoSync,
                    (v) => ref.read(_autoSyncProvider.notifier).state = v,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: Colors.white10),
                  ),
                  _buildSettingRow(
                    theme,
                    'Two-way sync',
                    'Export data from Herculex to $_title',
                    Icons.swap_horiz_rounded,
                    bidirectional,
                    (v) => ref.read(_bidirectionalProvider.notifier).state = v,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Watch Sync Guidance Card (for Samsung / Android) ───────────
            if (widget.platform == HealthPlatform.samsung ||
                widget.platform == HealthPlatform.google) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
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
                          Icons.watch_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'WATCH SYNC (GALAXY WATCH)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The watch saves steps to Samsung Health, which forwards them to Health Connect.\n'
                      '• If the watch shows more steps than the app, open Samsung Health on your phone briefly to refresh data.\n'
                      '• In Health Connect > Data sources, set Samsung Health to the top priority.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        height: 1.4,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Sync now button ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _syncNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
                label: Text(
                  _isSyncing ? 'Syncing...' : 'Sync now',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

  // ─── Sub-widgets ──────────────────────────────────────────────────────────

  Widget _buildHeaderCard(
    ThemeData theme,
    bool isConnected,
    DateTime? lastSync,
    String key,
  ) {
    final accent = _accentColor;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: accent, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Connection status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green : AppColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isConnected
                      ? lastSync != null
                            ? 'Last sync: ${_formatTime(lastSync)}'
                            : 'Connected — no previous syncs'
                      : 'Not connected — enable to grant access',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
              // Connection toggle
              Switch(
                value: isConnected,
                activeThumbColor: accent,
                onChanged: (val) => _toggleConnection(key, val),
              ),
            ],
          ),
          if (!isConnected) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _toggleConnection(key, true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text(
                  'Connect',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoriesCard(ThemeData theme) {
    final cats = _categories;
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          for (int i = 0; i < cats.length; i++) ...[
            _buildCategoryRow(theme, cats[i]),
            if (i < cats.length - 1)
              const Divider(height: 1, color: Colors.white10),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryRow(ThemeData theme, _CategoryItem item) {
    final value = ref.watch(item.provider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, size: 18, color: _accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              item.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: _accentColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => ref.read(item.provider.notifier).state = v,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(
    ThemeData theme,
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text, ThemeData theme) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: AppColors.secondary,
        letterSpacing: 1.0,
        fontSize: 11,
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _toggleConnection(String key, bool connect) async {
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
        _syncNow();
      }
    } else {
      final current = ref.read(healthPermissionStatusProvider);
      ref.read(healthPermissionStatusProvider.notifier).state = {
        ...current,
        key: false,
      };
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Internal category descriptor
class _CategoryItem {
  final String label;
  final IconData icon;
  final StateProvider<bool> provider;
  const _CategoryItem(this.label, this.icon, this.provider);
}
