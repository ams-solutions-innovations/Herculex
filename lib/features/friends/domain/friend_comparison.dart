import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';

/// A person on the Gym Buddy page: a friend, or the user themself.
class FriendEntry {
  const FriendEntry({
    required this.userId,
    required this.displayName,
    this.avatarId,
    this.snapshot,
    this.isMe = false,
  });

  final String userId;
  final String displayName;
  final String? avatarId;

  /// Null when the friend has sharing off or has not published yet.
  final FriendSnapshot? snapshot;
  final bool isMe;
}

class LeaderboardRow {
  const LeaderboardRow({required this.entry, required this.lift});

  final FriendEntry entry;
  final FriendLift lift;
}

/// One workout done together, with each side's numbers when known.
class SharedSession {
  const SharedSession({
    required this.buddySessionId,
    required this.at,
    this.mine,
    this.theirs,
  });

  final String buddySessionId;
  final DateTime at;
  final FriendBuddySession? mine;
  final FriendBuddySession? theirs;
}

abstract final class FriendComparison {
  /// Everyone with a logged number on [lift], strongest first. Barbell lifts
  /// rank by e1RM in kg — what people compare at the gym — and fall back to
  /// the bodyweight ratio when a kg value is missing.
  static List<LeaderboardRow> leaderboard(
    StrengthLift lift,
    Iterable<FriendEntry> people,
  ) {
    final rows = [
      for (final p in people)
        if (p.snapshot?.liftOf(lift) case final l?)
          LeaderboardRow(entry: p, lift: l),
    ];
    double score(FriendLift l) => l.e1rmKg ?? l.value;
    rows.sort((a, b) {
      final byScore = score(b.lift).compareTo(score(a.lift));
      if (byScore != 0) return byScore;
      return a.entry.displayName.compareTo(b.entry.displayName);
    });
    return rows;
  }

  /// Lifts at least one person has a number for, in enum order.
  static List<StrengthLift> liftsWithData(Iterable<FriendEntry> people) => [
    for (final lift in StrengthLift.values)
      if (people.any((p) => p.snapshot?.liftOf(lift) != null)) lift,
  ];

  /// Joins both published snapshots on the buddy session id. [serverIds]
  /// are the sessions the server knows both people joined; it covers a
  /// friend whose snapshot is hidden. Newest first.
  static List<SharedSession> sharedSessions({
    required FriendSnapshot? mine,
    required FriendSnapshot? theirs,
    Map<String, DateTime> serverIds = const {},
  }) {
    final myById = {
      for (final s in mine?.buddySessions ?? const <FriendBuddySession>[])
        s.buddySessionId: s,
    };
    final theirById = {
      for (final s in theirs?.buddySessions ?? const <FriendBuddySession>[])
        s.buddySessionId: s,
    };
    // Only sessions both sides were in: the intersection of the snapshots,
    // plus anything the server vouches for.
    final ids = {
      ...myById.keys.where(theirById.containsKey),
      ...serverIds.keys,
    };
    final out = [
      for (final id in ids)
        SharedSession(
          buddySessionId: id,
          at: myById[id]?.at ?? theirById[id]?.at ?? serverIds[id]!,
          mine: myById[id],
          theirs: theirById[id],
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return out;
  }
}
