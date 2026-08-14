import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../domain/cycle_adjuster.dart';
import 'cycle_providers.dart';

class CycleTrackingView extends ConsumerStatefulWidget {
  const CycleTrackingView({super.key});

  @override
  ConsumerState<CycleTrackingView> createState() => _CycleTrackingViewState();
}

class _CycleTrackingViewState extends ConsumerState<CycleTrackingView> {
  int _avgCycleDays = 28;
  int _avgPeriodDays = 5;
  DateTime _lastPeriodStart = DateTime.now().subtract(const Duration(days: 14));
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(cycleSettingsStreamProvider);
    final adjustmentAsync = ref.watch(cycleAdjustmentProvider);
    final syncState = ref.watch(cycleSyncNotifierProvider);

    settingsAsync.whenData((settings) {
      if (!_initialized && settings != null) {
        _avgCycleDays = settings.avgCycleDays;
        _avgPeriodDays = settings.avgPeriodDays;
        _lastPeriodStart = settings.lastPeriodStart;
        _initialized = true;
      }
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Cycle Syncing & Tracking'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: adjustmentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading cycle data: $err')),
        data: (adjustment) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Phase Hero / Visual Cycle Tracker ────────────────────────
                _buildCycleHero(theme, adjustment),

                const SizedBox(height: 20),

                // ── 2. Health & Flo Sync Card ──────────────────────────────────
                _buildHealthSyncCard(theme, syncState),

                const SizedBox(height: 20),

                // ── 3. Daily Phase & Intensity Override ────────────────────────
                _buildDailyOverrideCard(theme, adjustment),

                const SizedBox(height: 20),

                // ── 4. Cycle Settings (Lengths & Start Date) ───────────────────
                _buildCycleSettingsCard(theme),

                const SizedBox(height: 20),

