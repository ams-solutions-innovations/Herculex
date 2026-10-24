import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/labs/data/labs_ai_service.dart';
import 'package:herculex/features/labs/data/labs_data_source.dart';
import 'package:herculex/features/labs/data/labs_pdf_service.dart';
import 'package:herculex/features/labs/data/labs_repository.dart';
import 'package:herculex/features/labs/domain/labs_diet_evaluator.dart';
import 'package:herculex/features/labs/domain/labs_engine.dart';
import 'package:herculex/features/labs/domain/labs_experiment_evaluator.dart';
import 'package:herculex/features/labs/domain/labs_models.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

const labsEnabled = bool.fromEnvironment('HERCULEX_LABS', defaultValue: true);
final labsRepositoryProvider = Provider<LabsRepository>((ref) {
  final repo = LabsRepository(ref.watch(sharedPreferencesProvider));
  ref.onDispose(repo.changes.close);
  return repo;
});
final labsRevisionProvider = StateProvider<int>((ref) => 0);
final labsChangesProvider = StreamProvider<void>(
  (ref) => ref.watch(labsRepositoryProvider).changes.stream,
);
final labsConsentProvider = Provider<LabsConsent>((ref) {
  ref.watch(labsChangesProvider);
  return ref.watch(labsRepositoryProvider).consent;
});
final labsDataSourceProvider = Provider<LabsDataSource>(
  (ref) => LabsDataSource(
    ref.watch(appDatabaseProvider),
    ref.watch(nutritionRepositoryProvider),
    ref.watch(labsRepositoryProvider),
  ),
);
final labsPdfProvider = Provider<LabsPdfService>((ref) => LabsPdfService());
final labsSourceChangesProvider = StreamProvider<int>((ref) {
  if (!labsEnabled || !ref.watch(labsConsentProvider).enabled) {
    return const Stream.empty();
  }
  return ref
      .watch(appDatabaseProvider)
      .tableUpdates()
      .map((_) => DateTime.now().microsecondsSinceEpoch);
});
final labsSnapshotProvider = FutureProvider.family<LabsSnapshot, int>((
  ref,
  days,
) async {
  final consent = ref.watch(labsConsentProvider);
  final now = ref.watch(clockProvider).now();
  final period = LabsPeriod(
    DateTime(now.year, now.month, now.day - days + 1),
    DateTime(now.year, now.month, now.day + 1),
  );
  if (!labsEnabled || !consent.enabled) {
    return LabsSnapshot(period: period, generatedAt: now, findings: const []);
  }
  ref.watch(labsRevisionProvider);
  ref.watch(labsSourceChangesProvider);
  if (consent.allows(LabsCategory.supplements)) {
    ref.watch(takenTodayProvider);
    ref.watch(supplementsProvider);
  }
  final repo = ref.watch(labsRepositoryProvider);
  final observations = await ref.watch(labsDataSourceProvider).load(now);
  final findings = await compute(_analyze, (
    observations,
    period,
    consent.categories,
  ));
  final latest = repo.consent;
  final dietEvents = latest.allows(LabsCategory.nutrition)
      ? repo
            .records('event')
            .where(
              (e) =>
                  latest.history ||
                  !DateTime.parse(
                    e['at'],
                  ).isBefore(labsDay(latest.since ?? now)),
            )
            .toList()
      : <Map<String, dynamic>>[];
  findings.addAll(LabsDietEvaluator.evaluate(dietEvents, observations, period));
  return LabsSnapshot(
    period: period,
    generatedAt: now,
    findings: latest.enabled
        ? findings.where((f) => latest.categories.contains(f.category)).toList()
        : [],
    events: _allowedRecords(repo, 'event', latest, period),
    experiments: _allowedRecords(repo, 'experiment', latest, period)
        .map((e) => LabsExperimentEvaluator.evaluate(e, observations, now))
        .toList(),
  );
});
List<LabsFinding> _analyze(
  (List<LabsObservation>, LabsPeriod, Set<LabsCategory>) args,
) => LabsEngine.analyze(args.$1, args.$2, args.$3);
List<Map<String, dynamic>> _allowedRecords(
  LabsRepository repo,
  String kind,
  LabsConsent consent,
  LabsPeriod period,
) {
  if (!consent.enabled) {
    return [];
  }
  final records = [...repo.records(kind)];
  if (kind == 'event' && consent.allows(LabsCategory.supplements)) {
    for (final definition in repo.records('definitions')) {
      final before = {for (final p in definition['before'] as List) p['id']: p};
      final after = {for (final p in definition['after'] as List) p['id']: p};
      for (final id in {...before.keys, ...after.keys}) {
        final a = before[id], b = after[id];
        if (jsonEncode(a) == jsonEncode(b)) continue;
        records.add({
          'at': definition['at'],
          'category': 'supplements',
          'title': b == null
              ? '${a['name']}: removed from tracker'
              : a == null
              ? '${b['name']}: added to tracker'
              : '${b['name']}: updated tracked dose / product',
          'details': {'before': a, 'after': b},
        });
      }
    }
  }
  records.sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
  return records.where((r) {
    final at = DateTime.tryParse(r['at'] ?? '');
    if (at == null || !at.isBefore(period.end)) {
      return false;
    }
    if (!consent.history && at.isBefore(consent.since ?? period.start)) {
      return false;
    }
    if (kind == 'event') {
      return period.contains(at) &&
          consent.categories.any((c) => c.name == r['category']);
    }
    return (r['categories'] as List? ?? []).every(
      (c) => consent.categories.any((v) => v.name == c),
    );
  }).toList();
}

