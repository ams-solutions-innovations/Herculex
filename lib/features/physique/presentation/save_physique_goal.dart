import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/physique/application/physique_goal_starter.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/presentation/dialogs/baseline_privacy_dialog.dart';
import 'package:herculex/features/physique/presentation/dialogs/no_face_found_dialog.dart';
import 'package:herculex/features/physique/presentation/dialogs/start_new_goal_dialog.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';

/// Turns a Dream Physique analysis into a persistent goal (D-01, D-03, D-07).
///
/// Order: confirm replacing an active goal, choose blur, stage the sanitised
/// photos, warn when blur found no face, then persist. Returns true when a
/// goal was created. Never throws: a storage failure must not discard a valid
/// AI result, so the caller keeps showing it.
Future<bool> savePhysiqueGoal(
  BuildContext context,
  WidgetRef ref, {
  required DreamPhysiqueAnalysisResult result,
  required List<File> currentPhotos,
  required int targetPhotoCount,
  File? targetPhoto,
}) async {
  final starter = ref.read(physiqueGoalStarterProvider);
  List<StagedPhoto> staged = const [];
  try {
    final active = await ref.read(activePhysiqueGoalProvider.future);
    if (!context.mounted) return false;
    if (active != null) {
      if (await StartNewGoalDialog.show(context) != true) return false;
      if (!context.mounted) return false;
    }

    final blur = await BaselinePrivacyDialog.show(
      context,
      initialBlur: ref.read(physiquePrivacyPreferencesProvider).blurFaces,
    );
    if (blur == null || !context.mounted) return false;

    staged = await starter.stagePhotos(files: currentPhotos, blurFaces: blur);
    if (!context.mounted) {
      await starter.discardStaged(staged);
      return false;
    }

    if (blur && staged.any((s) => s.noFaceFound)) {
      final choice = await NoFaceFoundDialog.show(context);
      if (choice != NoFaceChoice.saveWithoutBlur) {
        await starter.discardStaged(staged);
        return false;
      }
    }

    await starter.startFromAnalysis(
      result: result,
      staged: staged,
      targetPhotoCount: targetPhotoCount,
      targetPhoto: targetPhoto,
    );
    return true;
  } on Object catch (e) {
    debugPrint('Saving the physique goal failed: $e');
    try {
      await starter.discardStaged(staged);
    } on Object catch (_) {}
    return false;
  }
}
