import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/measurements/presentation/body_fat_ai_dialog.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'BodyFatAiDialog requires explicit privacy consent when a photo is selected and defaults face blur to on',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      late final SharedPreferences prefs;
      late final AppDatabase db;
      await tester.runAsync(() async {
        prefs = await SharedPreferences.getInstance();
        db = AppDatabase.forTesting(NativeDatabase.memory());
      });
      addTearDown(() => tester.runAsync(db.close));

      final tempDir = Directory.systemTemp.createTempSync('bf_dialog_test_');
      addTearDown(() {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } on FileSystemException {
          // Windows keeps decoded image handles open until GC.
        }
      });
      final photoFile = File('${tempDir.path}/sample.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 16, height: 16)));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            measurementsRepositoryProvider.overrideWithValue(
              _StubMeasurementsRepository(db),
            ),
            profileProvider.overrideWith(
              (ref) => Stream.value(
                const Profile(
                  goal: FitnessGoal.maintenance,
                  activityLevel: ActivityLevel.active,
                  weightKg: 80,
                  heightCm: 180,
                  ageYears: 28,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: BodyFatAiDialog(initialImage: photoFile)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final blurFinder = find.byKey(const Key('body-fat-blur-faces'));
      final consentFinder = find.byKey(const Key('body-fat-privacy-consent'));
      final analyzeButtonFinder = find.ancestor(
        of: find.textContaining('Analyze (1 photos) with Herculex AI'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );

      expect(blurFinder, findsOneWidget);
      expect(tester.widget<SwitchListTile>(blurFinder).value, isTrue);
      expect(consentFinder, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(consentFinder).value, isFalse);
      expect(
        tester.widget<ButtonStyleButton>(analyzeButtonFinder).onPressed,
        isNull,
      );

      tester.widget<CheckboxListTile>(consentFinder).onChanged!(true);
      await tester.pump();

      expect(
        tester.widget<ButtonStyleButton>(analyzeButtonFinder).onPressed,
        isNotNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
    },
  );
}

class _StubMeasurementsRepository extends MeasurementsRepository {
  _StubMeasurementsRepository(super.database);

  @override
  Future<Map<String, double>> getLatestMeasurements() async => const {};

  @override
  Future<List<ProgressPhotoData>> getRecentPhotos({
    int limit = 20,
    String? pose,
  }) async => const [];
}
