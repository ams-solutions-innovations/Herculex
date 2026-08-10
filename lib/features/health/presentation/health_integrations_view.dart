import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../../../widgets/glass_container.dart';
import 'health_providers.dart';
import 'cycle_providers.dart';
import 'health_platform_detail_view.dart';
import '../../../data/local/database.dart';
import '../../profile/domain/profile.dart';

class HealthIntegrationsView extends ConsumerStatefulWidget {
  const HealthIntegrationsView({super.key});

  @override
  ConsumerState<HealthIntegrationsView> createState() =>
      _HealthIntegrationsViewState();
}

class _HealthIntegrationsViewState
    extends ConsumerState<HealthIntegrationsView> {
  bool _isSyncing = false;
  double _periodDays = 5;
  double _cycleDays = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = ref.watch(healthPermissionStatusProvider);
    final autoAdjust = ref.watch(autoAdjustGymVolumeProvider);
    final samplesAsync = ref.watch(todayHealthSamplesProvider);
    final adjustmentAsync = ref.watch(activityBasedAdjustmentProvider);
    final lastSyncTime = ref.watch(lastHealthSyncTimestampProvider);

    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;
    final isFemale = profile?.sex == BiologicalSex.female;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'HEALTH & SYNC',
          style: theme.textTheme.titleMedium
              ?.copyWith(letterSpacing: 2.0, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
        children: [
          // ── Activity impact card ───────────────────────────────────────
          adjustmentAsync.when(
            data: (adj) => _buildImpactCard(
                theme, adj.message, adj.statusLabel, adj.volumeFactor < 1.0),
            loading: () => const Center(child: LinearProgressIndicator()),
            error: (err, stack) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 32),

          // ── Biological sex ────────────────────────────────────────────
          Center(
            child: Text(
              'BIOLOGICAL SEX',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.secondary, letterSpacing: 1.0),
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
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.secondary, letterSpacing: 1.0),
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
                        icon: Icon(Icons.sync_rounded,
                            size: 20, color: AppColors.primary),
                        onPressed: _syncAllData,
                        tooltip: 'Sinhroniziraj vse',
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Platform cards ─────────────────────────────────────────────
          _buildPlatformCard(
            theme: theme,
            platform: HealthPlatform.samsung,
            name: 'Samsung Health',
            subtitle: 'Health Connect API · Android',
            icon: Icons.watch_rounded,
            accentColor: const Color(0xFF1428A0),
            isConnected: permissions['samsung'] ?? false,
            permKey: 'samsung',
            lastSync: lastSyncTime,
            route: '/health/samsung',
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 32),

          // ── Cycle sync (females only) ──────────────────────────────────
          if (isFemale) ...[
            Center(
              child: Text(
                'CYCLE SYNC',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.secondary, letterSpacing: 1.0),
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
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.secondary, letterSpacing: 1.0),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Switch(
                  value: autoAdjust,
                  onChanged: (val) {
                    ref
                        .read(autoAdjustGymVolumeProvider.notifier)
                        .state = val;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Ko je vklopljeno, Herculex prilagodi dnevna priporočila za število serij glede na globino spanca, počivajoči srčni utrip in kardiovaskularni stres.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
          ),
          const SizedBox(height: 32),

          // ── Today's biometrics ────────────────────────────────────────
          Center(
            child: Text(
              "TODAY'S BIOMETRICS",
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.secondary, letterSpacing: 1.0),
            ),
          ),
          const SizedBox(height: 16),
          samplesAsync.when(
            data: (samples) {
              if (samples.isEmpty) return _buildEmptyBiometricsCard(theme);
              return _buildBiometricsGrid(theme, samples);
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (err, stack) =>
                Center(child: Text('Error: $err')),
          ),
        ],
      ),
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
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
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
                      Text(
                        isConnected
                            ? (lastSync != null
                                ? 'Sync ${_formatTime(lastSync)}'
                                : 'Povezano')
                            : 'Ni povezano',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· $subtitle',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.tertiary,
                          fontSize: 10,
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
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.secondary),
          ],
        ),
      ),
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
          Text('Select Sex',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Row(
            children: [
              _buildSexPill('Male', BiologicalSex.male, currentSex, profile),
              const SizedBox(width: 8),
              _buildSexPill(
                  'Female', BiologicalSex.female, currentSex, profile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSexPill(String label, BiologicalSex sex,
      BiologicalSex? selectedSex, Profile? profile) {
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
          color:
              isSelected ? AppColors.primary : AppColors.surfaceContainer,
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
      ThemeData theme, String message, String label, bool isWarning) {
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
              isWarning
                  ? Icons.warning_amber_rounded
                  : Icons.offline_bolt,
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
    final phaseAsync = ref.watch(predictedPhaseProvider);
    final phaseStr = phaseAsync.valueOrNull ?? 'follicular';

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current predicted phase',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  phaseStr.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Cycle length: ${_cycleDays.round()} days',
              style: theme.textTheme.labelLarge),
          Slider(
            value: _cycleDays,
            min: 21,
            max: 35,
            divisions: 14,
            onChanged: (val) {
              setState(() => _cycleDays = val);
              _updateCycleSettings();
            },
          ),
          const SizedBox(height: 16),
          Text('Period length: ${_periodDays.round()} days',
              style: theme.textTheme.labelLarge),
          Slider(
            value: _periodDays,
            min: 3,
            max: 10,
            divisions: 7,
            onChanged: (val) {
              setState(() => _periodDays = val);
              _updateCycleSettings();
            },
          ),
        ],
      ),
    );
  }

  void _updateCycleSettings() async {
    final repo = ref.read(cycleRepositoryProvider);
    await repo.saveSettings(
      avgCycleDays: _cycleDays.round(),
      avgPeriodDays: _periodDays.round(),
      lastPeriodStart: DateTime.now().subtract(const Duration(days: 10)),
    );
    ref.invalidate(cycleSettingsProvider);
  }

  // ─── Biometrics ───────────────────────────────────────────────────────────

  Widget _buildEmptyBiometricsCard(ThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.monitor_heart_outlined,
              size: 36, color: AppColors.outline),
          const SizedBox(height: 12),
          Text('No Synced Data Yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Poveži vsaj eno integracijo zgoraj, da sinhroniziraš biometrične podatke.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.secondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricsGrid(
      ThemeData theme, List<HealthSampleData> samples) {
    double val(String kind) => samples
        .firstWhere((s) => s.kind == kind,
            orElse: () => HealthSampleData(
                id: 0, dateIso: '', kind: kind, value: 0.0))
        .value;

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
        _buildMetricCard('ACTIVE STEPS', '${steps.round()} steps',
            Icons.directions_walk, Colors.orange, theme),
        _buildMetricCard('SLEEP DEPTH', '${sleep.toStringAsFixed(1)} hrs',
            Icons.bedtime, Colors.indigo, theme),
        _buildMetricCard('WATER INTAKE', '${water.round()} ml',
            Icons.water_drop, Colors.blue, theme),
        _buildMetricCard('FOOD ENERGY', '${food.round()} kcal',
            Icons.restaurant, Colors.green, theme),
        _buildMetricCard('ACTIVE KCAL', '${kcal.round()} kcal',
            Icons.local_fire_department, Colors.red, theme),
        _buildMetricCard(
            'RESTING HR', '${hr.round()} bpm', Icons.favorite, Colors.teal, theme),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon,
      Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3)),
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
                    letterSpacing: 1.0),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _togglePermission(String key, bool connect) async {
    if (connect) {
      final success =
          await ref.read(healthServiceProvider).requestPermissions(key);
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
    await ref.read(healthServiceProvider).runDailySync();
    ref.read(lastHealthSyncTimestampProvider.notifier).state = DateTime.now();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Zdravstveni podatki uspešno sinhronizirani! 🍃'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}