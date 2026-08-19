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
      group: json['group'] as String? ?? 'Mišična skupina',
      priority: json['priority'] as String? ?? 'medium',
      focus: json['focus'] as String? ?? 'Progresivna obremenitev',
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
    final range = json['timeframeRange'] as String? ?? '$months mesecev';
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
                group: 'Zgornji del prsi',
                priority: 'high',
                focus: 'Incline potiski in kabli pod kotom',
              ),
              MusclePriority(
                group: 'Stranske rame',
                priority: 'high',
                focus: 'Lateralni dvigi za V-obliko',
              ),
              MusclePriority(
                group: 'Hrbet / Lats',
                priority: 'medium',
                focus: 'Široki potegi za širino hrbta',
              ),
            ],
      nutritionStrategy: json['nutritionStrategy'] as String? ??
          'Priporočen prilagojen vnos kalorij z 2.0g beljakovin na kg telesne teže.',
      trainingAdvice: json['trainingAdvice'] as String? ??
          'Trening 4-5x tedensko z dosledno progresivno obremenitvijo.',
      overallAssessment: json['overallAssessment'] as String? ??
          'Cilj je realen in dosegljiv z doslednim pristopom.',
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
        throw Exception('Izberite vsaj eno fotografijo svoje trenutne postave.');
      }

      if (!await targetImage.exists()) {
        throw Exception('Ciljna fotografija sanjske postave ne obstaja.');
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
        timeframeRange: '${estMonths - 1} - ${estMonths + 2} mesecev',
        weightChangeKg: double.parse(netWeightChange.toStringAsFixed(1)),
        leanMuscleGainKg: double.parse(muscleToGain.toStringAsFixed(1)),
        fatLossKg: double.parse(fatToLose.toStringAsFixed(1)),
        targetBfPercent: double.parse(targetBf.toStringAsFixed(1)),
        currentEstimatedBf: double.parse(estCurrentBf.toStringAsFixed(1)),
        musclePriorities: const [
          MusclePriority(
            group: 'Zgornji del prsi (Upper Chest)',
            priority: 'high',
            focus: 'Incline potiski z ročkami in kabelni dvigi pod kotom za V-obliko',
          ),
          MusclePriority(
            group: 'Stranske rame (Lateral Delts)',
            priority: 'high',
            focus: 'Lateralni dvigi na škripcu in z ročkami z visoko frekvenco (2-3x tedensko)',
          ),
          MusclePriority(
            group: 'Hrbet / V-Taper (Lats)',
            priority: 'medium',
            focus: 'Široki potegi na prsa in enoročni potegi za širino hrbta',
          ),
          MusclePriority(
            group: 'Trup / Abs & Serratus',
            priority: 'high',
            focus: 'Viseči dvigi kolen, cable crunches in znižanje telesne maščobe',
          ),
          MusclePriority(
            group: 'Roke (Biceps / Triceps)',
            priority: 'medium',
            focus: 'Izolacijske vaje za dolgo glavo tricepsa in vrh bicepsa',
          ),
        ],
        nutritionStrategy:
            'Priporočen zmeren kalorični deficit (cca 250–400 kcal pod vzdrževalnimi) z visokim vnosom beljakovin (2.0–2.2 g/kg).',
        trainingAdvice:
            'Frekvenca 4-5 treningov tedensko (Upper/Lower ali PPL) s poudarkom na zgornjem delu prsi in stranskih ramenih.',
        overallAssessment:
            'Ocena narejena na podlagi biometričnega profila (AI povezava: $e). Cilj je dosegljiv z doslednim treningom in načrtovano prehrano.',
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
