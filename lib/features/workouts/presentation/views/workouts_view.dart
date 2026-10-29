import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_content_width.dart';
import 'package:herculex/design_system/components/hx_top_tabs.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/gyms/presentation/gym_picker_sheet.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/presentation/sheets/day_detail_sheet.dart';
import 'package:herculex/features/programs/presentation/views/training_blocks_view.dart';
import 'package:herculex/features/programs/presentation/widgets/upcoming_workouts_panel.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/presentation/views/active_workout_view.dart';
import 'package:herculex/features/workouts/presentation/views/template_builder_view.dart';
import 'package:herculex/features/workouts/presentation/views/templates_view.dart';
import 'package:intl/intl.dart';

/// Widest the live workout grows in a wide window.
const _kLoggingMaxWidth = 960.0;

/// Widest the history and template lists grow: responsive columns of tiles on desktop.
const _kListMaxWidth = HxBreakpoints.wideMax;

class WorkoutsView extends ConsumerWidget {
  const WorkoutsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider);
    return active.when(
      data: (session) => session != null
          // The tab itself may be wide (the programs overview uses the room);
          // logging sets reads best in a column.
          ? HxContentWidth(
              maxWidth: _kLoggingMaxWidth,
              child: ActiveWorkoutView(session: session),
            )
          : const _WorkoutsLanding(),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _WorkoutsLanding extends ConsumerStatefulWidget {
  const _WorkoutsLanding();

  @override
  ConsumerState<_WorkoutsLanding> createState() => _WorkoutsLandingState();
}

class _WorkoutsLandingState extends ConsumerState<_WorkoutsLanding> {
  // Programs lives here as the third segment rather than as its own bottom
  // tab — contextual navigation belongs at the top of the section it
  // switches between, not in a second bottom bar.
  static const _segments = ['Sessions', 'Templates', 'Programs'];
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canStart = ref.watch(platformCapabilitiesProvider).hasLiveWorkout;
    final recentAsync = ref.watch(recentSessionsProvider);
    final hasSessions = recentAsync.asData?.value.isNotEmpty ?? false;
    final isWide = MediaQuery.sizeOf(context).width >= HxBreakpoints.rail;
    final showHeaderStart =
        canStart && (!isWide || _segment != 0 || hasSessions);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Workout',
                      style: theme.textTheme.displayMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      canStart
                          ? 'Log sets, supersets, and RPE. Rest timer starts when you check a set.'
                          : 'Review your sessions, build templates and plan your programs.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    if (showHeaderStart) ...[
                      Center(
                        child: PremiumButton(
                          text: 'Start Empty Workout',
                          icon: Icons.play_arrow,
                          onTap: () => _startEmptyWorkout(context, ref),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    // Three labels centered cleanly within max width.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: HxTopTabs(
                        labels: _segments,
                        index: _segment,
                        onChanged: (i) => setState(() => _segment = i),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _segment,
              children: [
                HxContentWidth(
                  maxWidth: _kListMaxWidth,
                  child: _RecentTab(
                    onSelectTab: (i) => setState(() => _segment = i),
                  ),
                ),
                const HxContentWidth(
                  maxWidth: _kListMaxWidth,
                  child: TemplatesView(),
                ),
                // The calendar has a side panel, so it takes the whole tab.
                const TrainingBlocksView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTab extends ConsumerStatefulWidget {
  final ValueChanged<int>? onSelectTab;

  const _RecentTab({this.onSelectTab});

  @override
  ConsumerState<_RecentTab> createState() => _RecentTabState();
}

class _RecentTabState extends ConsumerState<_RecentTab> {
  /// Long-pressing any row arms delete mode for the whole list; tapping
  /// anywhere outside a row disarms it again.
  bool _deleteMode = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = ref.watch(recentSessionsProvider);
    final canStart = ref.watch(platformCapabilitiesProvider).hasLiveWorkout;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _deleteMode ? () => setState(() => _deleteMode = false) : null,
      child: recent.when(
        data: (sessions) => sessions.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= HxBreakpoints.rail;
                  if (isWide) {
                    return _DesktopStarterDashboard(
                      onSelectTab: widget.onSelectTab,
                      onStartEmptyWorkout: () =>
                          _startEmptyWorkout(context, ref),
                      canStart: canStart,
                    );
                  }
                  return _MobileEmptySessions(
                    onSelectTab: widget.onSelectTab,
                    onStartEmptyWorkout: () => _startEmptyWorkout(context, ref),
                    canStart: canStart,
                  );
                },
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isWide =
                      constraints.maxWidth >= HxBreakpoints.twoColumns;
                  Widget tile(int i) => _SessionTile(
                    session: sessions[i],
                    deleteMode: _deleteMode,
                    onLongPress: () => setState(() => _deleteMode = true),
                    onDelete: () => _confirmDelete(sessions[i]),
                    isGrid: isWide,
                  );
                  const padding = EdgeInsets.fromLTRB(24, 12, 24, 120);
                  if (!isWide) {
                    return ListView.builder(
                      padding: padding,
                      itemCount: sessions.length,
                      itemBuilder: (_, i) => tile(i),
                    );
                  }
                  // Wide window: responsive 2 or 3 columns of history instead of one long
                  // list down the middle of the screen.
                  final crossAxisCount = constraints.maxWidth >= 1140 ? 3 : 2;
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Text(
                                '${sessions.length} Completed ${sessions.length == 1 ? 'Workout' : 'Workouts'}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              if (canStart)
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _startEmptyWorkout(context, ref),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Start Workout'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: padding,
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 104,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => tile(i),
                            childCount: sessions.length,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
        error: (e, _) => Center(child: Text('Error: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _confirmDelete(WorkoutSessionData session) async {
    final label = _displayName(session);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete workout?'),
        content: Text(
          'This permanently deletes "$label" and every set logged in it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(workoutsRepositoryProvider).deleteSession(session.id);
    if (mounted) {
      setState(() => _deleteMode = false);
    }
  }
}

/// Starts an empty live workout with multi-gym resolution.
Future<void> _startEmptyWorkout(BuildContext context, WidgetRef ref) async {
  final gym = await GymPickerSheet.resolve(context, ref);
  if (gym.cancelled) return;
  await ref.read(workoutsRepositoryProvider).startSession(gymId: gym.gymId);
}

/// Starts a live workout from a template with multi-gym resolution.
Future<void> _startTemplate(
  BuildContext context,
  WidgetRef ref,
  WorkoutTemplateData template,
) async {
  final canStart = ref.read(platformCapabilitiesProvider).hasLiveWorkout;
  if (!canStart) {
    TemplateBuilderView.show(context, existing: template);
    return;
  }
  final gym = await GymPickerSheet.resolve(context, ref);
  if (gym.cancelled) return;
  await ref
      .read(templatesRepositoryProvider)
      .startSessionFromTemplate(template.id, gymId: gym.gymId);
}

/// Desktop Starter Dashboard (State when `sessions.isEmpty` on desktop web).
class _DesktopStarterDashboard extends ConsumerWidget {
  final ValueChanged<int>? onSelectTab;
  final VoidCallback onStartEmptyWorkout;
  final bool canStart;

  const _DesktopStarterDashboard({
    required this.onSelectTab,
    required this.onStartEmptyWorkout,
    required this.canStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(workoutTemplatesProvider(-1));
    final activeProgramAsync = ref.watch(activeProgramProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column (Quick Starters & Templates)
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuickStarters(context, theme),
                const SizedBox(height: 24),
                _buildTemplatesSection(context, ref, theme, templatesAsync),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right Column (Upcoming Schedule & Volume/Recovery)
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUpcomingSchedule(context, ref, theme, activeProgramAsync),
                const SizedBox(height: 24),
                _buildVolumeAndRecovery(context, ref, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStarters(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Quick Start',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (canStart) ...[
            _QuickActionTile(
              icon: Icons.play_arrow_rounded,
              title: 'Start Empty Workout',
              subtitle:
                  'Log custom exercises with live rest timers & RPE tracking.',
              isPrimary: true,
              onTap: onStartEmptyWorkout,
            ),
            const SizedBox(height: 10),
          ],
          _QuickActionTile(
            icon: Icons.copy_rounded,
            title: 'Choose a Template',
            subtitle:
                'Pick from your saved templates or build custom routines.',
            onTap: () => onSelectTab?.call(1),
          ),
          const SizedBox(height: 10),
          _QuickActionTile(
            icon: Icons.calendar_month_rounded,
            title: 'Browse Training Programs',
            subtitle: 'Structured periodization blocks with scheduled splits.',
            onTap: () => onSelectTab?.call(2),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatesSection(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AsyncValue<List<WorkoutTemplateData>> templatesAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Popular Routines',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => onSelectTab?.call(1),
              child: const Text('All Templates →'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        templatesAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (templates) {
            if (templates.isNotEmpty) {
              final preview = templates.take(4).toList();
              return LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 500 ? 2 : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 80,
                    ),
                    itemCount: preview.length,
                    itemBuilder: (ctx, idx) => _SavedTemplateCard(
                      template: preview[idx],
                      onStart: () => _startTemplate(context, ref, preview[idx]),
                      onEdit: () => TemplateBuilderView.show(
                        context,
                        existing: preview[idx],
                      ),
                    ),
                  );
                },
              );
            }

            // No saved templates: show curated popular starter routines
            final starters = _kPresetStarterRoutines;
            return LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 500 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 96,
                  ),
                  itemCount: starters.length,
                  itemBuilder: (ctx, idx) => _PresetRoutineCard(
                    routine: starters[idx],
                    onTap: () => _onTapPreset(context, starters[idx]),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _onTapPreset(BuildContext context, _PresetStarterRoutine routine) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(routine.icon, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(routine.title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              routine.focus,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Target style: ${routine.tag}. Customize and save this routine as a template, or browse all templates.',
              style: TextStyle(color: AppColors.secondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(ctx);
              TemplateBuilderView.show(context);
            },
            child: const Text('Create Template'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onSelectTab?.call(1);
            },
            child: const Text('Go to Templates'),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingSchedule(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AsyncValue<ProgramData?> activeProgramAsync,
  ) {
    return activeProgramAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (program) {
        if (program != null) {
          return UpcomingWorkoutsPanel(
            programId: program.id,
            onOpenSession: (row) => DayDetailSheet.show(
              context,
              date: row.date,
              programId: program.id,
              initialScheduleId: row.id,
            ),
          );
        }

        // No active program: show invitation to explore programs
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_available_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Upcoming Schedule',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'No active training program',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Structured training blocks help automate progressive overload, calculate target weights, and plan deload weeks.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => onSelectTab?.call(2),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Explore Programs'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVolumeAndRecovery(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    final volumeAsync = ref.watch(weeklyMuscleVolumeProvider);
    final recoveryAsync = ref.watch(recoveryV3Provider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
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
                Icons.monitor_heart_outlined,
                color: context.hx.domainRecovery,
              ),
              const SizedBox(width: 10),
              Text(
                'Volume & Recovery',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => context.push(AppRoutes.muscleVolume),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    'Analytics →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Stats Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WEEKLY VOLUME',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      volumeAsync.when(
                        loading: () => const Text('Loading...'),
                        error: (_, _) => const Text('0 sets'),
                        data: (v) => Text(
                          '${v.totalSets} sets',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RECOVERY STATUS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      recoveryAsync.when(
                        loading: () => const Text('Checking...'),
                        error: (_, _) => const Text('Ready'),
                        data: (groups) {
                          final fatigued = groups
                              .where((g) => g.recoveryScore < 80)
                              .toList();
                          return Text(
                            fatigued.isEmpty
                                ? 'Fully Fresh'
                                : '${fatigued.length} Recovering',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: fatigued.isEmpty
                                  ? context.hx.domainRecovery
                                  : null,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Planning & coaching guidance tips
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Training & Recovery Tips',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _GuidanceTip(
                  text:
                      'Target 10–20 working sets per muscle group weekly across 2–3 sessions for progressive hypertrophy.',
                ),
                const SizedBox(height: 6),
                const _GuidanceTip(
                  text:
                      'Allow 48 hours between intense sessions of the same muscle group to maximize protein synthesis.',
                ),
                const SizedBox(height: 6),
                const _GuidanceTip(
                  text:
                      'Track RPE (Rate of Perceived Exertion) on heavy compounds to optimize intensity and avoid burnout.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidanceTip extends StatelessWidget {
  final String text;
  const _GuidanceTip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 8),
          child: Icon(Icons.circle, size: 4, color: AppColors.secondary),
        ),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPrimary;

  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isPrimary
          ? AppColors.primary.withValues(alpha: 0.1)
          : AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? AppColors.primary
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isPrimary ? Colors.white : AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isPrimary ? AppColors.primary : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetStarterRoutine {
  final String title;
  final String focus;
  final String tag;
  final IconData icon;

  const _PresetStarterRoutine({
    required this.title,
    required this.focus,
    required this.tag,
    required this.icon,
  });
}

const _kPresetStarterRoutines = [
  _PresetStarterRoutine(
    title: 'Upper Body Power',
    focus: 'Chest, Back, Shoulders & Arms',
    tag: 'Hypertrophy',
    icon: Icons.fitness_center_rounded,
  ),
  _PresetStarterRoutine(
    title: 'Lower Body Strength',
    focus: 'Quads, Hamstrings & Glutes',
    tag: 'Strength',
    icon: Icons.directions_run_rounded,
  ),
  _PresetStarterRoutine(
    title: 'Push Focus',
    focus: 'Chest, Front Delts & Triceps',
    tag: 'PPL Split',
    icon: Icons.accessibility_new_rounded,
  ),
  _PresetStarterRoutine(
    title: 'Pull Focus',
    focus: 'Lats, Rhomboids & Biceps',
    tag: 'PPL Split',
    icon: Icons.sports_gymnastics_rounded,
  ),
];

class _SavedTemplateCard extends ConsumerWidget {
  final WorkoutTemplateData template;
  final VoidCallback onStart;
  final VoidCallback onEdit;

  const _SavedTemplateCard({
    required this.template,
    required this.onStart,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final countAsync = ref.watch(templateExercisesProvider(template.id));
    final count = countAsync.asData?.value.length ?? 0;

    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      template.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      count == 1 ? '1 exercise' : '$count exercises',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Start', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetRoutineCard extends StatelessWidget {
  final _PresetStarterRoutine routine;
  final VoidCallback onTap;

  const _PresetRoutineCard({required this.routine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(routine.icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            routine.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            routine.tag,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      routine.focus,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileEmptySessions extends StatelessWidget {
  final ValueChanged<int>? onSelectTab;
  final VoidCallback onStartEmptyWorkout;
  final bool canStart;

  const _MobileEmptySessions({
    required this.onSelectTab,
    required this.onStartEmptyWorkout,
    required this.canStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              Icons.fitness_center_outlined,
              size: 36,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'No completed workouts yet',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your workout history, logs, and exercise summaries will appear here once you complete a session.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.secondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        if (canStart) ...[
          Center(
            child: PremiumButton(
              text: 'Start Empty Workout',
              icon: Icons.play_arrow,
              onTap: onStartEmptyWorkout,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Center(
          child: OutlinedButton.icon(
            onPressed: () => onSelectTab?.call(1),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Choose a Template'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onSurface,
              side: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The session's own name, falling back to the date when it was never named —
/// so the list reads "Push Day", not the same date twice over.
String _displayName(WorkoutSessionData session) {
  final name = session.name?.trim() ?? '';
  if (name.isNotEmpty) {
    return name;
  }
  return DateFormat('EEE, MMM d').format(session.startedAt);
}

class _SessionTile extends ConsumerWidget {
  final WorkoutSessionData session;
  final bool deleteMode;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final bool isGrid;

  const _SessionTile({
    required this.session,
    required this.deleteMode,
    required this.onLongPress,
    required this.onDelete,
    this.isGrid = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final duration = session.endedAt?.difference(session.startedAt);
    final durationStr = duration == null
        ? ''
        : duration.inHours > 0
        ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
        : '${duration.inMinutes}m';

    final sessionExercisesAsync = ref.watch(
      sessionExercisesProvider(session.id),
    );
    final catalogAsync = ref.watch(
      exerciseCatalogProvider(const ExerciseCatalogFilter()),
    );

    String? exerciseSummary;
    if (sessionExercisesAsync.asData?.value != null &&
        catalogAsync.asData?.value != null) {
      final rows = sessionExercisesAsync.asData!.value;
      final catalog = catalogAsync.asData!.value;
      final catalogMap = {for (final e in catalog) e.id: e.name};
      final names = rows
          .map((r) => catalogMap[r.exerciseId] ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.isNotEmpty) {
        if (names.length <= 3) {
          exerciseSummary = names.join(' • ');
        } else {
          exerciseSummary =
              '${names.take(3).join(' • ')} +${names.length - 3} more';
        }
      }
    }

    return Container(
      margin: EdgeInsets.only(bottom: isGrid ? 0 : 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deleteMode
              ? Colors.redAccent.withValues(alpha: 0.5)
              : AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: deleteMode
              ? onDelete
              : () => context.push(AppPaths.workoutHistory(session.id)),
          onLongPress: onLongPress,
          title: Text(
            _displayName(session),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [
                  DateFormat('EEE, MMM d').format(session.startedAt),
                  DateFormat('HH:mm').format(session.startedAt),
                  if (durationStr.isNotEmpty) durationStr,
                  if (session.sessionRpe != null) 'RPE ${session.sessionRpe}',
                ].join(' • '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              if (exerciseSummary != null && exerciseSummary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  exerciseSummary,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          trailing: IconButton(
            icon: Icon(
              deleteMode ? Icons.close : Icons.chevron_right,
              color: deleteMode ? Colors.redAccent : null,
            ),
            tooltip: deleteMode ? 'Delete workout' : null,
            onPressed: deleteMode
                ? onDelete
                : () => context.push(AppPaths.workoutHistory(session.id)),
          ),
        ),
      ),
    );
  }
}
