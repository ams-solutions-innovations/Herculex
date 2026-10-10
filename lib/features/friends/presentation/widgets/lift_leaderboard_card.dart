import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/friends/domain/friend_comparison.dart';
import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/presentation/level_band_style.dart';

/// "150 kg" for barbell lifts with a known e1RM, otherwise the standard's own
/// unit ("1.80× BW", "15 reps").
String formatFriendLift(FriendLift l, WeightFormat units) =>
    l.lift.measure == StrengthMeasure.bodyweightRatio && l.e1rmKg != null
    ? units.format(l.e1rmKg!, decimals: 0)
    : formatStrengthValue(l.lift, l.value);

/// Ranks the user and their friends on one main lift at a time.
class LiftLeaderboardCard extends ConsumerStatefulWidget {
  const LiftLeaderboardCard({super.key, required this.people});

  final List<FriendEntry> people;

  @override
  ConsumerState<LiftLeaderboardCard> createState() =>
      _LiftLeaderboardCardState();
}

class _LiftLeaderboardCardState extends ConsumerState<LiftLeaderboardCard> {
  StrengthLift? _picked;

  @override
  Widget build(BuildContext context) {
    final lifts = FriendComparison.liftsWithData(widget.people);
    if (lifts.isEmpty) return const SizedBox.shrink();
    final lift = lifts.contains(_picked) ? _picked! : lifts.first;
    final rows = FriendComparison.leaderboard(lift, widget.people);
    final units = ref.watch(weightFormatProvider);
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Main lifts',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: HxSpace.x3),
          HxPickerPill(
            caption: 'LIFT',
            label: lift.label,
            icon: Icons.fitness_center_rounded,
            onTap: () async {
              final next = await showHxPicker<StrengthLift>(
                context,
                title: 'Compare on',
                selected: lift,
                options: [
                  for (final l in lifts)
                    HxPickerOption(value: l, label: l.label),
                ],
              );
              if (next != null && mounted) setState(() => _picked = next);
            },
          ),
          const SizedBox(height: HxSpace.x3),
          for (final (i, row) in rows.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HxSpace.x1 + 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      i == 0 ? '🥇' : '#${i + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: hx.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.entry.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: row.entry.isMe
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: row.entry.isMe ? hx.primary : null,
                      ),
                    ),
                  ),
                  Text(
                    formatFriendLift(row.lift, units),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
