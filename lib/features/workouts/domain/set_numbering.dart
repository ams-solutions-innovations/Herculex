import 'package:herculex/data/local/database.dart';

/// How one set is numbered for display.
///
/// Warmups are not working sets, so they never take a number: two warmups
/// followed by three working sets read `W1 W2 1 2 3`, not `W W 3 4 5`.
class SetNumber {
  /// Whether this set is a warmup.
  final bool isWarmup;

  /// 1-based position among the warmups (for a warmup) or among the working
  /// sets (for everything else).
  final int ordinal;

  /// How many sets of the same kind ([isWarmup]) the exercise has.
  final int ofKind;

  const SetNumber({
    required this.isWarmup,
    required this.ordinal,
    required this.ofKind,
  });

  /// Compact label: `W1`, `W2` for warmups, `1`, `2` for working sets.
  String get short => isWarmup ? 'W$ordinal' : '$ordinal';

  /// Label with the working total: `1/3` for working sets. Warmups stay
  /// `W1` — "warmup 1 of 2" is noise next to the working-set count.
  String get withTotal => isWarmup ? short : '$ordinal/$ofKind';
}

/// Numbers [sets] (in display order) so working sets count from 1 regardless
/// of how many warmups precede them. Returns one entry per input set.
List<SetNumber> numberSets(List<SetEntryData> sets) =>
    numberSetFlags([for (final s in sets) s.isWarmup]);

/// [numberSets] over bare warmup flags, for callers that hold a different
/// set type (wire payloads, planned sets).
List<SetNumber> numberSetFlags(List<bool> isWarmup) {
  final warmupTotal = isWarmup.where((w) => w).length;
  final workingTotal = isWarmup.length - warmupTotal;
  var warmupSeen = 0;
  var workingSeen = 0;
  return [
    for (final warm in isWarmup)
      warm
          ? SetNumber(
              isWarmup: true,
              ordinal: ++warmupSeen,
              ofKind: warmupTotal,
            )
          : SetNumber(
              isWarmup: false,
              ordinal: ++workingSeen,
              ofKind: workingTotal,
            ),
  ];
}
