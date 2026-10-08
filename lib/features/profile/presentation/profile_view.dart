import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/core/utils/env.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/sync/sync_service.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/theme/theme_provider.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/measurements/data/body_fat_ai_service.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/speech_to_text_service.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/goal_target_provider.dart';
import 'package:herculex/features/physique/presentation/save_goal_target.dart';
import 'package:herculex/features/profile/data/local_profile_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/profile/presentation/widgets/activity_level_section.dart';
import 'package:herculex/features/profile/presentation/widgets/dream_physique_summary_card.dart';
import 'package:herculex/features/profile/presentation/widgets/dream_physique_nutrition_direction_card.dart';
import 'package:herculex/features/profile/presentation/widgets/sync_status_badge.dart';
import 'package:herculex/features/workouts/application/workout_bubble_controller.dart';
import 'package:herculex/services/platform/workout_bubble_service.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

part 'profile_view/_auth.part.dart';
part 'profile_view/_body.part.dart';
part 'profile_view/_identity.part.dart';
part 'profile_view/_settings.part.dart';
part 'profile_view/_target_cards.part.dart';

/// Latest logged value per body-measurement metric (waist, neck, hips ...).
final _latestMeasurementsProvider = StreamProvider<Map<String, double>>((ref) {
  return ref.watch(measurementsRepositoryProvider).watchAll().map((rows) {
    final latest = <String, double>{};
    // Rows arrive oldest-first, so later entries overwrite earlier ones.
    for (final r in rows) {
      latest[r.metric] = r.value;
    }
    return latest;
  });
});

// ── Profile view ─────────────────────────────────────────────────────────────
//
// The measurement-system preference now lives in `core/units.dart` so the
// workout and nutrition screens can honour it too (they previously read a
// private provider they had no access to, which is why imperial users still
// saw kilograms in workouts).