                // ── 5. Phase Education & Training Intelligence ─────────────────
                _buildPhaseIntelligenceCard(theme, adjustment.phase),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCycleHero(ThemeData theme, CycleAdjustmentResult adjustment) {
    final phase = adjustment.phase;
    Color phaseColor;
    switch (phase) {
      case CyclePhase.menstrual:
        phaseColor = Colors.redAccent;
        break;
      case CyclePhase.follicular:
        phaseColor = Colors.orangeAccent;
        break;
      case CyclePhase.ovulatory:
        phaseColor = Colors.purpleAccent;
        break;
      case CyclePhase.luteal:
        phaseColor = AppColors.primary;
        break;
    }

    final progressPct = (adjustment.dayOfCycle + 1) / adjustment.totalCycleDays;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: phaseColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: phaseColor.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: phaseColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(phase.icon, color: phaseColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phase.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        phase.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: phaseColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  adjustment.isManualOverride ? 'OVERRIDE' : 'DAY ${adjustment.dayOfCycle + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: phaseColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Cycle progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progressPct.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Day ${adjustment.dayOfCycle + 1} of ${adjustment.totalCycleDays}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                '${adjustment.daysUntilNextPeriod} days to next period',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),

          // Training & Volume Impact
          Row(
            children: [
              Icon(Icons.fitness_center, size: 18, color: phaseColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  adjustment.statusLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: phaseColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            adjustment.trainingRecommendation,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurface,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthSyncCard(ThemeData theme, CycleSyncState syncState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sync, color: Colors.pinkAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sync with Flo & Health Apps',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Apple Health · Health Connect · Flo · Clue',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Flo and Apple Cycle Tracking automatically sync period dates to Apple Health & Health Connect. Syncing pulls your real logs to update predictions.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          if (syncState.syncMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                syncState.syncMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: syncState.isSyncingHealth
                  ? null
                  : () async {
                      await ref
                          .read(cycleSyncNotifierProvider.notifier)
                          .syncFromHealthApps();
                    },
              icon: syncState.isSyncingHealth
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(
                syncState.isSyncingHealth ? 'Syncing...' : 'Sync Period Data from Health / Flo',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyOverrideCard(ThemeData theme, CycleAdjustmentResult adjustment) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Today\'s Override & Log',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (adjustment.isManualOverride)
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(cycleSyncNotifierProvider.notifier)
                        .clearManualOverride(DateTime.now());
                  },
                  child: const Text('Reset to Auto'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Override today\'s phase if your cycle started early/late or if you are feeling different energy levels.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Phase Selection Buttons
          Row(
            children: CyclePhase.values.map((phase) {
              final isSelected = adjustment.phase == phase;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () async {
                      await ref
                          .read(cycleSyncNotifierProvider.notifier)
                          .setManualOverride(
                            date: DateTime.now(),
                            phase: phase,
                            intensity: 3,
                          );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryContainer
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            phase.icon,
                            size: 18,
                            color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            phase.id.substring(0, 3).toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleSettingsCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cycle Parameters',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Last Period Start Date
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Last Period Start Date'),
            subtitle: Text(
              '${_lastPeriodStart.year}-${_lastPeriodStart.month.toString().padLeft(2, '0')}-${_lastPeriodStart.day.toString().padLeft(2, '0')}',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
            trailing: const Icon(Icons.calendar_today, size: 20),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _lastPeriodStart,
                firstDate: DateTime.now().subtract(const Duration(days: 120)),
                lastDate: DateTime.now().add(const Duration(days: 7)),
              );
              if (picked != null) {
                setState(() => _lastPeriodStart = picked);
                await ref
                    .read(cycleSyncNotifierProvider.notifier)
                    .saveSettings(
                      avgCycleDays: _avgCycleDays,
                      avgPeriodDays: _avgPeriodDays,
                      lastPeriodStart: picked,
                    );
              }
            },
          ),
          Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),

          // Average Cycle Length
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Average Cycle Length'),
              Text(
                '$_avgCycleDays days',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: _avgCycleDays.toDouble(),
            min: 21,
            max: 40,
            divisions: 19,
            activeColor: AppColors.primary,
            onChanged: (val) {
              setState(() => _avgCycleDays = val.round());
            },
            onChangeEnd: (val) async {
              await ref
                  .read(cycleSyncNotifierProvider.notifier)
                  .saveSettings(
                    avgCycleDays: val.round(),
                    avgPeriodDays: _avgPeriodDays,
                    lastPeriodStart: _lastPeriodStart,
                  );
            },
          ),

          // Average Period Length
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Average Period Duration'),
              Text(
                '$_avgPeriodDays days',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: _avgPeriodDays.toDouble(),
            min: 3,
            max: 10,
            divisions: 7,
            activeColor: AppColors.primary,
            onChanged: (val) {
              setState(() => _avgPeriodDays = val.round());
            },
            onChangeEnd: (val) async {
              await ref
                  .read(cycleSyncNotifierProvider.notifier)
                  .saveSettings(
                    avgCycleDays: _avgCycleDays,
                    avgPeriodDays: val.round(),
                    lastPeriodStart: _lastPeriodStart,
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseIntelligenceCard(ThemeData theme, CyclePhase currentPhase) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Physiological Intelligence',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          _buildPhaseRow(
            theme,
            phase: CyclePhase.menstrual,
            isCurrent: currentPhase == CyclePhase.menstrual,
            focus: 'Recovery, mobility, deload volume (-20%)',
            nutrition: 'Iron, magnesium, anti-inflammatory foods',
          ),
          const SizedBox(height: 12),
          _buildPhaseRow(
            theme,
            phase: CyclePhase.follicular,
            isCurrent: currentPhase == CyclePhase.follicular,
            focus: 'Progressive overload, high volume (+10%)',
            nutrition: 'Carbohydrate utilization, lean protein',
          ),
          const SizedBox(height: 12),
          _buildPhaseRow(
            theme,
            phase: CyclePhase.ovulatory,
            isCurrent: currentPhase == CyclePhase.ovulatory,
            focus: 'Peak strength, 1RM attempts, heavy compounds',
            nutrition: 'Fiber, antioxidants, healthy fats',
          ),
          const SizedBox(height: 12),
          _buildPhaseRow(
            theme,
            phase: CyclePhase.luteal,
            isCurrent: currentPhase == CyclePhase.luteal,
            focus: 'Steady-state cardio, moderate load (-15%)',
            nutrition: 'Complex carbs, magnesium, healthy hydration',
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseRow(
    ThemeData theme, {
    required CyclePhase phase,
    required bool isCurrent,
    required String focus,
    required String nutrition,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primaryContainer.withValues(alpha: 0.3)
            : AppColors.surfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: isCurrent
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(phase.icon, size: 16, color: isCurrent ? AppColors.primary : AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                phase.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isCurrent ? AppColors.primary : AppColors.onSurface,
                ),
              ),
              if (isCurrent) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'CURRENT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '• Training: $focus',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '• Nutrition: $nutrition',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
