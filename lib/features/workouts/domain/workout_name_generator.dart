import '../../../data/local/database.dart';
import '../../../data/local/exercise_biomechanics.dart';

enum MuscleTargetGroup {
  chest,
  back,
  frontSideDelts,
  rearDelts,
  biceps,
  triceps,
  forearms,
  quads,
  hamstrings,
  glutes,
  calves,
  core,
  neck,
  cardio,
  mobility,
  other,
}

/// Automatically composes an intelligent, human-friendly workout name based on
/// the exercises and muscle groups trained in a workout session.
/// Supports a comprehensive set of splits and combinations (e.g. "Arm Day",
/// "Leg Day", "Push Day", "Pull Day", "Shoulders & Triceps", "Arms & Abs",
/// "Chest & Abs", "Legs & Abs", "Push & Abs", "Shoulders & Arms", etc.).
class WorkoutNameGenerator {
  const WorkoutNameGenerator._();

  static MuscleTargetGroup classifyMuscle(
    String muscle, {
    String? force,
    String? movementPattern,
    String? exerciseName,
    String? category,
  }) {
    final cat = category?.toLowerCase() ?? '';
    if (cat == 'cardio') return MuscleTargetGroup.cardio;
    if (cat == 'mobility') return MuscleTargetGroup.mobility;

    final coarse = ExerciseBiomechanics.coarseMuscle(muscle).toLowerCase();
    final lowerMuscle = muscle.toLowerCase();
    final lowerName = exerciseName?.toLowerCase() ?? '';
    final lowerForce = force?.toLowerCase() ?? '';

    if (lowerMuscle.contains('rear delt') ||
        lowerName.contains('rear delt') ||
        lowerName.contains('face pull') ||
        lowerName.contains('reverse fly') ||
        (coarse == 'shoulders' && lowerForce == 'pull')) {
      return MuscleTargetGroup.rearDelts;
    }

    switch (coarse) {
      case 'chest':
        return MuscleTargetGroup.chest;
      case 'back':
        return MuscleTargetGroup.back;
      case 'shoulders':
        return MuscleTargetGroup.frontSideDelts;
      case 'biceps':
        return MuscleTargetGroup.biceps;
      case 'triceps':
        return MuscleTargetGroup.triceps;
      case 'forearms':
        return MuscleTargetGroup.forearms;
      case 'quads':
        return MuscleTargetGroup.quads;
      case 'hamstrings':
        return MuscleTargetGroup.hamstrings;
      case 'glutes':
        return MuscleTargetGroup.glutes;
      case 'calves':
        return MuscleTargetGroup.calves;
      case 'abs':
      case 'core':
        return MuscleTargetGroup.core;
      case 'neck':
        return MuscleTargetGroup.neck;
      default:
        if (lowerMuscle.contains('adductor') ||
            lowerMuscle.contains('abductor') ||
            lowerMuscle.contains('leg')) {
          return MuscleTargetGroup.quads;
        }
        return MuscleTargetGroup.other;
    }
  }

