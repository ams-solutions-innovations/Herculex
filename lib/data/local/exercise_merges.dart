import 'exercise_merge.dart';

/// Catalog rows that were folded into another row by `tool/catalog_cleanup.py`.
///
/// The tool removes the loser from `assets/data/exercises.json`, which is
/// enough for a fresh install. Existing installs already have the row — and
/// possibly logged sets against it — and the importer never deletes, so
/// without this list the duplicate would sit in the picker forever with its
/// history stranded on it.
///
/// [ExerciseMergeEngine] repoints that history onto the winner, preserving the
/// equipment each set was actually performed with. It is idempotent: once the
/// loser is gone the merge reports itself skipped, so the list can stay here
/// permanently and re-run on any future migration.
///
/// Keep in step with `MERGES` in `tool/catalog_cleanup.py`.
const kExerciseMerges = <ExerciseMerge>[
  // Two spellings of the same exercise, both derived from the source
  // spreadsheet.
  ExerciseMerge(loser: 'lateral-raise-db', winner: 'dumbbell-lateral-raise'),
  ExerciseMerge(loser: 'l-sit-ring-pull-up', winner: 'ring-l-sit-pull-up'),
  ExerciseMerge(
    loser: 'seated-rotary-torso-machine',
    winner: 'rotary-torso-machine',
  ),

  // "Feet on floor" is what a ring push-up already is; only the elevated and
  // knee versions need qualifying.
  ExerciseMerge(
    loser: 'ring-push-up-feet-on-floor',
    winner: 'ring-push-up',
  ),

  // "Weighted" is a loading choice, not a different exercise. The winner
  // carries supportsWeightedBodyweight, so added load still has a home.
  ExerciseMerge(loser: 'russian-twist-weighted', winner: 'dumbbell-russian-twist'),
  ExerciseMerge(loser: 'weighted-side-bend', winner: 'dumbbell-side-bend'),
  ExerciseMerge(loser: 'weighted-dip', winner: 'chest-dips'),
];
