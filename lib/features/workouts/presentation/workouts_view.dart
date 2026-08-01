import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../widgets/premium_button.dart';
import '../../gyms/presentation/gym_picker_sheet.dart';
import 'active_workout_view.dart';
import 'templates_view.dart';
import 'workouts_providers.dart';

class WorkoutsView extends ConsumerWidget {
  const WorkoutsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider);
    return active.when(
      data: (session) => session != null
          ? ActiveWorkoutView(session: session)
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

class _WorkoutsLandingState extends ConsumerState<_WorkoutsLanding>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Workout', style: theme.textTheme.displayMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Log sets, supersets, and RPE. Rest timer starts when you check a set.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Center(
                  child: PremiumButton(
                    text: 'Start Empty Workout',
                    icon: Icons.play_arrow,
                    onTap: () async {
                      // Multi-gym (§10): pick the gym when more than one exists.
                      final gym = await GymPickerSheet.resolve(context, ref);
                      if (gym.cancelled) return;
                      await ref
                          .read(workoutsRepositoryProvider)
                          .startSession(gymId: gym.gymId);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                TabBar(
                  controller: _tabs,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.onSurfaceVariant,
                  indicatorColor: AppColors.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Recent'),
                    Tab(text: 'Templates'),
                  ],
                ),
                const Divider(height: 1),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _RecentTab(),
                const TemplatesView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTab extends ConsumerStatefulWidget {
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _deleteMode ? () => setState(() => _deleteMode = false) : null,
      child: recent.when(
        data: (sessions) => sessions.isEmpty
            ? Center(
                child: Text(
                  'No completed workouts yet',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.secondary),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
                itemCount: sessions.length,
                itemBuilder: (_, i) => _SessionTile(
                  session: sessions[i],
                  deleteMode: _deleteMode,
                  onLongPress: () => setState(() => _deleteMode = true),
                  onDelete: () => _confirmDelete(sessions[i]),
                ),
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
            'This permanently deletes "$label" and every set logged in it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(workoutsRepositoryProvider).deleteSession(session.id);
    if (mounted) setState(() => _deleteMode = false);
  }
}

/// The session's own name, falling back to the date when it was never named —
/// so the list reads "Push Day", not the same date twice over.
String _displayName(WorkoutSessionData session) {
  final name = session.name?.trim() ?? '';
  if (name.isNotEmpty) return name;
  return DateFormat('EEE, MMM d').format(session.startedAt);
}

class _SessionTile extends ConsumerWidget {
  final WorkoutSessionData session;
  final bool deleteMode;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.deleteMode,
    required this.onLongPress,
    required this.onDelete,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: deleteMode
              ? Colors.redAccent.withValues(alpha: 0.5)
              : AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        onTap: deleteMode
            ? onDelete
            : () => context.push('/workout-history/${session.id}'),
        onLongPress: onLongPress,
        title: Text(_displayName(session),
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(
          [
            DateFormat('EEE, MMM d').format(session.startedAt),
            DateFormat('HH:mm').format(session.startedAt),
            if (durationStr.isNotEmpty) durationStr,
            if (session.sessionRpe != null) 'RPE ${session.sessionRpe}',
          ].join(' • '),
        ),
        trailing: IconButton(
          icon: Icon(deleteMode ? Icons.close : Icons.chevron_right,
              color: deleteMode ? Colors.redAccent : null),
          tooltip: deleteMode ? 'Delete workout' : null,
          onPressed: deleteMode
              ? onDelete
              : () => context.push('/workout-history/${session.id}'),
        ),
      ),
    );
  }
}
