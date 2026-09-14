import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/profile/presentation/dream_physique_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('requires explicit photo privacy consent before analysis', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final measurements = _EmptyMeasurementsRepository(database);
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWithValue(database),
          profileProvider.overrideWith((ref) => Stream.value(null)),
          measurementsRepositoryProvider.overrideWithValue(measurements),
        ],
        child: const MaterialApp(home: DreamPhysiqueView()),
      ),
    );
    // HxScreenShell owns a repeating ambient animation, so pumpAndSettle is
    // intentionally inappropriate here. Two frames are enough for the async
    // local context load to complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final consentFinder = find.byKey(
      const Key('dream-physique-privacy-consent'),
    );
    final startFinder = find.byKey(const Key('dream-physique-start-analysis'));

    expect(consentFinder, findsOneWidget);
    expect(find.textContaining('Google Gemini'), findsOneWidget);
    expect(
      find.textContaining('Herculex does not persist them'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(startFinder).onPressed, isNull);

    tester.widget<CheckboxListTile>(consentFinder).onChanged!(true);
    await tester.pump();

    expect(tester.widget<FilledButton>(startFinder).onPressed, isNotNull);
  });
}

class _EmptyMeasurementsRepository extends MeasurementsRepository {
  _EmptyMeasurementsRepository(super.database);

  @override
  Future<List<ProgressPhotoData>> getRecentPhotos({
    int limit = 20,
    String? pose,
  }) async => const [];

  @override
  Future<Map<String, double>> getLatestMeasurements() async => const {};
}