final labsReportRunnerProvider = Provider<LabsReportRunner>(
  (ref) => LabsReportRunner(
    ref.watch(labsRepositoryProvider),
    ref.watch(labsDataSourceProvider),
    ref.watch(labsPdfProvider),
  ),
);

class LabsReportRunner {
  LabsReportRunner(this.repo, this.source, this.pdf);
  final LabsRepository repo;
  final LabsDataSource source;
  final LabsPdfService pdf;
  Future<void>? _running;
  Future<void> catchUp(DateTime now) =>
      _running ??= _catchUp(now).whenComplete(() => _running = null);
  Future<void> _catchUp(DateTime now) async {
    final consent = repo.consent;
    if (!labsEnabled || !consent.enabled || consent.since == null) {
      return;
    }
    final token = jsonEncode(consent.toJson());
    final epoch = repo.privacyEpoch;
    for (final period in LabsPeriod.due(consent.since!, now)) {
      final from = DateTime(
        period.end.year,
        period.end.month,
        period.end.day - 180,
      );
      final observations = await source.load(
        period.end,
        start: consent.history ? from : consent.since,
      );
      final findings = await compute(_analyze, (
        observations,
        period,
        consent.categories,
      ));
      if (jsonEncode(repo.consent.toJson()) != token ||
          repo.privacyEpoch != epoch) {
        return;
      }
      if (consent.allows(LabsCategory.nutrition)) {
        findings.addAll(
          LabsDietEvaluator.evaluate(
            repo
                .records('event')
                .where(
                  (e) =>
                      consent.history ||
                      !DateTime.parse(
                        e['at'],
                      ).isBefore(labsDay(consent.since!)),
                )
                .toList(),
            observations,
            period,
          ),
        );
      }
      final previous =
          repo
              .records('report')
              .where((r) => r['start'] == period.start.toIso8601String())
              .map(LabsSnapshot.fromJson)
              .toList()
            ..sort((a, b) => a.revision.compareTo(b.revision));
      final snapshot = LabsSnapshot(
        period: period,
        generatedAt: now,
        findings: findings,
        revision: previous.isEmpty ? 1 : previous.last.revision + 1,
        partial: consent.since!.isAfter(period.start),
        events: _allowedRecords(repo, 'event', consent, period),
        experiments: _allowedRecords(repo, 'experiment', consent, period)
            .map(
              (e) =>
                  LabsExperimentEvaluator.evaluate(e, observations, period.end),
            )
            .toList(),
      );
      if (previous.isNotEmpty &&
          previous.last.fingerprint == snapshot.fingerprint) {
        continue;
      }
      final file = await pdf.save(snapshot);
      if (jsonEncode(repo.consent.toJson()) != token ||
          repo.privacyEpoch != epoch) {
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }
      await repo.put(
        'report',
        '${period.id}_${snapshot.revision}',
        snapshot.toJson(),
      );
    }
  }
}

final labsLifecycleProvider = Provider<void>((ref) {
  if (!labsEnabled) {
    return;
  }
  if (!ref.watch(labsConsentProvider).enabled) {
    return;
  }
  final runner = ref.watch(labsReportRunnerProvider);
  void refresh() {
    ref.read(labsRevisionProvider.notifier).state++;
    unawaited(
      runner.catchUp(ref.read(clockProvider).now()).catchError((
        Object e,
        StackTrace s,
      ) {
        debugPrint(
          'Labs report generation will retry on resume: ${e.runtimeType}',
        );
      }),
    );
  }

  final listener = AppLifecycleListener(onResume: refresh);
  final timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  Future.microtask(refresh);
  ref.onDispose(() {
    listener.dispose();
    timer.cancel();
  });
});
final labsAiProvider = Provider<LabsAiService>((ref) {
  final backend = ref.watch(geminiBackendProvider);
  return LabsAiService(
    backend is SupabaseGeminiBackend ? GeminiLabsAiBackend(backend) : null,
  );
});
