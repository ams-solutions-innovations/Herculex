import 'dart:io';

import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';

/// The user's "dream physique" reference photo for one goal.
///
/// It lives in the physique sandbox under a fixed name, so there is no table
/// and no schema bump: the file's existence is the record. It is sanitised
/// (metadata stripped, long side capped) like every other physique photo and
/// stays on the device; deleting the goal folder deletes it too.
class PhysiqueDreamPhotoRepository {
  PhysiqueDreamPhotoRepository({
    required PhysiquePhotoStore store,
    required PhysiquePhotoSanitizer sanitizer,
  }) : _store = store,
       _sanitizer = sanitizer;

  static const String fileName = 'dream_target.jpg';

  final PhysiquePhotoStore _store;
  final PhysiquePhotoSanitizer _sanitizer;

  /// The saved photo for [goalUuid], or null when none was stored.
  Future<File?> find(String goalUuid) async {
    try {
      final file = await _store.resolve(
        _store.relativePathFor(goalUuid: goalUuid, fileName: fileName),
      );
      return await file.exists() ? file : null;
    } on Object {
      return null;
    }
  }

  /// Sanitises [source] and stores it as the goal's dream photo, replacing any
  /// earlier one. Returns false when the image could not be processed.
  Future<bool> save(File source, {required String goalUuid}) async {
    StagedPhoto? staged;
    try {
      staged = await _sanitizer.stage(source);
      await _store.adopt(staged.file, goalUuid: goalUuid, fileName: fileName);
      return true;
    } on Object {
      if (staged != null) await _sanitizer.discard(staged);
      return false;
    }
  }
}
