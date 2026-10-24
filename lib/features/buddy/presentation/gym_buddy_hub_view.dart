import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/buddy/application/buddy_social_providers.dart';
import 'package:herculex/features/buddy/data/buddy_social_repository.dart';
import 'package:herculex/features/buddy/domain/gym_buddy_social.dart';
import 'package:herculex/features/buddy/presentation/buddy_share_sheet.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_badge.dart';
import 'package:herculex/features/workouts/presentation/sheets/exercise_picker_sheet.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';
import 'package:qr_flutter/qr_flutter.dart';

class GymBuddyHubView extends ConsumerStatefulWidget {
  const GymBuddyHubView({super.key});

  @override
  ConsumerState<GymBuddyHubView> createState() => _GymBuddyHubViewState();
}

class _GymBuddyHubViewState extends ConsumerState<GymBuddyHubView> {
  int _selectedTabIndex = 0;
  String _selectedExerciseKey = 'bench';

  String? _getExerciseSlug(ComparisonExercise ex) {
    if (ex.slug != null && ex.slug!.isNotEmpty) return ex.slug;
    final key = ex.key.toLowerCase();
    final label = ex.label.toLowerCase();
    if (key == 'bench' || label.contains('bench press')) {
      return 'barbell-bench-press';
    }
    if (key == 'squat' || label.contains('squat')) {
      return 'barbell-back-squat';
    }
    if (key == 'deadlift' || label.contains('deadlift')) {
      return 'conventional-deadlift';
    }
    if (key == 'ohp' ||
        label.contains('overhead') ||
        label.contains('military')) {
      return 'overhead-press';
    }
    if (key == 'pullup' ||
        label.contains('pull-up') ||
        label.contains('pullup') ||
        label.contains('chin-up')) {
      return 'pull-up';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final buddies = ref.watch(allBuddiesWithUserProvider);
    final prFeed = ref.watch(buddyPrFeedProvider).valueOrNull ?? const [];
    final repo = ref.watch(buddySocialRepositoryProvider);
    final compExercises =
        ref.watch(comparisonExercisesProvider).valueOrNull ??
        BuddySocialRepository.defaultComparisonExercises;
    final hx = context.hx;

    return HxScreenShell(
      title: 'Gym Buddy',
      titleIcon: Icons.group_rounded,
      actions: [
        IconButton(
          icon: const Icon(Icons.person_add_outlined),
          tooltip: 'Add Gym Buddy',
          onPressed: () => _showAddBuddySheet(context, repo),
        ),
      ],
      children: [
        HxTopTabs(
          labels: const ['Comparison', 'Friends', 'PR Activity'],
          index: _selectedTabIndex,
          onChanged: (idx) => setState(() => _selectedTabIndex = idx),
          accent: hx.domainTraining,
        ),
        const SizedBox(height: HxSpace.x4),
        if (_selectedTabIndex == 0) ...[
          _buildGoalProgressSection(context, buddies),
          const SizedBox(height: HxSpace.x6),
          _buildLiftsLeaderboardSection(context, buddies, compExercises, repo),
          const SizedBox(height: HxSpace.x6),
          _buildBigThreeTotalSection(context, buddies),
        ] else if (_selectedTabIndex == 1) ...[
          _buildInviteCodeCard(context, repo.myInviteCode, repo),
          const SizedBox(height: HxSpace.x4),
          _buildFriendsListSection(context, buddies),
        ] else ...[
          _buildPrFeedHeader(context),
          const SizedBox(height: HxSpace.x4),
          _buildPrFeedSection(context, prFeed),
        ],
      ],
    );
  }

  // ── Tab 0: Comparison (Goal Progress & Lifts) ───────────────────────────────

  Widget _buildGoalProgressSection(
    BuildContext context,
    List<GymBuddyProfile> buddies,
  ) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final weightFmt = ref.watch(weightFormatProvider);

    // Sort buddies by goal progress percent descending
    final sortedByProgress = List<GymBuddyProfile>.from(buddies)
      ..sort((a, b) => b.goalProgressPercent.compareTo(a.goalProgressPercent));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'GOAL PROGRESS',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              'Dream Physique',
              style: theme.textTheme.labelSmall?.copyWith(
                color: hx.domainTraining,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x2),
        HxCard(
          accent: hx.domainTraining,
          child: Column(
            children: [
              for (var i = 0; i < sortedByProgress.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                _buildGoalProgressRow(context, sortedByProgress[i], weightFmt),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoalProgressRow(
    BuildContext context,
    GymBuddyProfile profile,
    WeightFormat weightFmt,
  ) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final percent = (profile.goalProgressPercent * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GreekAvatarBadge(
              avatarId: profile.avatarId,
              name: profile.name,
              size: 38,
            ),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (profile.isUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: hx.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'YOU',
                            style: TextStyle(
                              color: hx.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    profile.goalPhase,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$percent%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hx.domainTraining,
                  ),
                ),
                if (profile.currentWeightKg != null &&
                    profile.targetWeightKg != null)
                  Text(
                    '${weightFmt.format(profile.currentWeightKg!, decimals: 1)} → ${weightFmt.format(profile.targetWeightKg!, decimals: 1)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: profile.goalProgressPercent.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              profile.isUser ? hx.primary : hx.domainTraining,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiftsLeaderboardSection(
    BuildContext context,
    List<GymBuddyProfile> buddies,
    List<ComparisonExercise> compExercises,
    dynamic repo,
  ) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final user = buddies.firstWhere(
      (b) => b.isUser,
      orElse: () => buddies.first,
    );

    final currentExercise = compExercises.firstWhere(
      (e) => e.key == _selectedExerciseKey,
      orElse: () => compExercises.first,
    );

    final key = currentExercise.key;
    final sorted = List<GymBuddyProfile>.from(buddies)
      ..sort((a, b) {
        final valA = a.benchmarkLifts[key] ?? 0.0;
        final valB = b.benchmarkLifts[key] ?? 0.0;
        return valB.compareTo(valA);
      });

    final userVal = user.benchmarkLifts[key] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LIFTS COMPARISON (EST. 1RM)',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton.icon(
              onPressed: () => _showAddCustomExerciseSheet(context, repo),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Exercise', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x2),
        // Lift Selector Button that opens a bottom sheet
        GestureDetector(
          onTap: () => _showLiftPickerSheet(context, compExercises, repo),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: hx.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hx.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                ExerciseArtwork.fromSlug(
                  slug: _getExerciseSlug(currentExercise),
                  size: 44,
                  radius: 10,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECTED EXERCISE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        currentExercise.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: hx.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hx.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: hx.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: HxSpace.x3),
        HxCard(
          accent: hx.domainTraining,
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                _buildLeaderboardRow(
                  context,
                  rank: i + 1,
                  profile: sorted[i],
                  liftValue: sorted[i].benchmarkLifts[key] ?? 0.0,
                  userValue: userVal,
                  unit: currentExercise.unit,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardRow(
    BuildContext context, {
    required int rank,
    required GymBuddyProfile profile,
    required double liftValue,
    required double userValue,
    required String unit,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;

    Widget rankBadge;
    if (rank == 1) {
      rankBadge = const Text('🥇', style: TextStyle(fontSize: 20));
    } else if (rank == 2) {
      rankBadge = const Text('🥈', style: TextStyle(fontSize: 20));
    } else if (rank == 3) {
      rankBadge = const Text('🥉', style: TextStyle(fontSize: 20));
    } else {
      rankBadge = Text(
        '#$rank',
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      );
    }

    final delta = liftValue - userValue;
    String deltaText = '';
    Color deltaColor = theme.colorScheme.onSurfaceVariant;
    if (profile.isUser) {
      deltaText = 'Your personal record';
      deltaColor = hx.primary;
    } else if (delta > 0) {
      deltaText = '+${delta.toStringAsFixed(1)} $unit ahead of you';
      deltaColor = hx.warning;
    } else if (delta < 0) {
      deltaText = '${delta.abs().toStringAsFixed(1)} $unit behind you';
      deltaColor = hx.domainRecovery;
    } else {
      deltaText = 'Tied with you';
    }

    return Row(
      children: [
        SizedBox(width: 30, child: Center(child: rankBadge)),
        const SizedBox(width: 8),
        GreekAvatarBadge(
          avatarId: profile.avatarId,
          name: profile.name,
          size: 36,
        ),
        const SizedBox(width: HxSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (profile.isUser) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: hx.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'YOU',
                        style: TextStyle(
                          color: hx.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                deltaText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: deltaColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${liftValue.toStringAsFixed(unit == 'reps' ? 0 : 1)} $unit',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: profile.isUser ? hx.primary : null,
              ),
            ),
            Text(
              profile.levelTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBigThreeTotalSection(
    BuildContext context,
    List<GymBuddyProfile> buddies,
  ) {
    final theme = Theme.of(context);
    final hx = context.hx;

    double computeTotal(GymBuddyProfile p) {
      final b = p.benchmarkLifts['bench'] ?? 0.0;
      final s = p.benchmarkLifts['squat'] ?? 0.0;
      final d = p.benchmarkLifts['deadlift'] ?? 0.0;
      return b + s + d;
    }

    final sorted = List<GymBuddyProfile>.from(buddies)
      ..sort((a, b) => computeTotal(b).compareTo(computeTotal(a)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BIG 3 TOTAL (BENCH + SQUAT + DEADLIFT)',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        HxCard(
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                Row(
                  children: [
                    Text(
                      '#${i + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GreekAvatarBadge(
                      avatarId: sorted[i].avatarId,
                      name: sorted[i].name,
                      size: 30,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sorted[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${computeTotal(sorted[i]).toStringAsFixed(1)} kg',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: sorted[i].isUser
                            ? hx.primary
                            : hx.domainTraining,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 1: Friends ──────────────────────────────────────────────────────────

  Widget _buildInviteCodeCard(BuildContext context, String code, dynamic repo) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxCard(
      accent: hx.primary,
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: hx.primary, size: 28),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Gym Buddy Code',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Partners can add you using this code or QR',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: hx.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  code,
                  style: TextStyle(
                    color: hx.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 38),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    AppNotice.showWith(
                      ref,
                      'Code $code copied to clipboard',
                      title: 'Ready to share',
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text(
                    'Copy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 38),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => _showAddBuddySheet(context, repo),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                  label: const Text(
                    'Scan QR',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsListSection(
    BuildContext context,
    List<GymBuddyProfile> buddies,
  ) {
    final theme = Theme.of(context);
    final friends = buddies.where((b) => !b.isUser).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MY WORKOUT BUDDIES (${friends.length})',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x2),
        for (final friend in friends) ...[
          _buildFriendTile(context, friend),
          const SizedBox(height: HxSpace.x3),
        ],
      ],
    );
  }

  Widget _buildFriendTile(BuildContext context, GymBuddyProfile friend) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxCard(
      child: Column(
        children: [
          Row(
            children: [
              GreekAvatarBadge(
                avatarId: friend.avatarId,
                name: friend.name,
                size: 48,
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${friend.levelTitle} · Last workout: ${friend.lastWorkout}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 38),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => _showFriendStatsSheet(context, friend),
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: const Text(
                    'Stats',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: hx.domainTraining,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 38),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => BuddyShareSheet.show(context),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text(
                    'Train',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 2: PR Activity Feed ─────────────────────────────────────────────────

  Widget _buildPrFeedHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'RECENT PR ACHIEVEMENTS',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton.icon(
          onPressed: () => _showPostPrSheet(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Share PR'),
        ),
      ],
    );
  }

  Widget _buildPrFeedSection(
    BuildContext context,
    List<BuddyPrActivity> prFeed,
  ) {
    if (prFeed.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No PR achievements posted by buddies yet.'),
        ),
      );
    }

    return Column(
      children: [
        for (final item in prFeed) ...[
          _buildPrCard(context, item),
          const SizedBox(height: HxSpace.x3),
        ],
      ],
    );
  }

  Widget _buildPrCard(BuildContext context, BuddyPrActivity item) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final repo = ref.watch(buddySocialRepositoryProvider);

    return HxCard(
      accent: hx.domainTraining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GreekAvatarBadge(
                avatarId: item.buddyAvatarId,
                name: item.buddyName,
                size: 38,
              ),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.buddyName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatDate(item.achievedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFFFD54F),
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hx.surfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.exerciseName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.improvementKg != null)
                        Text(
                          '+${item.improvementKg!.toStringAsFixed(1)} kg personal record!',
                          style: TextStyle(
                            color: hx.domainRecovery,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${item.weightKg.toStringAsFixed(1)} kg',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hx.domainTraining,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HxSpace.x3),
          // Reactions Row
          Row(
            children: [
              for (final emoji in ['🔥', '💪', '👏'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      Haptics.light();
                      await repo.toggleReaction(item.id, emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: hx.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (item.reactions[emoji] ?? 0) > 0
                              ? hx.primary.withValues(alpha: 0.3)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Text(
                            '${item.reactions[emoji] ?? 0}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  // ── Bottom Sheet Pickers & Modals ──────────────────────────────────────────

  /// Modal bottom sheet to pick benchmark lift (Bench, Squat, custom, etc.)
  void _showLiftPickerSheet(
    BuildContext context,
    List<ComparisonExercise> exercises,
    BuddySocialRepository repo,
  ) {
    final theme = Theme.of(context);
    final hx = context.hx;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Benchmark Lift',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddCustomExerciseSheet(context, repo);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Exercise'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: exercises.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final ex = exercises[i];
                    final isSelected = _selectedExerciseKey == ex.key;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor: isSelected
                          ? hx.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      leading: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected
                              ? Border.all(color: hx.primary, width: 2)
                              : Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.2),
                                  width: 1,
                                ),
                        ),
                        child: ExerciseArtwork.fromSlug(
                          slug: _getExerciseSlug(ex),
                          size: 44,
                          radius: 8,
                          fallbackColor: isSelected
                              ? hx.primary.withValues(alpha: 0.2)
                              : null,
                        ),
                      ),
                      title: Text(
                        ex.label,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        'Measured in ${ex.unit}${ex.isCustom ? ' · Custom' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ex.isCustom)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              color: hx.danger,
                              tooltip: 'Delete custom exercise',
                              onPressed: () async {
                                await repo.removeComparisonExercise(ex.key);
                                if (_selectedExerciseKey == ex.key) {
                                  setState(
                                    () => _selectedExerciseKey = 'bench',
                                  );
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                            ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded, color: hx.primary),
                        ],
                      ),
                      onTap: () {
                        Haptics.selection();
                        setState(() => _selectedExerciseKey = ex.key);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAddCustomExerciseSheet(context, repo);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('+ Add New Exercise to Compare'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add custom exercise sheet with exercise library picker or manual name
  void _showAddCustomExerciseSheet(
    BuildContext context,
    BuddySocialRepository repo,
  ) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final nameCtrl = TextEditingController();
    final prCtrl = TextEditingController(text: '80.0');
    var unit = 'kg';
    String? pickedSlug;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.fitness_center_rounded,
                      color: hx.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Add Exercise to Compare',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose an exercise from the catalog or type a custom one to compare with your friends.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                // Pick from exercise library button
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                  ),
                  onPressed: () async {
                    final picks = await ExercisePickerSheet.show(context);
                    if (picks != null && picks.isNotEmpty) {
                      final chosen = picks.first.exercise;
                      nameCtrl.text = chosen.name;
                      setSheetState(() {
                        pickedSlug = chosen.slug;
                        if (chosen.loggingMetric == 'reps') {
                          unit = 'reps';
                          prCtrl.text = '15';
                        } else {
                          unit = 'kg';
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('Pick from Exercise Library'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Exercise Name',
                    hintText: 'e.g. Incline Dumbbell Press',
                    prefixIcon: pickedSlug != null
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: ExerciseArtwork.fromSlug(
                              slug: pickedSlug,
                              size: 28,
                              radius: 6,
                            ),
                          )
                        : const Icon(Icons.edit_note_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: prCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Your 1RM / Record ($unit)',
                          prefixIcon: const Icon(Icons.scale_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'kg', label: Text('kg')),
                        ButtonSegment(value: 'reps', label: Text('reps')),
                      ],
                      selected: {unit},
                      onSelectionChanged: (val) {
                        setSheetState(() => unit = val.first);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: hx.domainTraining,
                  ),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      AppNotice.showWith(
                        ref,
                        'Please enter an exercise name',
                        title: 'Missing Name',
                        kind: AppNoticeKind.error,
                      );
                      return;
                    }
                    final record = double.tryParse(prCtrl.text.trim()) ?? 75.0;
                    final key =
                        'custom_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

                    final newExercise = ComparisonExercise(
                      key: key,
                      label: name,
                      unit: unit,
                      isCustom: true,
                      slug: pickedSlug,
                    );

                    await repo.addComparisonExercise(
                      newExercise,
                      userValue: record,
                    );

                    setState(() => _selectedExerciseKey = key);

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      AppNotice.showWith(
                        ref,
                        '$name has been added to lifts comparison!',
                        title: 'Exercise Added',
                      );
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Add to Comparison'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Add Buddy bottom sheet offering QR scan, enter code, and share QR
  void _showAddBuddySheet(BuildContext context, dynamic repo) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.person_add_rounded, color: hx.primary, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Add Workout Buddy',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Option 1: Scan Partner's QR
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: hx.domainTraining,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(AppRoutes.buddyJoin);
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan Partner QR Code'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR ENTER CODE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. HERC-8921',
                  prefixIcon: const Icon(Icons.tag_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste_rounded),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        ctrl.text = data!.text!.trim().toUpperCase();
                      }
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () async {
                  final code = ctrl.text.trim().toUpperCase();
                  if (code.isNotEmpty) {
                    final newBuddy = GymBuddyProfile(
                      id: 'buddy_${DateTime.now().millisecondsSinceEpoch}',
                      name: 'Buddy $code',
                      avatarId: 'hercules',
                      levelTitle: 'Spartan II',
                      levelNumber: 2,
                      goalPhase: 'Maintenance',
                      currentWeightKg: 82.0,
                      targetWeightKg: 80.0,
                      goalProgressPercent: 0.70,
                      benchmarkLifts: {
                        'bench': 105.0,
                        'squat': 145.0,
                        'deadlift': 185.0,
                        'ohp': 65.0,
                        'pullup': 12.0,
                      },
                      lastWorkout: 'Just now',
                      inviteCode: code,
                    );
                    await repo.addBuddy(newBuddy);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      AppNotice.showWith(
                        ref,
                        'Partner $code was added successfully!',
                        title: 'Gym Buddy Connected',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Connect via Code'),
              ),
              const SizedBox(height: 20),
              // Option 3: Partner can scan your QR
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: hx.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: hx.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Your QR Code',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Have your partner scan this on their phone:',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: 'herculex:buddy:${repo.myInviteCode}',
                        version: QrVersions.auto,
                        size: 150,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      repo.myInviteCode,
                      style: TextStyle(
                        color: hx.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        fontSize: 16,
                      ),
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

  /// Post PR bottom sheet with full overflow protection
  void _showPostPrSheet(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final user = ref.read(userGymBuddyProfileProvider);
    final repo = ref.read(buddySocialRepositoryProvider);

    final exCtrl = TextEditingController(text: 'Barbell Bench Press');
    final wtCtrl = TextEditingController(text: '105.0');
    final impCtrl = TextEditingController(text: '5.0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFFFFD54F),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Share Personal Record',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: exCtrl,
                decoration: InputDecoration(
                  labelText: 'Exercise Name',
                  prefixIcon: const Icon(Icons.fitness_center_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Weight (kg)',
                        prefixIcon: const Icon(Icons.scale_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: impCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Gain (+ kg)',
                        prefixIcon: const Icon(Icons.trending_up_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: hx.domainTraining,
                ),
                onPressed: () async {
                  final wt = double.tryParse(wtCtrl.text.trim()) ?? 100.0;
                  final imp = double.tryParse(impCtrl.text.trim()) ?? 2.5;
                  final act = BuddyPrActivity(
                    id: 'pr_${DateTime.now().millisecondsSinceEpoch}',
                    buddyId: user.id,
                    buddyName: user.name,
                    buddyAvatarId: user.avatarId,
                    exerciseName: exCtrl.text.trim(),
                    weightKg: wt,
                    improvementKg: imp,
                    achievedAt: DateTime.now(),
                  );
                  await repo.addPrActivity(act);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    AppNotice.showWith(
                      ref,
                      'Your new PR has been shared with your buddies!',
                      title: 'PR Broadcasted',
                    );
                  }
                },
                icon: const Icon(Icons.send_rounded),
                label: const Text('Publish Record'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFriendStatsSheet(BuildContext context, GymBuddyProfile friend) {
    final theme = Theme.of(context);
    final weightFmt = ref.read(weightFormatProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                GreekAvatarBadge(
                  avatarId: friend.avatarId,
                  name: friend.name,
                  size: 54,
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${friend.levelTitle} · ${friend.goalPhase}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'BENCHMARK LIFTS RECORD',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final entry in friend.benchmarkLifts.entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.key.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      entry.key == 'pullup'
                          ? '${entry.value.toInt()} reps'
                          : weightFmt.format(entry.value),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: ctx.hx.domainTraining,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  BuddyShareSheet.show(context);
                },
                icon: const Icon(Icons.fitness_center_rounded),
                label: const Text('Start Shared Workout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
