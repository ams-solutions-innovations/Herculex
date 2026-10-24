import 'dart:convert';
import 'dart:math';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/labs/data/labs_repository.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';

class LabsDataSource {
  LabsDataSource(this.db, this.nutrition, this.repository);
  final AppDatabase db;
  final NutritionRepository nutrition;
  final LabsRepository repository;

  Future<List<LabsObservation>> load(DateTime end, {DateTime? start}) async {
    final consent = repository.consent;
    if (!consent.enabled) return [];
    final cutoff =
        start ??
        (consent.history
            ? DateTime(end.year, end.month, end.day - 180)
            : labsDay(consent.since ?? end));
    final rows = <LabsObservation>[];
    void add(
      LabsCategory category,
      String metric,
      DateTime at,
      double value,
      String unit,
      String source,
      String id, {
      String stratum = '',
      String quality = 'recorded',
    }) {
      if (!consent.allows(category) ||
          at.isBefore(cutoff) ||
          !at.isBefore(end) ||
          !value.isFinite) {
        return;
      }
      rows.add(
        LabsObservation(
          id: '$source:$id:$metric:$stratum',
          category: category,
          metric: metric,
          at: at,
          value: value,
          unit: unit,
          source: source,
          stratum: stratum,
          quality: quality,
        ),
      );
    }

    final weights = <String, double>{};
    if (consent.allows(LabsCategory.physique)) {
      for (final m in await db.select(db.bodyMeasurements).get()) {
        if (m.deletedAt != null) continue;
        final at = DateTime.parse(m.dateIso);
        if (m.metric == 'bodyweight') weights[m.dateIso] = m.value;
        add(
          LabsCategory.physique,
          m.metric,
          at,
          m.value,
          m.metric == 'bodyweight'
              ? 'kg'
              : m.metric == 'body_fat'
              ? '%'
              : 'cm',
          'measurements',
          '${m.id}',
        );
      }
      for (final a in await db.select(db.physiqueAssessments).get()) {
        if (a.deletedAt != null || a.kind != 'checkin') continue;
        add(
          LabsCategory.physique,
          'physique_checkin',
          DateTime.parse(a.dateIso),
          1,
          'check-in',
          'physique',
          '${a.id}',
          quality: 'self_reported',
        );
      }
    }
    if (consent.allows(LabsCategory.sleep) ||
        consent.allows(LabsCategory.context)) {
      // HealthSamples has no per-device provenance; choose highest row id for
      // each day/kind, never sum overlapping device measurements.
      final latest = <String, HealthSampleData>{};
      for (final h in await db.select(db.healthSamples).get()) {
        final key = '${h.dateIso}:${h.kind}';
        if (!latest.containsKey(key) || h.id > latest[key]!.id) latest[key] = h;
      }
      for (final h in latest.values) {
        const units = {
          'sleep_hours': 'h',
          'resting_hr': 'bpm',
          'steps': 'steps',
          'active_kcal': 'kcal',
        };
        if (!units.containsKey(h.kind)) continue;
        final cat = h.kind == 'sleep_hours'
            ? LabsCategory.sleep
            : LabsCategory.context;
        add(
          cat,
          h.kind,
          DateTime.parse(h.dateIso),
          h.value,
          units[h.kind]!,
          'health',
          '${h.id}',
        );
      }
      if (consent.allows(LabsCategory.context)) {
        for (final d in await db.select(db.dailySummaries).get()) {
          if (d.deletedAt == null && d.waterMl > 0) {
            add(
              LabsCategory.context,
              'water_ml',
              DateTime.parse(d.dateIso),
              d.waterMl.toDouble(),
              'ml',
              'daily_summary',
              d.dateIso,
            );
          }
        }
        for (final c in repository.records('checkin')) {
          final at = DateTime.parse(c['at']);
          for (final entry in (c['values'] as Map).entries) {
            add(
              LabsCategory.context,
              entry.key,
              at,
              (entry.value as num).toDouble(),
              entry.key == 'caffeine_mg'
                  ? 'mg'
                  : entry.key == 'alcohol_units'
                  ? 'units'
                  : '/5',
              'checkin',
              labsDate(at),
              quality: 'self_reported',
            );
          }
        }
      }
    }
    if (consent.categories.any(
      {
        LabsCategory.strength,
        LabsCategory.training,
        LabsCategory.techniques,
      }.contains,
    )) {
      final snapshot = await TrainingSnapshot.load(
        db,
        from: cutoff,
        until: end,
      );
      final sessions = <int, List<ResolvedSet>>{};
      for (final s in snapshot.sets) {
        if (s.session.endedAt == null ||
            s.session.deletedAt != null ||
            s.set.deletedAt != null ||
            s.workoutExercise.deletedAt != null ||
            s.set.isWarmup ||
            !s.set.isCompleted) {
          continue;
        }
        sessions.putIfAbsent(s.session.id, () => []).add(s);
      }
      for (final entry in sessions.entries) {
        final sets = entry.value, session = sets.first.session;
        final at = session.startedAt;
        final id = '${entry.key}';
        final minutes = session.endedAt!.difference(at).inSeconds / 60;
        add(
          LabsCategory.training,
          'working_sets',
          at,
          sets.length.toDouble(),
          'sets',
          'workout',
          id,
        );
        add(
          LabsCategory.training,
          'reps',
          at,
          sets.fold(0.0, (n, s) => n + s.countedReps),
          'reps',
          'workout',
          id,
        );
        add(
          LabsCategory.training,
          'training_hour',
          at,
          at.hour + at.minute / 60,
          'h',
          'workout',
          id,
        );
        if (minutes > 0) {
          add(
            LabsCategory.training,
            'training_minutes',
            at,
            minutes,
            'min',
            'workout',
            id,
          );
          add(
            LabsCategory.training,
            'density',
            at,
            sets.length / minutes,
            'sets/min',
            'workout',
            id,
          );
        }
        final effort = sets.where((s) => s.set.rpeX10 != null).toList();
        if (effort.isNotEmpty) {
          add(
            LabsCategory.training,
            'rpe',
            at,
            effort.fold(0.0, (n, s) => n + s.set.rpeX10! / 10) / effort.length,
            '/10',
            'workout',
            id,
            quality: 'self_reported',
          );
        }
        add(
          LabsCategory.techniques,
          'advanced_fraction',
          at,
          sets.where((s) => s.set.setType != 'standard').length /
              sets.length *
              100,
          '%',
          'workout',
          id,
        );
        add(
          LabsCategory.techniques,
          'superset_fraction',
          at,
          sets.where((s) => s.workoutExercise.supersetGroup != null).length /
              sets.length *
              100,
          '%',
          'workout',
          id,
        );
        final repSets = sets.where((s) => s.metric.isRepBased).toList();
        if (repSets.isNotEmpty) {
          add(
            LabsCategory.training,
            'rep_mean',
            at,
            repSets.fold(0.0, (n, s) => n + s.set.reps) / repSets.length,
            'reps/set',
            'workout',
            id,
          );
          for (final band in [(1, 5), (6, 12), (13, 30)]) {
            add(
              LabsCategory.training,
              'rep_band_${band.$1}_${band.$2}',
              at,
              repSets
                  .where((s) => s.set.reps >= band.$1 && s.set.reps <= band.$2)
                  .length
                  .toDouble(),
              'sets',
              'workout',
              id,
            );
          }
        }
        final muscleSets = <String, double>{};
        for (final set in sets) {
          for (final muscle in snapshot.exerciseMuscles.where(
            (m) => m.exerciseId == set.exercise.id && m.role == 'primary',
          )) {
            muscleSets[muscle.muscle] = (muscleSets[muscle.muscle] ?? 0) + 1;
          }
        }
        for (final muscle in muscleSets.entries) {
          add(
            LabsCategory.training,
            'muscle_sets',
            at,
            muscle.value,
            'sets',
            'workout',
            id,
            stratum: muscle.key,
          );
        }
        final types = sets.map((s) => s.set.setType).toSet();
        for (final type in types) {
          add(
            LabsCategory.techniques,
            'set_type',
            at,
            sets.where((s) => s.set.setType == type).length.toDouble(),
            'sets',
            'workout',
            id,
            stratum: type,
          );
        }
        final exerciseGroups = <String, List<ResolvedSet>>{};
        for (final set in repSets.where((s) => s.set.setType == 'standard')) {
          final effort = set.set.rpeX10 == null
              ? 'effort unknown'
              : 'RPE ${(set.set.rpeX10! / 10).round()}';
          final key =
              '${set.exercise.name} · ${set.equipmentVariant} · ${set.accessoryCombo} · $effort';
          exerciseGroups.putIfAbsent(key, () => []).add(set);
        }
        for (final group in exerciseGroups.entries) {
          final count = group.value.length;
          add(
            LabsCategory.strength,
            'exercise_load',
            at,
            group.value.fold(0.0, (v, s) => v + s.effectiveKg) / count,
            'kg',
            'workout',
            id,
            stratum: group.key,
          );
          add(
            LabsCategory.strength,
            'exercise_reps',
            at,
            group.value.fold(0.0, (v, s) => v + s.set.reps) / count,
            'reps/set',
            'workout',
            id,
            stratum: group.key,
          );
          add(
            LabsCategory.strength,
            'exercise_sets',
            at,
            count.toDouble(),
            'sets',
            'workout',
            id,
            stratum: group.key,
          );
        }
        final grouped = <String, double>{};
        for (final s in sets.where(
          (s) =>
              s.metric.isRepBased &&
              s.set.reps > 0 &&
              s.set.reps <= 10 &&
              s.effectiveKg > 0 &&
              s.set.setType == 'standard',
        )) {
          // Missing RPE never silently joins a known effort stratum.
          final effort = s.set.rpeX10 == null
              ? 'effort unknown'
              : 'RPE ${(s.set.rpeX10! / 10).round()}';
          final key =
              '${s.exercise.name} · ${s.equipmentVariant} · ${s.accessoryCombo} · $effort';
          grouped[key] = max(
            grouped[key] ?? 0,
            s.effectiveKg * (1 + s.set.reps / 30),
          );
        }
        for (final best in grouped.entries) {
          add(
            LabsCategory.strength,
            'e1rm',
            at,
            best.value,
            'kg',
            'workout',
            id,
            stratum: best.key,
            quality: 'estimated',
          );
        }
      }
    }
    if (consent.allows(LabsCategory.nutrition)) {
      final totals = await nutrition
          .watchDailyTotalsForRange(cutoff, end)
          .first;
      for (final e in totals.entries) {
        final at = DateTime.parse(e.key), t = e.value;
        for (final m in {
          'kcal': t.kcal,
          'protein': t.proteinG,
          'carbs': t.carbsG,
          'fat': t.fatG,
          'fiber': t.fiberG,
        }.entries) {
          add(
            LabsCategory.nutrition,
            m.key,
            at,
            m.value,
            m.key == 'kcal' ? 'kcal' : 'g',
            'nutrition',
            e.key,
          );
        }
        final known =
            weights.keys
                .where(
                  (d) =>
                      d.compareTo(e.key) <= 0 &&
                      at.difference(DateTime.parse(d)).inDays <= 7,
                )
                .toList()
              ..sort();
        if (known.isNotEmpty && weights[known.last]! > 0) {
          add(
            LabsCategory.nutrition,
            'protein_g_kg',
            at,
            t.proteinG / weights[known.last]!,
            'g/kg',
            'nutrition',
            e.key,
          );
        }
      }
    }
    if (consent.allows(LabsCategory.fasting)) {
      for (final f in await db.select(db.fastingSessions).get()) {
        if (f.deletedAt != null ||
            f.endedAt == null ||
            f.endedAt!.isAfter(end)) {
          continue;
        }
        add(
          LabsCategory.fasting,
          'fasting_hours',
          f.endedAt!,
          f.endedAt!.difference(f.startedAt).inSeconds / 3600,
          'h',
          'fasting',
          '${f.id}',
        );
      }
    }
    if (consent.allows(LabsCategory.supplements)) {
      final exact = <String>{};
      for (final intake in repository.records('intake')) {
        final at = DateTime.parse(intake['at']);
        final p = intake['product'] as Map;
        final id = '${p['id']}';
        exact.add('${labsDate(at)}:$id');
        final dose = p['doseAmount'] as num?;
        if (dose != null && p['doseUnit'] != null) {
          add(
            LabsCategory.supplements,
            'supplement_dose',
            at,
            intake['taken'] == true ? dose.toDouble() : 0,
            '${p['doseUnit']}',
            'supplement_dose',
            '${labsDate(at)}:$id',
            stratum: '${p['name'] ?? id} [$id] · ${p['doseUnit']}',
            quality: 'self_reported',
          );
        }

        add(
          LabsCategory.supplements,
          'supplement:${p['name'] ?? id} [$id]',
          at,
          intake['taken'] == true ? 1 : 0,
          'taken (1) / skipped (0)',
          'supplement',
          '${labsDate(at)}:$id',
          quality: 'self_reported',
        );
      }
      // Legacy positives may be used with explicit unknown dose. Never
      // infer non-use from absent ticks, and never apply today's dose to them.
      if (consent.history) {
        final config =
            jsonDecode(
                  repository.prefs.getString('supplements_config_v1') ?? '[]',
                )
                as List;
        final names = {for (final p in config) '${p['id']}': '${p['name']}'};
        for (final key in repository.prefs.getKeys().where(
          (k) => k.startsWith('supplements_taken_'),
        )) {
          final day = key.substring('supplements_taken_'.length);
          final at = DateTime.tryParse(day);
          if (at == null) continue;
          for (final id
              in jsonDecode(repository.prefs.getString(key)!) as List) {
            if (exact.contains('$day:$id')) continue;
            add(
              LabsCategory.supplements,
              'supplement:${names[id] ?? id} [$id]',
              at,
              1,
              'taken (dose unknown)',
              'supplement_legacy',
              '$day:$id',
              quality: 'self_reported',
            );
          }
        }
      }
    }
    return rows;
  }
}
