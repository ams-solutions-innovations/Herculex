import 'dart:io';

import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';

class FakeFaceDetector implements FaceDetectorPort {
  FakeFaceDetector({this.boxes = const [], this.throwOnDetect});

  final List<FaceBox> boxes;
  final Object? throwOnDetect;
  int callCount = 0;
  String? lastPath;

  @override
  Future<List<FaceBox>> detect(File uprightImage) async {
    callCount++;
    lastPath = uprightImage.path;
    if (throwOnDetect != null) throw throwOnDetect!;
    return boxes;
  }
}
