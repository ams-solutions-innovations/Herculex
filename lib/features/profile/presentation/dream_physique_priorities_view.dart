import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';

/// Full-page screen displaying active Dream Physique priorities analyzed by Gemini.
/// Allows viewing muscle rationales, target aesthetic details, adjusting priority
/// levels, and launching a new photo analysis.
class DreamPhysiquePrioritiesView extends ConsumerStatefulWidget {
  const DreamPhysiquePrioritiesView({super.key, this.initialProfile});

  final DreamPhysiqueProgrammingProfile? initialProfile;

  @override
  ConsumerState<DreamPhysiquePrioritiesView> createState() =>
      _DreamPhysiquePrioritiesViewState();
}

class _DreamPhysiquePrioritiesViewState
    extends ConsumerState<DreamPhysiquePrioritiesView> {
  bool _loading = true;
  bool _saving = false;
  bool _isDirty = false;
  DreamPhysiqueProgrammingProfile? _profile;
  List<ProgrammingMusclePriority> _priorities = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
      _priorities = List.from(widget.initialProfile!.musclePriorities);
      _loading = false;
    } else {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final row =
          await (db.select(db.physiqueProgrammingProfiles)
                ..where((table) => table.active.equals(true))
                ..orderBy([(table) => OrderingTerm.desc(table.confirmedAt)])
                ..limit(1))
              .getSingleOrNull();

      if (row != null) {
        final decoded = jsonDecode(row.prioritiesJson) as Map<String, dynamic>;
        final profile = DreamPhysiqueProgrammingProfile.fromJson(decoded);
        if (mounted) {
          setState(() {
            _profile = profile;
            _priorities = List.from(profile.musclePriorities);
            _loading = false;
            _isDirty = false;
          });
          return;
        }
      }
    } catch (_) {
      // Handled by empty state
    }
    if (mounted) {
      setState(() {
        _profile = null;
        _priorities = [];
        _loading = false;
        _isDirty = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_profile == null || _priorities.isEmpty || _saving) return;
    setState(() => _saving = true);
    Haptics.selection();

    try {
      final db = ref.read(appDatabaseProvider);
      final payload = {
        'schemaVersion': _profile!.schemaVersion,
        'overallConfidence': _profile!.overallConfidence,
        'musclePriorities': [
          for (final priority in _priorities)
            {
              'muscleId': priority.muscleId,
              'priority': priority.priority.wireValue,
              'confidence': priority.confidence,
              'rationale': priority.rationale,
              'uncertainties': priority.uncertainties,
            },
        ],
        'uncertainties': _profile!.uncertainties,
      };

      await db.transaction(() async {
        await db
            .update(db.physiqueProgrammingProfiles)
            .write(
              const PhysiqueProgrammingProfilesCompanion(active: Value(false)),
            );
        await db
            .into(db.physiqueProgrammingProfiles)
            .insert(
              PhysiqueProgrammingProfilesCompanion.insert(
                prioritiesJson: jsonEncode(payload),
                source: const Value('manual_adjustment'),
                modelVersion: Value('schema-${_profile!.schemaVersion}'),
              ),
            );
      });

      if (!mounted) return;
      Haptics.success();
      context.pop(true);
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          'Could not save priorities: $e',
          kind: AppNoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = ref.watch(dreamPhysiqueSummaryProvider).valueOrNull;

    if (_loading) {
      return const HxScreenShell(
        title: 'Dream Physique Priorities',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_profile == null || _priorities.isEmpty) {
      return HxScreenShell(
        title: 'Dream Physique Priorities',
        children: [_buildEmptyState(theme)],
      );
    }

    return HxScreenShell(
      title: 'Dream Physique Priorities',
      pinnedBottom: Container(
        padding: const EdgeInsets.only(top: HxSpace.x2, bottom: HxSpace.x4),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await context.push(AppRoutes.dreamPhysique);
                  if (mounted) _loadProfile();
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Set new goal'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (_isDirty) {
                          _saveChanges();
                        } else {
                          context.pop();
                        }
                      },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isDirty ? 'Save changes' : 'Done'),
              ),
            ),
          ],
        ),
      ),
      children: [
        Text(
          'AI-assessed goals & focus areas',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 14),
        if (summary != null) ...[
          _buildSummaryCard(theme, summary),
          const SizedBox(height: 20),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Prioritized Muscles',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'AI confidence ${(_profile!.overallConfidence * 100).round()}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _priorities.length; i++) ...[
          _buildPriorityCard(theme, i),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        if (_profile!.uncertainties.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Analysis notes',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _profile!.uncertainties.map((e) => '• $e').join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    DreamPhysiqueAnalysisSummary summary,
  ) {
    final weightChangeLabel = summary.weightChangeKg == 0
        ? 'Scale-weight steady'
        : '${summary.weightChangeKg > 0 ? '+' : ''}'
              '${summary.weightChangeKg.toStringAsFixed(1)} kg';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  summary.targetAestheticStyle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (summary.timeframeRange.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  summary.timeframeRange,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(
                theme,
                'Current BF',
                '${summary.currentEstimatedBf.toStringAsFixed(0)}%',
              ),
              Container(
                width: 1,
                height: 28,
                color: AppColors.outlineVariant.withValues(alpha: 0.35),
              ),
              _statItem(
                theme,
                'Target BF',
                '${summary.targetBfPercent.toStringAsFixed(0)}%',
              ),
              Container(
                width: 1,
                height: 28,
                color: AppColors.outlineVariant.withValues(alpha: 0.35),
              ),
              _statItem(theme, 'Weight goal', weightChangeLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(ThemeData theme, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityCard(ThemeData theme, int index) {
    final item = _priorities[index];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _muscleLabel(item.muscleId),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(item.confidence * 100).round()}% confidence',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<ProgrammingPriorityLevel>(
                  value: item.priority,
                  borderRadius: BorderRadius.circular(12),
                  items: ProgrammingPriorityLevel.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _priorityColor(
                                value,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _priorityLabel(value),
                              style: TextStyle(
                                color: _priorityColor(value),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null && value != item.priority) {
                      setState(() {
                        _priorities[index] = item.copyWith(priority: value);
                        _isDirty = true;
                      });
                      Haptics.selection();
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Remove priority',
                onPressed: () {
                  Haptics.light();
                  setState(() {
                    _priorities.removeAt(index);
                    _isDirty = true;
                  });
                },
              ),
            ],
          ),
          if (item.rationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.rationale,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 48,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No Dream Physique Priorities Set',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Take or upload photos to let Herculex AI analyze your physique and propose custom muscle volume targets.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await context.push(AppRoutes.dreamPhysique);
              if (mounted) _loadProfile();
            },
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Set Dream Physique Goal'),
          ),
        ],
      ),
    );
  }

  static String _priorityLabel(ProgrammingPriorityLevel value) {
    return switch (value) {
      ProgrammingPriorityLevel.high => 'High',
      ProgrammingPriorityLevel.medium => 'Medium',
      ProgrammingPriorityLevel.maintenance => 'Maintenance',
    };
  }

  static Color _priorityColor(ProgrammingPriorityLevel value) {
    return switch (value) {
      ProgrammingPriorityLevel.high => Colors.greenAccent.shade700,
      ProgrammingPriorityLevel.medium => AppColors.primary,
      ProgrammingPriorityLevel.maintenance => Colors.orangeAccent.shade700,
    };
  }

  static String _muscleLabel(String id) {
    const labels = <String, String>{
      'chest': 'Chest',
      'back': 'Back',
      'lats': 'Lats',
      'traps': 'Traps',
      'front_delts': 'Front delts',
      'side_delts': 'Side delts',
      'rear_delts': 'Rear delts',
      'biceps': 'Biceps',
      'triceps': 'Triceps',
      'forearms': 'Forearms',
      'abs': 'Abs',
      'obliques': 'Obliques',
      'neck': 'Neck',
      'quads': 'Quads',
      'hamstrings': 'Hamstrings',
      'glutes': 'Glutes',
      'calves': 'Calves',
      'adductors': 'Adductors',
      'abductors': 'Abductors',
    };
    return labels[id] ?? id;
  }
}