  static String generate(List<ExerciseCatalogData> exercises) {
    if (exercises.isEmpty) return 'Quick Workout';

    // 1. Tally muscle groups
    final muscleCounts = <MuscleTargetGroup, int>{};
    for (final ex in exercises) {
      final target = classifyMuscle(
        ex.primaryMuscle,
        force: ex.force,
        movementPattern: ex.movementPattern,
        exerciseName: ex.name,
        category: ex.category,
      );
      muscleCounts[target] = (muscleCounts[target] ?? 0) + 1;
    }

    final cardio = muscleCounts[MuscleTargetGroup.cardio] ?? 0;
    final mobility = muscleCounts[MuscleTargetGroup.mobility] ?? 0;
    final chest = muscleCounts[MuscleTargetGroup.chest] ?? 0;
    final back = muscleCounts[MuscleTargetGroup.back] ?? 0;
    final frontSideDelts = muscleCounts[MuscleTargetGroup.frontSideDelts] ?? 0;
    final rearDelts = muscleCounts[MuscleTargetGroup.rearDelts] ?? 0;
    final allShoulders = frontSideDelts + rearDelts;

    final biceps = muscleCounts[MuscleTargetGroup.biceps] ?? 0;
    final triceps = muscleCounts[MuscleTargetGroup.triceps] ?? 0;
    final forearms = muscleCounts[MuscleTargetGroup.forearms] ?? 0;
    final quads = muscleCounts[MuscleTargetGroup.quads] ?? 0;
    final hamstrings = muscleCounts[MuscleTargetGroup.hamstrings] ?? 0;
    final glutes = muscleCounts[MuscleTargetGroup.glutes] ?? 0;
    final calves = muscleCounts[MuscleTargetGroup.calves] ?? 0;
    final core = muscleCounts[MuscleTargetGroup.core] ?? 0;

    final legs = quads + hamstrings + glutes + calves;
    final arms = biceps + triceps + forearms;
    final push = chest + frontSideDelts + triceps;
    final pull = back + biceps + rearDelts + forearms;
    final upper = chest + back + allShoulders + arms;
    final total = exercises.length;

    final hasAbs = core > 0;

    // 2. Pure Cardio / Mobility
    if (cardio == total) return 'Cardio';
    if (mobility == total) return 'Mobility';
    if (cardio > 0 && upper == 0 && legs == 0 && hasAbs) {
      return 'Cardio & Abs';
    }
    if (cardio > 0 && arms > 0 && chest == 0 && back == 0 && legs == 0) {
      return hasAbs ? 'Cardio, Arms & Abs' : 'Cardio & Arms';
    }
    if (cardio > 0 && legs > 0 && upper == 0) {
      return hasAbs ? 'Cardio, Legs & Abs' : 'Cardio & Legs';
    }

    // 3. Full Body (upper + lower)
    if (legs > 0 && upper > 0) {
      // If only 1 upper muscle and 1 lower muscle, name the specific combination
      if (legs > 0 &&
          allShoulders > 0 &&
          chest == 0 &&
          back == 0 &&
          arms == 0) {
        return hasAbs ? 'Legs, Shoulders & Abs' : 'Legs & Shoulders';
      }
      if (legs > 0 &&
          arms > 0 &&
          chest == 0 &&
          back == 0 &&
          allShoulders == 0) {
        return hasAbs ? 'Legs, Arms & Abs' : 'Legs & Arms';
      }
      if (legs > 0 &&
          chest > 0 &&
          back == 0 &&
          allShoulders == 0 &&
          arms == 0) {
        return hasAbs ? 'Legs, Chest & Abs' : 'Legs & Chest';
      }
      if (legs > 0 &&
          back > 0 &&
          chest == 0 &&
          allShoulders == 0 &&
          arms == 0) {
        return hasAbs ? 'Legs, Back & Abs' : 'Legs & Back';
      }
      return 'Full Body';
    }

    // 4. Arms (Biceps / Triceps / Forearms)
    if (arms > 0 && chest == 0 && back == 0 && allShoulders == 0 && legs == 0) {
      if (biceps > 0 && triceps > 0) {
        return hasAbs ? 'Arms & Abs' : 'Arm Day';
      }
      if (biceps > 0 && triceps == 0) {
        if (hasAbs) return 'Biceps & Abs';
        return forearms > 0 ? 'Biceps & Forearms' : 'Biceps Day';
      }
      if (triceps > 0 && biceps == 0) {
        return hasAbs ? 'Triceps & Abs' : 'Triceps Day';
      }
      return hasAbs ? 'Arms & Abs' : 'Arm Day';
    }

    // 5. Push (Chest, Front/Side Delts, Triceps)
    if (push > 0 && back == 0 && biceps == 0 && rearDelts == 0 && legs == 0) {
      if (chest > 0 && frontSideDelts > 0 && triceps > 0) {
        return hasAbs ? 'Push & Abs' : 'Push Day';
      }
      if (chest > 0 && triceps > 0 && frontSideDelts == 0) {
        return hasAbs ? 'Chest, Triceps & Abs' : 'Chest & Triceps';
      }
      if (chest > 0 && frontSideDelts > 0 && triceps == 0) {
        return hasAbs ? 'Chest, Shoulders & Abs' : 'Chest & Shoulders';
      }
      if (frontSideDelts > 0 && triceps > 0 && chest == 0) {
        return hasAbs ? 'Shoulders, Triceps & Abs' : 'Shoulders & Triceps';
      }
      if (chest > 0 && frontSideDelts == 0 && triceps == 0) {
        return hasAbs ? 'Chest & Abs' : 'Chest Day';
      }
      if (frontSideDelts > 0 && chest == 0 && triceps == 0) {
        return hasAbs ? 'Shoulders & Abs' : 'Shoulder Day';
      }
      if (triceps > 0 && chest == 0 && frontSideDelts == 0) {
        return hasAbs ? 'Triceps & Abs' : 'Triceps Day';
      }
      return hasAbs ? 'Push & Abs' : 'Push Day';
    }

    // 6. Pull (Back, Biceps, Rear Delts, Forearms)
    if (pull > 0 &&
        chest == 0 &&
        triceps == 0 &&
        frontSideDelts == 0 &&
        legs == 0) {
      if (back > 0 && biceps > 0) {
        if (total >= 4 || rearDelts > 0) {
          return hasAbs ? 'Pull & Abs' : 'Pull Day';
        }
        return hasAbs ? 'Back, Biceps & Abs' : 'Back & Biceps';
      }
      if (back > 0 && biceps == 0) {
        if (rearDelts > 0 && total >= 3) {
          return hasAbs ? 'Pull & Abs' : 'Pull Day';
        }
        return hasAbs ? 'Back & Abs' : 'Back Day';
      }
      if (biceps > 0 && back == 0 && rearDelts == 0) {
        return hasAbs ? 'Biceps & Abs' : 'Biceps Day';
      }
      return hasAbs ? 'Pull & Abs' : 'Pull Day';
    }

    // 7. Shoulders with Arms (no chest, no back, no legs)
    if (allShoulders > 0 && arms > 0 && chest == 0 && back == 0 && legs == 0) {
      if (biceps > 0 && triceps > 0) {
        return hasAbs ? 'Shoulders, Arms & Abs' : 'Shoulders & Arms';
      }
      if (triceps > 0 && biceps == 0) {
        return hasAbs ? 'Shoulders, Triceps & Abs' : 'Shoulders & Triceps';
      }
      if (biceps > 0 && triceps == 0) {
        return hasAbs ? 'Shoulders, Biceps & Abs' : 'Shoulders & Biceps';
      }
    }

    // 8. Shoulders only (no chest, no back, no arms, no legs)
    if (allShoulders > 0 && chest == 0 && back == 0 && arms == 0 && legs == 0) {
      return hasAbs ? 'Shoulders & Abs' : 'Shoulder Day';
    }

    // 9. Chest Combinations (no legs)
    if (chest > 0 && legs == 0) {
      if (back > 0) {
        if (hasAbs && allShoulders == 0 && arms == 0)
          return 'Chest, Back & Abs';
        if (allShoulders == 0 && arms == 0) return 'Chest & Back';
        if (total <= 4 && arms == 0) return 'Chest & Back';
        return hasAbs ? 'Upper Body & Abs' : 'Upper Body';
      }
      if (biceps > 0 && triceps == 0 && back == 0 && allShoulders == 0) {
        return hasAbs ? 'Chest, Biceps & Abs' : 'Chest & Biceps';
      }
      if (biceps > 0 && triceps > 0 && back == 0 && allShoulders == 0) {
        return hasAbs ? 'Chest, Arms & Abs' : 'Chest & Arms';
      }
      if (hasAbs && back == 0 && arms == 0 && allShoulders == 0) {
        return 'Chest & Abs';
      }
    }

    // 10. Back Combinations (no legs)
    if (back > 0 && legs == 0) {
      if (triceps > 0 && biceps == 0 && chest == 0 && allShoulders == 0) {
        return hasAbs ? 'Back, Triceps & Abs' : 'Back & Triceps';
      }
      if (biceps > 0 && triceps > 0 && chest == 0 && allShoulders == 0) {
        return hasAbs ? 'Back, Arms & Abs' : 'Back & Arms';
      }
      if (allShoulders > 0 && chest == 0 && arms == 0) {
        return hasAbs ? 'Back, Shoulders & Abs' : 'Back & Shoulders';
      }
      if (hasAbs && chest == 0 && arms == 0 && allShoulders == 0) {
        return 'Back & Abs';
      }
    }

    // 11. Legs (no upper)
    if (legs > 0 && upper == 0) {
      if (hasAbs) {
        if (glutes > 0 && quads == 0 && hamstrings == 0) return 'Glutes & Abs';
        if (quads > 0 && hamstrings == 0 && glutes == 0) return 'Quads & Abs';
        return 'Legs & Abs';
      }
      if ((hamstrings > 0 || glutes > 0) && quads == 0) {
        if (glutes > 0 && hamstrings > 0) return 'Glutes & Hamstrings';
        if (glutes > 0) return 'Glutes Day';
        if (hamstrings > 0) return 'Hamstrings Day';
      }
      if (quads > 0 && calves > 0 && hamstrings == 0 && glutes == 0) {
        return 'Quads & Calves';
      }
      if (hamstrings > 0 && calves > 0 && quads == 0 && glutes == 0) {
        return 'Hamstrings & Calves';
      }
      return 'Leg Day';
    }

    // 12. Upper Body
    if (legs == 0 && upper > 0) {
      return hasAbs ? 'Upper Body & Abs' : 'Upper Body';
    }

    // 13. Abs / Core only
    if (hasAbs && upper == 0 && legs == 0) {
      return 'Abs & Core';
    }

    // 14. Dynamic Fallback: compose active labels
    final labels = <String>[];
    if (chest > 0) labels.add('Chest');
    if (back > 0) labels.add('Back');
    if (allShoulders > 0) labels.add('Shoulders');
    if (arms > 0) {
      if (biceps > 0 && triceps == 0) {
        labels.add('Biceps');
      } else if (triceps > 0 && biceps == 0) {
        labels.add('Triceps');
      } else {
        labels.add('Arms');
      }
    }
    if (legs > 0) {
      if (glutes > 0 && quads == 0 && hamstrings == 0) {
        labels.add('Glutes');
      } else {
        labels.add('Legs');
      }
    }
    if (hasAbs) labels.add('Abs');
    if (cardio > 0) labels.add('Cardio');

    if (labels.length == 1) {
      final single = labels.first;
      if (single == 'Abs' || single == 'Cardio') return single;
      return '$single Day';
    }
    if (labels.length == 2) {
      return '${labels[0]} & ${labels[1]}';
    }
    if (labels.length == 3) {
      return '${labels[0]}, ${labels[1]} & ${labels[2]}';
    }

    return 'Quick Workout';
  }
}
