import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';

/// ML Kit adapter for [FaceDetectorPort]. Mapping only, no logic.
class MlKitFaceDetector implements FaceDetectorPort {
  @override
  Future<List<FaceBox>> detect(File uprightImage) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
    );
    try {
      final faces = await detector.processImage(
        InputImage.fromFilePath(uprightImage.path),
      );
      return [
        for (final f in faces)
          FaceBox(
            left: f.boundingBox.left,
            top: f.boundingBox.top,
            width: f.boundingBox.width,
            height: f.boundingBox.height,
          ),
      ];
    } finally {
      await detector.close();
    }
  }
}
