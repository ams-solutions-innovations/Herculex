import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/measurements/data/body_fat_ai_service.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
import 'package:image/image.dart' as img;

Uint8List _makeJpegWithExif() {
  final image = img.Image(width: 48, height: 48);
  img.fill(image, color: img.ColorRgb8(50, 130, 210));
  img.fillRect(
    image,
    x1: 12,
    y1: 12,
    x2: 36,
    y2: 36,
    color: img.ColorRgb8(240, 60, 40),
  );
  image.exif.imageIfd['Artist'] = 'Sensitive Author';
  image.exif.gpsIfd['GPSLatitudeRef'] = 'N';
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

void main() {
  group('BodyFatAiService', () {
    test('Navy formula calculates accurate body fat for male', () {
      // Height 180cm, Waist 82cm, Neck 38cm
      final bf = BodyFatAiService.calculateNavyBodyFat(
        heightCm: 180,
        waistCm: 82,
        neckCm: 38,
        isMale: true,
      );

      expect(bf, isNotNull);
      expect(bf!, greaterThan(10.0));
      expect(bf, lessThan(18.0));
    });

    test('Navy formula calculates accurate body fat for female', () {
      // Height 165cm, Waist 70cm, Neck 32cm, Hips 95cm
      final bf = BodyFatAiService.calculateNavyBodyFat(
        heightCm: 165,
        waistCm: 70,
        neckCm: 32,
        hipsCm: 95,
        isMale: false,
      );

      expect(bf, isNotNull);
      expect(bf!, greaterThan(18.0));
      expect(bf, lessThan(28.0));
    });

    test('BMI formula computes sensible baseline', () {
      final bf = BodyFatAiService.calculateBmiBodyFat(
        weightKg: 80,
        heightCm: 180,
        ageYears: 25,
        isMale: true,
      );

      expect(bf, greaterThan(12.0));
      expect(bf, lessThan(22.0));
    });

    test(
      'Delegates to Gemini backend when images provided and strips EXIF/GPS metadata',
      () async {
        final fakeBackend = _MockGeminiBackend();
        final service = BodyFatAiService(fakeBackend);

        final tempDir = await Directory.systemTemp.createTemp('bf_test_');
        addTearDown(() => tempDir.delete(recursive: true));
        final imageFile = File('${tempDir.path}/test_body.jpg');
        await imageFile.writeAsBytes(_makeJpegWithExif());

        const profile = Profile(
          goal: FitnessGoal.muscleGain,
          activityLevel: ActivityLevel.active,
          weightKg: 80.0,
          heightCm: 180.0,
          ageYears: 28,
          sex: BiologicalSex.male,
        );

        final result = await service.estimateBodyFat(
          imageFiles: [imageFile],
          consentGranted: true,
          profile: profile,
          measurements: {'waist': 82.0, 'neck': 38.0},
          userNote: 'morning photo',
        );

        expect(result.estimatedBfPercent, 13.8);
        expect(result.bfRangeMin, 12.5);
        expect(result.bfRangeMax, 15.0);
        expect(result.leanMassKg, isNotNull);
        expect(result.fatMassKg, isNotNull);
        expect(result.isAiGenerated, isTrue);
        expect(fakeBackend.calledEstimate, isTrue);
        expect(fakeBackend.receivedImages, hasLength(1));

        final sentBytes = Uint8List.fromList(
          fakeBackend.receivedImages!.single['bytes'] as List<int>,
        );
        final decoded = img.decodeJpg(sentBytes);
        expect(decoded, isNotNull);
        expect(decoded!.exif.imageIfd.isEmpty, isTrue);
        expect(decoded.exif.gpsIfd.isEmpty, isTrue);
      },
    );

    test(
      'Blurs detected faces on device when blurFaces is true before sending',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('bf_blur_test_');
        addTearDown(() => tempDir.delete(recursive: true));

        final detector = _FakeFaceDetector([
          const FaceBox(left: 12, top: 12, width: 24, height: 24),
        ]);
        final sanitizer = PhysiquePhotoSanitizer(
          faceDetector: detector,
          stagingDirectory: () async => Directory('${tempDir.path}/staging'),
        );
        final fakeBackend = _MockGeminiBackend();
        final service = BodyFatAiService(fakeBackend, sanitizer: sanitizer);

        final imageFile = File('${tempDir.path}/face_body.jpg');
        await imageFile.writeAsBytes(_makeJpegWithExif());

        final result = await service.estimateBodyFat(
          imageFiles: [imageFile],
          consentGranted: true,
          blurFaces: true,
        );

        expect(result.isAiGenerated, isTrue);
        expect(detector.calls, 1);
        expect(fakeBackend.receivedImages, hasLength(1));
      },
    );

    test(
      'Requires explicit privacy consent before reading or uploading images',
      () async {
        final fakeBackend = _MockGeminiBackend();
        final service = BodyFatAiService(fakeBackend);

        await expectLater(
          service.estimateBodyFat(
            imageFiles: [File('unopened_photo.jpg')],
            consentGranted: false,
          ),
          throwsA(
            isA<BodyFatAiException>()
                .having((e) => e.recoverable, 'recoverable', isFalse)
                .having(
                  (e) => e.message,
                  'message',
                  contains('privacy notice'),
                ),
          ),
        );
        expect(fakeBackend.calledEstimate, isFalse);
      },
    );

    test('Enforces maxPhotos (4) limit', () async {
      final fakeBackend = _MockGeminiBackend();
      final service = BodyFatAiService(fakeBackend);

      await expectLater(
        service.estimateBodyFat(
          imageFiles: List.generate(5, (i) => File('photo_$i.jpg')),
          consentGranted: true,
        ),
        throwsA(
          isA<BodyFatAiException>().having(
            (e) => e.recoverable,
            'recoverable',
            isFalse,
          ),
        ),
      );
      expect(fakeBackend.calledEstimate, isFalse);
    });

    test(
      'Propagates recoverable BodyFatAiException when backend fails instead of fabricating 15%',
      () async {
        final failingBackend = _FailingBodyFatBackend();
        final service = BodyFatAiService(failingBackend);

        final tempDir = await Directory.systemTemp.createTemp('bf_fail_test_');
        addTearDown(() => tempDir.delete(recursive: true));
        final imageFile = File('${tempDir.path}/test_body.jpg');
        await imageFile.writeAsBytes(_makeJpegWithExif());

        await expectLater(
          service.estimateBodyFat(
            imageFiles: [imageFile],
            consentGranted: true,
          ),
          throwsA(
            isA<BodyFatAiException>()
                .having((e) => e.recoverable, 'recoverable', isTrue)
                .having(
                  (e) => e.message,
                  'message',
                  contains('Gateway timeout'),
                ),
          ),
        );
      },
    );

    test(
      'Falls back gracefully to anthropometric formula without images when profile/measurements exist',
      () async {
        final fakeBackend = _MockGeminiBackend();
        final service = BodyFatAiService(fakeBackend);

        const profile = Profile(
          goal: FitnessGoal.maintenance,
          activityLevel: ActivityLevel.active,
          weightKg: 80.0,
          heightCm: 180.0,
          ageYears: 28,
          sex: BiologicalSex.male,
        );

        final result = await service.estimateBodyFat(
          imageFiles: [],
          profile: profile,
          measurements: {'waist': 82.0, 'neck': 38.0},
        );

        expect(result.estimatedBfPercent, greaterThan(10.0));
        expect(result.isAiGenerated, isFalse);
        expect(fakeBackend.calledEstimate, isFalse);
      },
    );

    test(
      'Throws honest BodyFatAiException when neither images nor anthropometric data exist',
      () async {
        final fakeBackend = _MockGeminiBackend();
        final service = BodyFatAiService(fakeBackend);

        await expectLater(
          service.estimateBodyFat(imageFiles: []),
          throwsA(
            isA<BodyFatAiException>().having(
              (e) => e.recoverable,
              'recoverable',
              isFalse,
            ),
          ),
        );
        expect(fakeBackend.calledEstimate, isFalse);
      },
    );
  });
}

class _FakeFaceDetector implements FaceDetectorPort {
  _FakeFaceDetector(this._boxes);
  final List<FaceBox> _boxes;
  int calls = 0;

  @override
  Future<List<FaceBox>> detect(File uprightImage) async {
    calls += 1;
    return _boxes;
  }
}

class _MockGeminiBackend implements GeminiBackend {
  bool calledEstimate = false;
  List<Map<String, dynamic>>? receivedImages;

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    calledEstimate = true;
    receivedImages = images;
    return {
      'estimatedBfPercent': 13.8,
      'bfRangeMin': 12.5,
      'bfRangeMax': 15.0,
      'confidence': 0.92,
      'explanation':
          'Good abdominal definition and low levels of subcutaneous fat.',
      'fatDistribution': 'Moderate on lower abdomen.',
      'recommendations': 'Maintain current calorie intake.',
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) async => throw UnimplementedError();

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async => throw UnimplementedError();

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateProgramBrief({
    required Map<String, dynamic> profileInputs,
    String? userNote,
  }) async => throw UnimplementedError();
}

class _FailingBodyFatBackend extends _MockGeminiBackend {
  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    throw Exception('Gateway timeout');
  }
}
