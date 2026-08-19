import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/reps/data/fixture_recorder.dart';
import 'package:herculex/features/reps/domain/motion_sample.dart';
import 'package:herculex/features/reps/domain/rep_movement.dart';

void main() {
  late Directory tempDir;
  late FixtureRecorder recorder;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fixture_recorder_test_');
    recorder = FixtureRecorder(baseDirOverride: () => tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final trace = MotionTrace(
    samples: const [
      MotionSample(0, 1.0, 2.0, 3.0),
      MotionSample(20, 1.1, 2.1, 3.1),
      MotionSample(40, 1.2, 2.2, 3.2),
    ],
    sensorType: MotionSensorType.linearAcceleration,
  );

  test('save then listRecorded round-trips a fixture name', () async {
    await recorder.save(
      'pullup_wrist_clean_8reps',
      trace,
      repCount: 8,
      movement: RepMovement.verticalPull,
      source: 'wrist',
      description: 'clean baseline set',
      recordedBy: 'tester',
      deviceModel: 'Galaxy Watch 6 SM-R930',
    );

    final recorded = await recorder.listRecorded();
    expect(recorded, contains('pullup_wrist_clean_8reps'));
  });

  test('the written sidecar has all ten keys and synthetic is always false', () async {
    await recorder.save(
      'dip_wrist_clean_12reps',
      trace,
      repCount: 12,
      movement: RepMovement.bodyweightPush,
      source: 'wrist',
      description: 'baseline dips',
      recordedBy: 'tester',
      deviceModel: 'Pixel Watch 3',
    );

    final dir = await recorder.fixturesDir();
    final jsonFile = File('${dir.path}/dip_wrist_clean_12reps.json');
    final sidecar = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;

    const expectedKeys = {
      'repCount',
      'movement',
      'source',
      'placement',
      'sensorType',
      'description',
      'recordedBy',
      'recordedAt',
      'deviceModel',
      'synthetic',
    };
    expect(sidecar.keys.toSet(), expectedKeys);
    expect(sidecar['synthetic'], isFalse);
    expect(sidecar['repCount'], 12);
    expect(sidecar['movement'], 'bodyweightPush');
  });

  test('the written csv has one line per sample in t_ms,x,y,z order', () async {
    await recorder.save(
      'noise_walking_60s_0reps',
      trace,
      repCount: 0,
      movement: null,
      source: 'wrist',
      description: 'walking noise',
      recordedBy: 'tester',
      deviceModel: 'Galaxy Watch 6 SM-R930',
    );

    final dir = await recorder.fixturesDir();
    final csvFile = File('${dir.path}/noise_walking_60s_0reps.csv');
    final lines = (await csvFile.readAsString())
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    // Header + 3 sample rows.
    expect(lines.first, 't_ms,x,y,z');
    expect(lines.length, 1 + trace.samples.length);
    expect(lines[1].split(',').first, '0');
    expect(lines[2].split(',').first, '20');
    expect(lines[3].split(',').first, '40');
  });

  test('an interrupted save (csv without json) does not appear in listRecorded', () async {
    final dir = await recorder.fixturesDir();
    final orphanCsv = File('${dir.path}/pullup_wrist_interrupted_6reps.csv');
    await orphanCsv.writeAsString(trace.toCsv());

    final recorded = await recorder.listRecorded();
    expect(recorded, isNot(contains('pullup_wrist_interrupted_6reps')));
  });
}
