import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/physique/presentation/widgets/phone_only_notice.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/presentation/dream_physique_priorities_view.dart';
import 'package:herculex/features/profile/presentation/dream_physique_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dream Physique used to paint with the static `AppColors` shim and literal
/// `Colors.*`, which only looked right in the default dark theme. These render
/// it under every colour theme in both brightnesses and check it takes its
/// colours from the theme.

const _profile = DreamPhysiqueProgrammingProfile(
  schemaVersion: 1,
  overallConfidence: 0.85,
  musclePriorities: [
    ProgrammingMusclePriority(
      muscleId: 'chest',
      priority: ProgrammingPriorityLevel.high,
      confidence: 0.9,
      rationale: 'Prominent pectoral development in the target photo.',
      uncertainties: [],
    ),
    ProgrammingMusclePriority(
      muscleId: 'back',
      priority: ProgrammingPriorityLevel.medium,
      confidence: 0.7,
      rationale: 'A wider upper back frames the shoulders.',
      uncertainties: [],
    ),
    ProgrammingMusclePriority(
      muscleId: 'quads',
      priority: ProgrammingPriorityLevel.maintenance,
      confidence: 0.6,
      rationale: 'Already close to the target.',
      uncertainties: [],
    ),
  ],
  uncertainties: [],
);

Future<void> _pumpSetup(
  WidgetTester tester, {
  required Brightness brightness,
  required AppColorTheme colorTheme,
  PlatformCapabilities? capabilities,
}) async {
  // Wide on purpose: flutter_test draws text in Ahem (one em per glyph), which
  // overflows the screen's section headers at a phone's width.
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(database),
        profileProvider.overrideWith((ref) => Stream.value(null)),
        measurementsRepositoryProvider.overrideWithValue(
          _EmptyMeasurementsRepository(database),
        ),
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
      child: MaterialApp(
        theme: AppTheme.buildTheme(brightness, colorTheme),
        home: const DreamPhysiqueView(),
      ),
    ),
  );
  // HxScreenShell owns a repeating ambient animation: pumpAndSettle never
  // settles. Two frames let the local context load finish.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpPriorities(
  WidgetTester tester, {
  required Brightness brightness,
  required AppColorTheme colorTheme,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        dreamPhysiqueSummaryProvider.overrideWith(
          (ref) => Stream.value(
            DreamPhysiqueAnalysisSummary(
              schemaVersion: 1,
              analyzedAt: DateTime(2026, 10, 27),
              targetAestheticStyle: 'Heroic build',
              timeframeRange: '16-24 weeks',
              currentEstimatedBf: 15,
              targetBfPercent: 12,
              weightChangeKg: 5.5,
              estimatedMonths: 5,
              currentPhotoCount: 2,
              targetPhotoCount: 2,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.buildTheme(brightness, colorTheme),
        home: const DreamPhysiquePrioritiesView(initialProfile: _profile),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final colorTheme in AppColorTheme.values) {
    for (final brightness in Brightness.values) {
      final name = '${colorTheme.label} ${brightness.name}';
      final hx = HxColors.of(brightness, colorTheme);

      testWidgets('setup screen follows the theme: $name', (tester) async {
        await _pumpSetup(
          tester,
          brightness: brightness,
          colorTheme: colorTheme,
        );
        expect(tester.takeException(), isNull);

        // Accents use the contrast-safe primaryText, not the vivid fill.
        final goalIcon = tester.widget<Icon>(
          find.byIcon(Icons.add_photo_alternate_rounded),
        );
        expect(goalIcon.color, hx.primaryText);

        // Captions take the theme's muted colours, never a literal grey.
        final count = tester.widget<Text>(find.text('0 / 3'));
        expect(count.style?.color, hx.secondary);
        final emptyPose = tester.widget<Text>(find.text('FRONT'));
        expect(emptyPose.style?.color, hx.tertiary);
      });

      testWidgets('priorities screen follows the theme: $name', (tester) async {
        await _pumpPriorities(
          tester,
          brightness: brightness,
          colorTheme: colorTheme,
        );
        expect(tester.takeException(), isNull);

        final confidence = tester.widget<Text>(find.text('AI confidence 85%'));
        expect(confidence.style?.color, hx.primaryText);
        // Priority badges carry the hue in tint and border; their text is the
        // body colour, which clears 4.5:1 on every surface.
        final badge = tester.widget<Text>(find.text('High').first);
        expect(badge.style?.color, hx.onSurface);
      });
    }
  }

  testWidgets('on the web photo analysis is replaced by a phone notice', (
    tester,
  ) async {
    await _pumpSetup(
      tester,
      brightness: Brightness.dark,
      colorTheme: AppColorTheme.classicBlue,
      capabilities: const PlatformCapabilities.web(),
    );

    expect(find.byType(PhysiquePhoneOnlyNotice), findsOneWidget);
    expect(find.text(PhysiquePhoneOnlyNotice.title), findsOneWidget);
    // None of the photo steps is offered, so none can fail on dart:io.
    expect(
      find.byKey(const Key('dream-physique-privacy-consent')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('dream-physique-start-analysis')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
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
