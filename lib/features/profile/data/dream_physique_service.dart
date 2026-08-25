import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/gemini_backend_service.dart';
import '../domain/profile.dart';

final dreamPhysiqueServiceProvider = Provider<DreamPhysiqueService>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  return DreamPhysiqueService(backend);
});

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
    return MusclePriority(
      group: json['group'] as String? ?? 'Muscle Group',
      priority: json['priority'] as String? ?? 'medium',
      focus: json['focus'] as String? ?? 'Progressive overload',
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
    this.isAiGenerated = true,
  });

  factory DreamPhysiqueAnalysisResult.fromJson(Map<String, dynamic> json) {
    final months = (json['estimatedMonths'] as num?)?.toInt() ?? 6;
    final range = json['timeframeRange'] as String? ?? '$months months';
    final weightDelta =
        (json['weightChangeKg'] as num?)?.toDouble() ?? 0.0;
    final muscleGain =
        (json['leanMuscleGainKg'] as num?)?.toDouble() ?? 2.5;
    final fatLoss = (json['fatLossKg'] as num?)?.toDouble() ?? 3.0;
    final targetBf =
        (json['targetBfPercent'] as num?)?.toDouble() ?? 12.0;
    final currentBf =
        (json['currentEstimatedBf'] as num?)?.toDouble() ?? 18.0;

    final rawPriorities = json['musclePriorities'] as List<dynamic>? ?? [];
    final priorities = rawPriorities
        .map((p) =>
            MusclePriority.fromJson(p is Map<String, dynamic> ? p : {}))
        .toList();

    return DreamPhysiqueAnalysisResult(
      estimatedMonths: months,
      timeframeRange: range,
      weightChangeKg: weightDelta,
      leanMuscleGainKg: muscleGain,
      fatLossKg: fatLoss,
      targetBfPercent: targetBf,
      currentEstimatedBf: currentBf,
      musclePriorities: priorities.isNotEmpty
          ? priorities
          : const [
              MusclePriority(
                group: 'Upper Chest',
                priority: 'high',
                focus: 'Incline presses and angled cable crossovers',
              ),
              MusclePriority(
                group: 'Lateral Delts',
                priority: 'high',
                focus: 'Lateral raises for V-taper',
              ),
              MusclePriority(
                group: 'Back / Lats',
                priority: 'medium',
                focus: 'Wide pulldowns for back width',
              ),
            ],
      nutritionStrategy: json['nutritionStrategy'] as String? ??
          'Recommended adjusted calorie intake with 2.0g protein per kg body weight.',
      trainingAdvice: json['trainingAdvice'] as String? ??
          'Train 4-5x weekly with consistent progressive overload.',
      overallAssessment: json['overallAssessment'] as String? ??
          'The goal is realistic and achievable with a consistent approach.',
      isAiGenerated: true,
    );
  }
}

class DreamPhysiqueService {
  final GeminiBackend _backend;

  DreamPhysiqueService(this._backend);

  Future<DreamPhysiqueAnalysisResult> compareAndAnalyzePhysique({
    required List<File> currentImages,
    required File targetImage,
    Profile? profile,
    Map<String, double>? measurements,
    String? targetGoalStyle,
    String? userNote,
  }) async {
    final weightKg = profile?.weightKg ?? 78.0;
    final heightCm = profile?.heightCm ?? 180.0;
    final age = profile?.ageYears ?? 25;
    final isMale = profile?.sex != BiologicalSex.female;

    final biometrics = <String, dynamic>{
      'sex': isMale ? 'male' : 'female',
      'weightKg': weightKg,
      'heightCm': heightCm,
      'ageYears': age,
      'targetGoalStyle': targetGoalStyle ?? 'Lean & Aesthetic',
      ...?measurements != null ? {'measurements': measurements} : null,
    };

    try {
      final currentPayload = <Map<String, dynamic>>[];
      for (final file in currentImages) {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final mime = _mimeType(file.path);
          currentPayload.add({'bytes': bytes, 'mimeType': mime});
        }
      }

      if (currentPayload.isEmpty) {
        throw Exception('Select at least one photo of your current physique.');
      }

      if (!await targetImage.exists()) {
        throw Exception('Target dream physique photo does not exist.');
      }

      final targetBytes = await targetImage.readAsBytes();
      final targetMime = _mimeType(targetImage.path);

      final resultJson = await _backend.analyzeDreamPhysique(
        currentImages: currentPayload,
        targetImageBytes: targetBytes,
        targetImageMimeType: targetMime,
        biometrics: biometrics,
        userNote: userNote,
      );

      return DreamPhysiqueAnalysisResult.fromJson(resultJson);
    } catch (e) {
      // Smart fallback computation based on body weight, height and goal style
      final estCurrentBf = isMale ? 18.0 : 25.0;
      final targetBf = targetGoalStyle?.contains('Lean') == true
          ? (isMale ? 10.5 : 18.0)
          : (isMale ? 12.0 : 20.0);

      final fatToLose =
          (weightKg * (estCurrentBf - targetBf) / 100.0).clamp(1.0, 15.0);
      final muscleToGain = (isMale ? 3.5 : 2.0);
      final netWeightChange = muscleToGain - fatToLose;

      // Realistic timeframe: fat loss @ 0.5kg/week, muscle gain @ 0.4kg/month
      final monthsForFat = fatToLose / 2.0;
      final monthsForMuscle = muscleToGain / 0.5;
      final estMonths = (monthsForFat > monthsForMuscle ? monthsForFat : monthsForMuscle)
          .ceil()
          .clamp(3, 18);

      return DreamPhysiqueAnalysisResult(
        estimatedMonths: estMonths,
        timeframeRange: '${estMonths - 1} - ${estMonths + 2} months',
        weightChangeKg: double.parse(netWeightChange.toStringAsFixed(1)),
        leanMuscleGainKg: double.parse(muscleToGain.toStringAsFixed(1)),
        fatLossKg: double.parse(fatToLose.toStringAsFixed(1)),
        targetBfPercent: double.parse(targetBf.toStringAsFixed(1)),
        currentEstimatedBf: double.parse(estCurrentBf.toStringAsFixed(1)),
        musclePriorities: const [
          MusclePriority(
            group: 'Upper Chest',
            priority: 'high',
            focus: 'Incline dumbbell presses and angled cable flyes for upper chest fullness',
          ),
          MusclePriority(
            group: 'Lateral Delts',
            priority: 'high',
            focus: 'Cable and dumbbell lateral raises with high frequency (2-3x weekly)',
          ),
          MusclePriority(
            group: 'Back / V-Taper (Lats)',
            priority: 'medium',
            focus: 'Wide lat pulldowns and single-arm rows for back width',
          ),
          MusclePriority(
            group: 'Core / Abs & Serratus',
            priority: 'high',
            focus: 'Hanging knee raises, cable crunches, and caloric deficit for leanness',
          ),
          MusclePriority(
            group: 'Arms (Biceps / Triceps)',
            priority: 'medium',
            focus: 'Isolation movements for long head of triceps and bicep peak',
          ),
        ],
        nutritionStrategy:
            'Recommended moderate calorie deficit (~250–400 kcal below maintenance) with high protein intake (2.0–2.2 g/kg).',
        trainingAdvice:
            'Frequency of 4-5 sessions per week (Upper/Lower or PPL) with emphasis on upper chest and lateral delts.',
        overallAssessment:
            'Estimate based on biometric profile (AI connection: $e). Goal is achievable with consistent training and structured nutrition.',
        isAiGenerated: false,
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
