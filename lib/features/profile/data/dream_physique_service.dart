import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

final dreamPhysiqueServiceProvider = Provider<DreamPhysiqueService>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  return DreamPhysiqueService(backend);
});

const canonicalProgrammingMuscleIds = <String>{
  'chest',
  'back',
  'lats',
  'traps',
  'front_delts',
  'side_delts',
  'rear_delts',
  'biceps',
  'triceps',
  'forearms',
  'abs',
  'obliques',
  'neck',
  'quads',
  'hamstrings',
  'glutes',
  'calves',
  'adductors',
  'abductors',
};

enum ProgrammingPriorityLevel {
  high,
  medium,
  maintenance;

  String get wireValue => name;

  static ProgrammingPriorityLevel fromWire(Object? value) {
    return switch (value) {
      'high' => ProgrammingPriorityLevel.high,
      'medium' => ProgrammingPriorityLevel.medium,
      'maintenance' => ProgrammingPriorityLevel.maintenance,
      _ => throw const FormatException(
        'Invalid programming priority in Dream Physique response.',
      ),
    };
  }
}

class MusclePriority {
  final String group;
  final String priority; // 'high', 'medium', 'maintenance'
  final String focus;

  const MusclePriority({
    required this.group,
    required this.priority,
    required this.focus,
  });

  factory MusclePriority.fromJson(Map<String, dynamic> json) {
    final priority = ProgrammingPriorityLevel.fromWire(json['priority']);
    return MusclePriority(
      group: _requiredString(json, 'group'),
      priority: priority.wireValue,
      focus: _requiredString(json, 'focus'),
    );
  }
}

class ProgrammingMusclePriority {
  final String muscleId;
  final ProgrammingPriorityLevel priority;
  final double confidence;
  final String rationale;
  final List<String> uncertainties;

  const ProgrammingMusclePriority({
    required this.muscleId,
    required this.priority,
    required this.confidence,
    required this.rationale,
    required this.uncertainties,
  });

  factory ProgrammingMusclePriority.fromJson(Map<String, dynamic> json) {
    final muscleId = _requiredString(json, 'muscleId');
    if (!canonicalProgrammingMuscleIds.contains(muscleId)) {
      throw FormatException(
        'Unknown canonical muscle id in Dream Physique response: $muscleId',
      );
    }

    final confidence = _requiredDouble(json, 'confidence');
    if (confidence < 0 || confidence > 1) {
      throw const FormatException(
        'Programming priority confidence must be between 0 and 1.',
      );
    }

    return ProgrammingMusclePriority(
      muscleId: muscleId,
      priority: ProgrammingPriorityLevel.fromWire(json['priority']),
      confidence: confidence,
      rationale: _requiredString(json, 'rationale'),
      uncertainties: _stringList(json['uncertainties']),
    );
  }

  ProgrammingMusclePriority copyWith({ProgrammingPriorityLevel? priority}) {
    return ProgrammingMusclePriority(
      muscleId: muscleId,
      priority: priority ?? this.priority,
      confidence: confidence,
      rationale: rationale,
      uncertainties: uncertainties,
    );
  }
}

class DreamPhysiqueProgrammingProfile {
  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final double overallConfidence;
  final List<ProgrammingMusclePriority> musclePriorities;
  final List<String> uncertainties;

  const DreamPhysiqueProgrammingProfile({
    required this.schemaVersion,
    required this.overallConfidence,
    required this.musclePriorities,
    required this.uncertainties,
  });

  factory DreamPhysiqueProgrammingProfile.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion < 1) {
      throw const FormatException(
        'Invalid Dream Physique programming profile version.',
      );
    }

    final overallConfidence = _requiredDouble(json, 'overallConfidence');
    if (overallConfidence < 0 || overallConfidence > 1) {
      throw const FormatException(
        'Programming profile confidence must be between 0 and 1.',
      );
    }

    final rawPriorities = json['musclePriorities'];
    if (rawPriorities is! List || rawPriorities.isEmpty) {
      throw const FormatException(
        'Dream Physique programming profile has no muscle priorities.',
      );
    }

    final priorities = rawPriorities
        .map((value) {
          if (value is! Map) {
            throw const FormatException(
              'Invalid muscle priority in Dream Physique response.',
            );
          }
          return ProgrammingMusclePriority.fromJson(
            Map<String, dynamic>.from(value),
          );
        })
        .toList(growable: false);

    return DreamPhysiqueProgrammingProfile(
      schemaVersion: schemaVersion,
      overallConfidence: overallConfidence,
      musclePriorities: priorities,
      uncertainties: _stringList(json['uncertainties']),
    );
  }
}

class DreamPhysiqueAnalysisResult {
  final int estimatedMonths;
  final String timeframeRange;
  final double weightChangeKg;
  final double leanMuscleGainKg;
  final double fatLossKg;
  final double targetBfPercent;
  final double currentEstimatedBf;
  final List<MusclePriority> musclePriorities;
  final String nutritionStrategy;
  final String trainingAdvice;
  final String overallAssessment;
  final String targetAestheticStyle;
  final DreamPhysiqueProgrammingProfile? programmingProfile;
  final bool isAiGenerated;

  const DreamPhysiqueAnalysisResult({
    required this.estimatedMonths,
    required this.timeframeRange,
    required this.weightChangeKg,
    required this.leanMuscleGainKg,
    required this.fatLossKg,
    required this.targetBfPercent,
    required this.currentEstimatedBf,
    required this.musclePriorities,
    required this.nutritionStrategy,
    required this.trainingAdvice,
    required this.overallAssessment,
    required this.targetAestheticStyle,
    this.programmingProfile,
    this.isAiGenerated = true,
  });

