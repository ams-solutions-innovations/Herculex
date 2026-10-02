import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:image/image.dart' as img;

import '../../support/exif_jpeg_fixture.dart';
import '../../support/fake_face_detector.dart';

void main() {
  late Directory src;
  late Directory staging;

  setUp(() {
    src = Directory.systemTemp.createTempSync('san_src_');
    staging = Directory.systemTemp.createTempSync('san_stg_');
  });

  tearDown(() {
    for (final d in [src, staging]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  File write(List<int> bytes, [String name = 'in.jpg']) =>
      File('${src.path}/$name')..writeAsBytesSync(bytes);

  PhysiquePhotoSanitizer make(FakeFaceDetector d) => PhysiquePhotoSanitizer(
    faceDetector: d,
    stagingDirectory: () async => staging,
  );

  test('strips EXIF and bakes orientation', () async {
    final input = write(buildJpegWithExif());
    // Sanity: fixture really carries the metadata.
    final before = img.decodeJpg(input.readAsBytesSync())!;
    expect(before.exif.imageIfd.make, 'TestMake');

    final detector = FakeFaceDetector();
    final staged = await make(detector).stage(input);
    final out = img.decodeJpg(staged.file.readAsBytesSync())!;
    expect(out.exif.imageIfd.make, isNull);
    expect(out.exif.gpsIfd.gpsLatitude, isNull);
    expect(out.width, 48);
    expect(out.height, 64);
    expect(staged.width, 48);
    expect(staged.height, 64);
    expect(detector.callCount, 0);
    expect(input.existsSync(), isTrue);
  });

  test('downscales to 2048 long side, keeps small images', () async {
    final big = img.Image(width: 3000, height: 1000);
    final staged = await make(
      FakeFaceDetector(),
    ).stage(write(img.encodeJpg(big), 'big.jpg'));
    expect(staged.width, 2048);
    expect(staged.height, 683);
    final small = await make(
      FakeFaceDetector(),
    ).stage(write(buildJpegWithExif(orientation: 1), 's.jpg'));
    expect(small.width, 64);
    expect(small.height, 48);
  });

  test('undecodable bytes throw and write nothing', () async {
    await expectLater(
      make(FakeFaceDetector()).stage(write([1, 2, 3, 4], 'bad.jpg')),
      throwsA(isA<PhotoSanitizeException>()),
    );
    expect(staging.listSync(), isEmpty);
  });

  test('blur modifies pixels inside the box only', () async {
    final noisy = img.Image(width: 240, height: 240);
    for (final p in noisy) {
      final v = ((p.x ~/ 2 + p.y ~/ 2) % 2) * 220;
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    final input = write(img.encodeJpg(noisy, quality: 100));
    final plain = await make(FakeFaceDetector()).stage(input);
    final plainImg = img.decodeJpg(plain.file.readAsBytesSync())!;

    final detector = FakeFaceDetector(
      boxes: const [FaceBox(left: 100, top: 100, width: 40, height: 40)],
    );
    final staged = await make(detector).stage(input, blurFaces: true);
    final blurred = img.decodeJpg(staged.file.readAsBytesSync())!;

    expect(staged.blurApplied, isTrue);
    expect(staged.facesFound, 1);
    expect(staged.noFaceFound, isFalse);
    expect(detector.callCount, 1);

    var insideDiff = 0;
    for (var y = 105; y < 135; y++) {
      for (var x = 105; x < 135; x++) {
        if ((blurred.getPixel(x, y).r - plainImg.getPixel(x, y).r).abs() > 40) {
          insideDiff++;
        }
      }
    }
    expect(insideDiff, greaterThan(0));
    for (final (x, y) in [(5, 5), (230, 230), (10, 200), (200, 10)]) {
      // Allow for JPEG recompression noise outside the blurred region.
      expect(
        (blurred.getPixel(x, y).r - plainImg.getPixel(x, y).r).abs(),
        lessThan(12),
      );
    }
    expect(blurred.exif.gpsIfd.gpsLatitude, isNull);
  });

  test('no face found: reported honestly, not blurred', () async {
    final detector = FakeFaceDetector();
    final staged = await make(
      detector,
    ).stage(write(buildJpegWithExif()), blurFaces: true);
    expect(staged.facesFound, 0);
    expect(staged.blurApplied, isFalse);
    expect(staged.noFaceFound, isTrue);
    expect(detector.callCount, 1);
  });

  test('detector runs on the sanitised upright temp file', () async {
    final detector = FakeFaceDetector();
    final input = write(buildJpegWithExif());
    final staged = await make(detector).stage(input, blurFaces: true);
    expect(detector.lastPath, staged.file.path);
    expect(detector.lastPath, isNot(input.path));
  });

  test(
    'detector failure becomes PhotoSanitizeException and cleans up',
    () async {
      final detector = FakeFaceDetector(throwOnDetect: StateError('boom'));
      await expectLater(
        make(detector).stage(write(buildJpegWithExif()), blurFaces: true),
        throwsA(isA<PhotoSanitizeException>()),
      );
      expect(staging.listSync(), isEmpty);
    },
  );

  test('analysisBytes is <=1280 and EXIF-free', () async {
    final big = img.Image(width: 2000, height: 1500);
    big.exif.imageIfd.make = 'X';
    final bytes = await make(
      FakeFaceDetector(),
    ).analysisBytes(write(img.encodeJpg(big), 'a.jpg'));
    final out = img.decodeJpg(bytes)!;
    expect(out.width, 1280);
    expect(out.exif.imageIfd.make, isNull);
  });

  test('discard deletes and tolerates a missing file', () async {
    final s = make(FakeFaceDetector());
    final staged = await s.stage(write(buildJpegWithExif()));
    await s.discard(staged);
    expect(staged.file.existsSync(), isFalse);
    await s.discard(staged);
  });
}
