import 'dart:async';
import 'dart:convert';

import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local, privacy-preserving record of the most recent Dream Physique
/// analysis. Source photos are deliberately not copied or persisted here.
class DreamPhysiqueAnalysisSummary {
  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime analyzedAt;
  final String targetAestheticStyle;
  final String timeframeRange;
  final int estimatedMonths;
  final double targetBfPercent;
  final double currentEstimatedBf;
  final double weightChangeKg;
  final int currentPhotoCount;
  final int targetPhotoCount;

  const DreamPhysiqueAnalysisSummary({
    required this.schemaVersion,
    required this.analyzedAt,
    required this.targetAestheticStyle,
    required this.timeframeRange,
    required this.estimatedMonths,
    required this.targetBfPercent,
    required this.currentEstimatedBf,
    required this.weightChangeKg,
    required this.currentPhotoCount,
    required this.targetPhotoCount,
  });

  factory DreamPhysiqueAnalysisSummary.fromResult({
    required DreamPhysiqueAnalysisResult result,
    required int currentPhotoCount,
    required int targetPhotoCount,
    DateTime? analyzedAt,
  }) {
    return DreamPhysiqueAnalysisSummary(
      schemaVersion: currentSchemaVersion,
      analyzedAt: analyzedAt ?? DateTime.now().toUtc(),
      targetAestheticStyle: result.targetAestheticStyle,
      timeframeRange: result.timeframeRange,
      estimatedMonths: result.estimatedMonths,
      targetBfPercent: result.targetBfPercent,
      currentEstimatedBf: result.currentEstimatedBf,
      weightChangeKg: result.weightChangeKg,
      currentPhotoCount: currentPhotoCount,
      targetPhotoCount: targetPhotoCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'analyzedAt': analyzedAt.toUtc().toIso8601String(),
    'targetAestheticStyle': targetAestheticStyle,
    'timeframeRange': timeframeRange,
    'estimatedMonths': estimatedMonths,
    'targetBfPercent': targetBfPercent,
    'currentEstimatedBf': currentEstimatedBf,
    'weightChangeKg': weightChangeKg,
    'currentPhotoCount': currentPhotoCount,
    'targetPhotoCount': targetPhotoCount,
  };

  factory DreamPhysiqueAnalysisSummary.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    final analyzedAt = json['analyzedAt'];
    final targetAestheticStyle = json['targetAestheticStyle'];
    final timeframeRange = json['timeframeRange'];
    final estimatedMonths = json['estimatedMonths'];
    final targetBfPercent = json['targetBfPercent'];
    final currentEstimatedBf = json['currentEstimatedBf'];
    final weightChangeKg = json['weightChangeKg'];
    final currentPhotoCount = json['currentPhotoCount'];
    final targetPhotoCount = json['targetPhotoCount'];

    if (schemaVersion is! int ||
        schemaVersion < 1 ||
        analyzedAt is! String ||
        targetAestheticStyle is! String ||
        targetAestheticStyle.trim().isEmpty ||
        timeframeRange is! String ||
        timeframeRange.trim().isEmpty ||
        estimatedMonths is! int ||
        targetBfPercent is! num ||
        currentEstimatedBf is! num ||
        weightChangeKg is! num ||
        currentPhotoCount is! int ||
        targetPhotoCount is! int) {
      throw const FormatException('Invalid Dream Physique summary.');
    }

    final parsedDate = DateTime.tryParse(analyzedAt);
    if (parsedDate == null || currentPhotoCount < 0 || targetPhotoCount < 0) {
      throw const FormatException('Invalid Dream Physique summary.');
    }

    return DreamPhysiqueAnalysisSummary(
      schemaVersion: schemaVersion,
      analyzedAt: parsedDate.toUtc(),
      targetAestheticStyle: targetAestheticStyle.trim(),
      timeframeRange: timeframeRange.trim(),
      estimatedMonths: estimatedMonths,
      targetBfPercent: targetBfPercent.toDouble(),
      currentEstimatedBf: currentEstimatedBf.toDouble(),
      weightChangeKg: weightChangeKg.toDouble(),
      currentPhotoCount: currentPhotoCount,
      targetPhotoCount: targetPhotoCount,
    );
  }
}

class DreamPhysiqueSummaryRepository {
  static const _legacyStorageKey = 'herculex.dream_physique_summary.v1';
  static const _historyStorageKey =
      'herculex.dream_physique_summary_history.v1';
  static const _maxHistoryLength = 20;

  final SharedPreferences _preferences;
  final _controller =
      StreamController<DreamPhysiqueAnalysisSummary?>.broadcast();
  final _historyController =
      StreamController<List<DreamPhysiqueAnalysisSummary>>.broadcast();

  DreamPhysiqueSummaryRepository(this._preferences) {
    _controller.onListen = () {
      scheduleMicrotask(() {
        if (!_controller.isClosed) _controller.add(current);
      });
    };
    _historyController.onListen = () {
      scheduleMicrotask(() {
        if (!_historyController.isClosed) _historyController.add(history);
      });
    };
  }

  /// Newest-first list of past analyses, capped at [_maxHistoryLength].
  ///
  /// Migrates the old single-summary key on first read: if the history list
  /// is still empty but a legacy summary exists, it becomes the sole entry.
  List<DreamPhysiqueAnalysisSummary> get history {
    final raw = _preferences.getStringList(_historyStorageKey);
    if (raw != null) {
      final parsed = <DreamPhysiqueAnalysisSummary>[];
      for (final entry in raw) {
        try {
          final decoded = jsonDecode(entry);
          if (decoded is! Map) continue;
          parsed.add(
            DreamPhysiqueAnalysisSummary.fromJson(
              Map<String, dynamic>.from(decoded),
            ),
          );
        } catch (_) {
          // Skip a corrupted entry rather than losing the rest of the list.
        }
      }
      return parsed;
    }

    final legacy = _readLegacy();
    return legacy == null ? const [] : [legacy];
  }

  DreamPhysiqueAnalysisSummary? _readLegacy() {
    final raw = _preferences.getString(_legacyStorageKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return DreamPhysiqueAnalysisSummary.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  DreamPhysiqueAnalysisSummary? get current =>
      history.isEmpty ? null : history.first;

  Stream<DreamPhysiqueAnalysisSummary?> watch() => _controller.stream;

  Stream<List<DreamPhysiqueAnalysisSummary>> watchHistory() =>
      _historyController.stream;

  Future<void> save(DreamPhysiqueAnalysisSummary summary) async {
    final updated = [summary, ...history].take(_maxHistoryLength).toList();
    await _preferences.setStringList(
      _historyStorageKey,
      updated.map((s) => jsonEncode(s.toJson())).toList(),
    );
    _controller.add(summary);
    _historyController.add(updated);
  }

  void dispose() {
    _controller.close();
    _historyController.close();
  }
}