  factory DreamPhysiqueAnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawPriorities = json['musclePriorities'];
    if (rawPriorities is! List) {
      throw const FormatException(
        'Dream Physique response is missing muscle priorities.',
      );
    }
    final priorities = rawPriorities
        .map((value) {
          if (value is! Map) {
            throw const FormatException(
              'Invalid muscle priority in Dream Physique response.',
            );
          }
          return MusclePriority.fromJson(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);

    final rawProgrammingProfile = json['programmingProfile'];
    final programmingProfile = rawProgrammingProfile == null
        ? null
        : rawProgrammingProfile is Map
        ? DreamPhysiqueProgrammingProfile.fromJson(
            Map<String, dynamic>.from(rawProgrammingProfile),
          )
        : throw const FormatException(
            'Invalid Dream Physique programming profile.',
          );

    return DreamPhysiqueAnalysisResult(
      estimatedMonths: _requiredInt(json, 'estimatedMonths'),
      timeframeRange: _requiredString(json, 'timeframeRange'),
      weightChangeKg: _requiredDouble(json, 'weightChangeKg'),
      leanMuscleGainKg: _requiredDouble(json, 'leanMuscleGainKg'),
      fatLossKg: _requiredDouble(json, 'fatLossKg'),
      targetBfPercent: _requiredDouble(json, 'targetBfPercent'),
      currentEstimatedBf: _requiredDouble(json, 'currentEstimatedBf'),
      musclePriorities: priorities,
      nutritionStrategy: _requiredString(json, 'nutritionStrategy'),
      trainingAdvice: _requiredString(json, 'trainingAdvice'),
      overallAssessment: _requiredString(json, 'overallAssessment'),
      targetAestheticStyle: _requiredString(json, 'targetAestheticStyle'),
      programmingProfile: programmingProfile,
      isAiGenerated: true,
    );
  }
}

class DreamPhysiqueAnalysisException implements Exception {
  final String message;
  final bool recoverable;

  const DreamPhysiqueAnalysisException(this.message, {this.recoverable = true});

  @override
  String toString() => message;
}

class DreamPhysiqueService {
  final GeminiBackend _backend;

  DreamPhysiqueService(this._backend);

  Future<DreamPhysiqueAnalysisResult> compareAndAnalyzePhysique({
    required List<File> currentImages,
    required List<File> targetImages,
    required bool consentGranted,
    Profile? profile,
    Map<String, double>? measurements,
    String? userNote,
  }) async {
    if (!consentGranted) {
      throw const DreamPhysiqueAnalysisException(
        'Confirm the photo privacy notice before starting the analysis.',
        recoverable: false,
      );
    }

    final biometrics = <String, dynamic>{
      if (profile != null) ...{
        'sex': profile.sex == BiologicalSex.female ? 'female' : 'male',
        'weightKg': profile.weightKg,
        'heightCm': profile.heightCm,
        'ageYears': profile.ageYears,
      },
      ...?measurements != null ? {'measurements': measurements} : null,
    };

    try {
      final currentPayload = <Map<String, dynamic>>[];
      for (final file in currentImages) {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          currentPayload.add({
            'bytes': bytes,
            'mimeType': _mimeType(file.path),
          });
        }
      }

      if (currentPayload.isEmpty) {
        throw const DreamPhysiqueAnalysisException(
          'Select at least one available photo of your current physique.',
          recoverable: false,
        );
      }

      if (targetImages.isEmpty) {
        throw const DreamPhysiqueAnalysisException(
          'Select at least one target photo of your dream physique.',
          recoverable: false,
        );
      }
      if (currentPayload.length + targetImages.length > 4) {
        throw const DreamPhysiqueAnalysisException(
          'Use at most four photos across your current and target physiques.',
          recoverable: false,
        );
      }

      final targetPayload = <Map<String, dynamic>>[];
      for (final file in targetImages) {
        if (!await file.exists()) {
          throw const DreamPhysiqueAnalysisException(
            'One of the selected target physique photos is no longer available.',
            recoverable: false,
          );
        }
        targetPayload.add({
          'bytes': await file.readAsBytes(),
          'mimeType': _mimeType(file.path),
        });
      }

      final resultJson = await _backend.analyzeDreamPhysique(
        currentImages: currentPayload,
        targetImages: targetPayload,
        biometrics: biometrics,
        userNote: userNote,
      );

      try {
        return DreamPhysiqueAnalysisResult.fromJson(resultJson);
      } on FormatException {
        throw const DreamPhysiqueAnalysisException(
          'Gemini returned an incomplete analysis. Your selections were kept; please try again.',
        );
      }
    } on DreamPhysiqueAnalysisException {
      rethrow;
    } catch (error) {
      final detail = error.toString().replaceFirst('Exception: ', '').trim();
      final message = detail.isEmpty
          ? 'Gemini analysis is temporarily unavailable.'
          : detail;
      throw DreamPhysiqueAnalysisException(
        '$message Your selections were kept; please try again.',
      );
    }
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Dream Physique response is missing $key.');
}

double _requiredDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Dream Physique response is missing $key.');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('Dream Physique response is missing $key.');
}

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Expected a list of uncertainty notes.');
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
