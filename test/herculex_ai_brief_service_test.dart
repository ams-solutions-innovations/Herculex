import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/herculex_ai_brief_service.dart';
import 'package:herculex/features/programs/domain/program_brief.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

import 'support/test_database.dart';

Map<String, dynamic> _validBriefJson() => {
  'splitType': 'upper_lower',
  'periodizationModel': 'linear',
  'dayRoles': [
    {
      'dayIndex': 0,
      'role': 'intensity',
      'focus': 'Upper body heavy pressing',
      'rationale': 'Front-loads the week while recovery is freshest.',
    },
    {
      'dayIndex': 1,
      'role': 'volume',
      'focus': 'Lower body accumulation',
      'rationale': 'Builds volume before the next intensity day.',
    },
  ],
  'musclePriorities': [
    {
      'muscleId': 'chest',
      'priority': 'high',
      'confidence': 0.8,
      'rationale': 'Lagging relative to back.',
      'uncertainties': <String>[],
    },
  ],
  'phaseIntent': 'Build upper body symmetry ahead of the next block.',
};

class _FixedClock implements Clock {
  _FixedClock(this.time);
  DateTime time;
  @override
  DateTime now() => time;
}

/// A minimal `GeminiBackend` fake whose only implemented method is
/// `generateProgramBrief` (configurable per test); every other method throws
/// `UnimplementedError`, matching the existing `_MockGeminiBackend`
/// convention in `dream_physique_service_test.dart` and
/// `body_fat_ai_service_test.dart`.
class _FakeGeminiBackend implements GeminiBackend {
  _FakeGeminiBackend({this.result, this.provenance, this.error});

  Map<String, dynamic>? result;
  Map<String, dynamic>? provenance;
  Object? error;

  Map<String, dynamic>? lastProfileInputs;
  String? lastUserNote;

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateProgramBrief({
    required Map<String, dynamic> profileInputs,
    String? userNote,
  }) async {
    lastProfileInputs = profileInputs;
    lastUserNote = userNote;
    if (error != null) throw error!;
    return (
      result ?? _validBriefJson(),
      provenance ?? const <String, dynamic>{},
    );
  }

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) => throw UnimplementedError();

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) => throw UnimplementedError();
}

