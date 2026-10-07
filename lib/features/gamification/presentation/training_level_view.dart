import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:intl/intl.dart';

class TrainingLevelView extends ConsumerStatefulWidget {
  const TrainingLevelView({super.key});

  @override
  ConsumerState<TrainingLevelView> createState() => _TrainingLevelViewState();
}

class _TrainingLevelViewState extends ConsumerState<TrainingLevelView> {
  int _selectedBandIndex = 0; // 0: All, 1: Novice, 2: Intermediate, 3: Advanced

  Color _bandColor(LevelBand band, BuildContext context) {
    switch (band) {
      case LevelBand.novice:
        return const Color(0xFF10B981); // Emerald
      case LevelBand.intermediate:
        return const Color(0xFF06B6D4); // Cyan
      case LevelBand.advanced:
        return const Color(0xFFF59E0B); // Amber / Gold
    }
  }

  String _bandLore(LevelBand band) {
    switch (band) {
      case LevelBand.novice:
        return 'Movement fundamentals, muscle activation & training habit formation.';
      case LevelBand.intermediate:
        return 'Progressive overload, high volume capacity & structural adaptation.';
      case LevelBand.advanced:
        return 'Near-maximal strength output, elite resilience & peak CNS conditioning.';
    }
  }

  IconData _bandIcon(LevelBand band) {
    switch (band) {
      case LevelBand.novice:
        return Icons.military_tech_rounded;
      case LevelBand.intermediate:
        return Icons.shield_rounded;
      case LevelBand.advanced:
        return Icons.diamond_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final progressAsync = ref.watch(levelProgressProvider);
    final entries = ref.watch(xpLedgerEntriesProvider);

    return progressAsync.when(
      loading: () => const HxScreenShell(
        title: 'Training Level',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (e, _) => HxScreenShell(
        title: 'Training Level',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(
                'Could not load training level: $e',
                style: TextStyle(color: hx.danger),
              ),
            ),
          ),
        ],
      ),
      data: (progress) {
        final currentLevel = progress.level;
        final nextLevel = progress.nextLevel;
        final currentBandColor = _bandColor(currentLevel.band, context);
        final percent = (progress.progressToNext * 100).toInt();

        final filteredLevels = switch (_selectedBandIndex) {
          1 => trainingLevels.where((l) => l.band == LevelBand.novice).toList(),
          2 =>
            trainingLevels
                .where((l) => l.band == LevelBand.intermediate)
                .toList(),
          3 =>
            trainingLevels.where((l) => l.band == LevelBand.advanced).toList(),
          _ => trainingLevels,
        };

        return HxScreenShell(
          title: 'Training Level',
          children: [
            const SizedBox(height: HxSpace.x2),

            // ── HERO LEVEL CARD ──────────────────────────────────────────────
            _buildHeroCard(
              theme: theme,
              hx: hx,
              progress: progress,
              currentLevel: currentLevel,
              nextLevel: nextLevel,
              bandColor: currentBandColor,
              percent: percent,
            ),

            const SizedBox(height: HxSpace.x5),

            // ── STATS SUMMARY GRID ───────────────────────────────────────────
            _buildStatsGrid(
              progress: progress,
              currentLevel: currentLevel,
              bandColor: currentBandColor,
            ),

            const SizedBox(height: HxSpace.x6),

            // ── PROGRESSION LADDER HEADER & TABS ──────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progression Ladder',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '15 Herculex training ranks across 3 tiers',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hx.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: HxSpace.x2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: currentBandColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: currentBandColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _bandIcon(currentLevel.band),
                        size: 14,
                        color: currentBandColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tier ${currentLevel.band.name.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: currentBandColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: HxSpace.x3),

            // Filter tabs
            HxTopTabs(
              labels: const ['All', 'Novice', 'Intermediate', 'Advanced'],
              index: _selectedBandIndex,
              onChanged: (i) {
                Haptics.selection();
                setState(() => _selectedBandIndex = i);
              },
            ),

            const SizedBox(height: HxSpace.x4),

            // Ladder List
            for (final level in filteredLevels) ...[
              _buildLadderTile(
                level: level,
                progress: progress,
                theme: theme,
                hx: hx,
              ),
              const SizedBox(height: HxSpace.x2),
            ],

            const SizedBox(height: HxSpace.x6),

            // ── HOW XP WORKS CARD ────────────────────────────────────────────
            _buildHowXpWorksCard(theme: theme, hx: hx),

            const SizedBox(height: HxSpace.x6),

            // ── RECENT XP ACTIVITY FEED ──────────────────────────────────────
            Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: hx.secondary),
                const SizedBox(width: 8),
                Text(
                  'Recent XP Activity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${entries.length} logged entries',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hx.secondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: HxSpace.x3),

            if (entries.isEmpty)
              HxCard(
                padding: const EdgeInsets.all(HxSpace.x5),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 36,
                        color: hx.secondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No XP entries recorded yet',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Complete a workout or sync your training history to start earning XP!',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hx.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final entry in entries.reversed.take(10)) ...[
                _buildActivityTile(entry: entry, theme: theme, hx: hx),
                const SizedBox(height: HxSpace.x2),
              ],

            const SizedBox(height: HxSpace.x8),
          ],
        );
      },
    );
  }

  Widget _buildHeroCard({
    required ThemeData theme,
    required dynamic hx,
    required LevelProgress progress,
    required TrainingLevel currentLevel,
    required TrainingLevel? nextLevel,
    required Color bandColor,
    required int percent,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bandColor.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.4),
          ],
        ),
        border: Border.all(
          color: bandColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: bandColor.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Glowing emblem container
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bandColor.withValues(alpha: 0.20),
                  border: Border.all(color: bandColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: bandColor.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    _bandIcon(currentLevel.band),
                    color: bandColor,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: bandColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'RANK ${currentLevel.number} OF 15',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: bandColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${progress.totalXp} XP',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: hx.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentLevel.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Text(
            _bandLore(currentLevel.band),
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.onSurfaceVariant,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20),

          // Progress Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                nextLevel == null
                    ? 'Maximum rank achieved'
                    : '${progress.xpIntoLevel} / ${progress.xpForNextLevel} XP to ${nextLevel.title}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: bandColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress.progressToNext,
              minHeight: 10,
              backgroundColor: hx.surfaceVariant.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(bandColor),
            ),
          ),

          if (progress.xpRemaining != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${progress.xpRemaining} XP remaining',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsGrid({
    required LevelProgress progress,
    required TrainingLevel currentLevel,
    required Color bandColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: HxStatTile(
            label: 'LOGGED WORKOUTS',
            value: '${progress.completedWorkouts}',
            icon: Icons.fitness_center_rounded,
            accent: AppColors.primary,
          ),
        ),
        const SizedBox(width: HxSpace.x3),
        Expanded(
          child: HxStatTile(
            label: 'TOTAL XP',
            value: '${progress.totalXp}',
            icon: Icons.bolt_rounded,
            accent: bandColor,
          ),
        ),
      ],
    );
  }

  Widget _buildLadderTile({
    required TrainingLevel level,
    required LevelProgress progress,
    required ThemeData theme,
    required dynamic hx,
  }) {
    final isCurrent = level.number == progress.level.number;
    final isCompleted = progress.totalXp >= level.xpAtLevel && !isCurrent;
    final isLocked = progress.totalXp < level.xpAtLevel;
    final bandColor = _bandColor(level.band, context);

    final borderColor = isCurrent
        ? bandColor
        : isCompleted
        ? bandColor.withValues(alpha: 0.3)
        : hx.surfaceVariant.withValues(alpha: 0.3);

    final bgColor = isCurrent
        ? bandColor.withValues(alpha: 0.12)
        : isCompleted
        ? hx.surfaceVariant.withValues(alpha: 0.15)
        : hx.surfaceVariant.withValues(alpha: 0.05);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isCurrent ? 1.8 : 1.0),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: bandColor.withValues(alpha: 0.2),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Rank number or status icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? bandColor
                  : isCompleted
                  ? bandColor.withValues(alpha: 0.2)
                  : hx.surfaceVariant.withValues(alpha: 0.3),
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check_rounded, size: 20, color: bandColor)
                  : isCurrent
                  ? const Icon(
                      Icons.star_rounded,
                      size: 22,
                      color: Colors.black,
                    )
                  : Text(
                      '${level.number}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: hx.secondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      level.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: isCurrent
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isLocked ? hx.secondary : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: bandColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${level.xpAtLevel} XP required',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hx.secondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (isLocked)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: hx.secondary),
                const SizedBox(width: 4),
                Text(
                  '+${level.xpAtLevel - progress.totalXp} XP',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hx.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else if (isCompleted)
            Icon(
              Icons.verified_rounded,
              size: 18,
              color: bandColor.withValues(alpha: 0.8),
            )
          else if (isCurrent)
            Text(
              '${(progress.progressToNext * 100).toInt()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: bandColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHowXpWorksCard({required ThemeData theme, required dynamic hx}) {
    return HxCard(
      padding: const EdgeInsets.all(20),
      radius: HxRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'How Training XP is Earned',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRuleRow(
            icon: Icons.check_circle_outline_rounded,
            title: 'Workout Completed',
            points: '+40 XP',
            subtitle: 'Awarded for every completed workout session.',
            theme: theme,
            hx: hx,
          ),
          const SizedBox(height: 12),
          _buildRuleRow(
            icon: Icons.fitness_center_rounded,
            title: 'Working Sets Volume',
            points: 'Up to +20 XP',
            subtitle: '+2 XP for every completed working set.',
            theme: theme,
            hx: hx,
          ),
          const SizedBox(height: 12),
          _buildRuleRow(
            icon: Icons.trending_up_rounded,
            title: 'Relative Strength Milestone',
            points: '+10 to +15 XP',
            subtitle: 'Logged load exceeding 1.0× or 1.5× bodyweight.',
            theme: theme,
            hx: hx,
          ),
          const SizedBox(height: 12),
          _buildRuleRow(
            icon: Icons.repeat_rounded,
            title: 'Consistency Reward',
            points: '+10 XP',
            subtitle: 'Training again between 20 and 96 hours.',
            theme: theme,
            hx: hx,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hx.surfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: hx.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Deterministic & transparent — XP reflects logged training only, never arbitrary streaks or paywalls.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.secondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleRow({
    required IconData icon,
    required String title,
    required String points,
    required String subtitle,
    required ThemeData theme,
    required dynamic hx,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    points,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hx.secondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityTile({
    required XpLedgerEntry entry,
    required ThemeData theme,
    required dynamic hx,
  }) {
    final dateStr = DateFormat.MMMd().add_jm().format(entry.awardedAt);

    return HxCard(
      padding: const EdgeInsets.all(14),
      radius: HxRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.fitness_center_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Training Session',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+${entry.xp} XP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dateStr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.secondary,
              fontSize: 11,
            ),
          ),
          if (entry.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final reason in entry.reasons)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: hx.surfaceVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 10,
                        color: hx.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
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
}