Future<int> _insertProgram(AppDatabase db, {String name = 'Test Program'}) {
  return db.into(db.programs).insert(ProgramsCompanion.insert(name: name));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HerculexAiBriefService.generateBrief', () {
    test('valid backend result parses into a ProgramBrief', () async {
      final backend = _FakeGeminiBackend(
        provenance: {'knowledgeVersion': 'kb-1', 'modelVersion': 'gemini-2.5'},
      );
      final db = await openTestDatabase();
      addTearDown(db.close);
      final service = HerculexAiBriefService(
        backend,
        db,
        _FixedClock(DateTime(2026, 9, 30)),
      );

      final (brief, provenance) = await service.generateBrief(
        profileInputs: {'sex': 'male'},
        userNote: 'Prefer 4 days/week',
      );

      expect(brief.splitType, SplitType.upperLower);
      expect(
        brief.phaseIntent,
        'Build upper body symmetry ahead of the next block.',
      );
      expect(provenance, {
        'knowledgeVersion': 'kb-1',
        'modelVersion': 'gemini-2.5',
      });
      expect(backend.lastProfileInputs, {'sex': 'male'});
      expect(backend.lastUserNote, 'Prefer 4 days/week');
    });

    test(
      'backend not-configured failure translates into a recoverable, non-technical exception',
      () async {
        final backend = _FakeGeminiBackend(
          error: Exception(
            'AI analysis is not configured. Build with Supabase credentials and deploy '
            'the gemini-analyze Edge Function with a server-side GEMINI_API_KEY secret.',
          ),
        );
        final db = await openTestDatabase();
        addTearDown(db.close);
        final service = HerculexAiBriefService(
          backend,
          db,
          _FixedClock(DateTime(2026, 9, 30)),
        );

        await expectLater(
          service.generateBrief(profileInputs: const {}),
          throwsA(
            isA<HerculexAiBriefException>()
                .having((e) => e.recoverable, 'recoverable', isTrue)
                .having((e) => e.isQuotaExhausted, 'isQuotaExhausted', isFalse)
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('Exception:')),
                ),
          ),
        );
      },
    );

    test(
      'quota-exhausted backend failure is distinguishable from the generic offline/unconfigured case',
      () async {
        final backend = _FakeGeminiBackend(
          error: Exception(
            "Today's Herculex AI program briefs (10/day) are used up — try again tomorrow.",
          ),
        );
        final db = await openTestDatabase();
        addTearDown(db.close);
        final service = HerculexAiBriefService(
          backend,
          db,
          _FixedClock(DateTime(2026, 9, 30)),
        );

        await expectLater(
          service.generateBrief(profileInputs: const {}),
          throwsA(
            isA<HerculexAiBriefException>().having(
              (e) => e.isQuotaExhausted,
              'isQuotaExhausted',
              isTrue,
            ),
          ),
        );
      },
    );

    test(
      'malformed brief JSON produces a message distinct from the network-failure case',
      () async {
        final backend = _FakeGeminiBackend(
          result: {'splitType': 'upper_lower'},
        );
        final db = await openTestDatabase();
        addTearDown(db.close);
        final service = HerculexAiBriefService(
          backend,
          db,
          _FixedClock(DateTime(2026, 9, 30)),
        );

        await expectLater(
          service.generateBrief(profileInputs: const {}),
          throwsA(
            isA<HerculexAiBriefException>().having(
              (e) => e.message,
              'message',
              'Herculex AI returned an incomplete brief. Try generating again.',
            ),
          ),
        );
      },
    );
  });

  group('HerculexAiBriefService.persistBrief', () {
    test(
      'inserts exactly one row with provenance and Clock-stamped confirmedAt',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);
        final programId = await _insertProgram(db);
        final fixedTime = DateTime(2026, 9, 30, 12);
        final service = HerculexAiBriefService(
          _FakeGeminiBackend(),
          db,
          _FixedClock(fixedTime),
        );
        final brief = ProgramBrief.fromJson(_validBriefJson());

        await service.persistBrief(
          programId: programId,
          brief: brief,
          provenance: {
            'knowledgeVersion': 'kb-2',
            'modelVersion': 'gemini-2.5',
          },
        );

        final rows = await db.select(db.herculexAiProgramBriefs).get();
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row.programId, programId);
        expect(row.source, 'herculex_ai');
        expect(row.knowledgeVersion, 'kb-2');
        expect(row.modelVersion, 'gemini-2.5');
        expect(row.confirmedAt, fixedTime);
        expect(row.active, isTrue);
        final decoded = jsonDecode(row.briefJson) as Map<String, dynamic>;
        expect(decoded['splitType'], 'upper_lower');
        expect(decoded['phaseIntent'], brief.phaseIntent);
      },
    );
  });

  group('HerculexAiBriefService.watchBriefForProgram', () {
    test(
      'emits the most recent active row for the program, newest first',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);
        final programId = await _insertProgram(db);
        final service = HerculexAiBriefService(
          _FakeGeminiBackend(),
          db,
          _FixedClock(DateTime(2026, 9, 30)),
        );

        await db
            .into(db.herculexAiProgramBriefs)
            .insert(
              HerculexAiProgramBriefsCompanion.insert(
                programId: programId,
                briefJson: jsonEncode(_validBriefJson()),
                confirmedAt: Value(DateTime(2026, 9, 1)),
              ),
            );
        await db
            .into(db.herculexAiProgramBriefs)
            .insert(
              HerculexAiProgramBriefsCompanion.insert(
                programId: programId,
                briefJson: jsonEncode({
                  ..._validBriefJson(),
                  'phaseIntent': 'Newest brief.',
                }),
                confirmedAt: Value(DateTime(2026, 9, 20)),
              ),
            );

        final row = await service.watchBriefForProgram(programId).first;

        expect(row, isNotNull);
        final decoded = jsonDecode(row!.briefJson) as Map<String, dynamic>;
        expect(decoded['phaseIntent'], 'Newest brief.');
      },
    );

    test('emits null when no brief exists for the program', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final programId = await _insertProgram(db);
      final service = HerculexAiBriefService(
        _FakeGeminiBackend(),
        db,
        _FixedClock(DateTime(2026, 9, 30)),
      );

      final row = await service.watchBriefForProgram(programId).first;

      expect(row, isNull);
    });
  });
}
