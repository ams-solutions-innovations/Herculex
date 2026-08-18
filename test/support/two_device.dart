import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';

import 'test_database.dart';

/// Two independent in-memory [AppDatabase] instances in one test process —
/// extracted from `test/sync/sync_payload_test.dart`'s "second device, same
/// account, same fake cloud" idiom so buddy tests (and any future
/// two-device test) do not have to copy-paste it a third time.
class TwoDevices {
  TwoDevices({required this.deviceA, required this.deviceB});

  final AppDatabase deviceA;
  final AppDatabase deviceB;

  Future<void> close() async {
    await deviceA.close();
    await deviceB.close();
  }
}

/// Opens two independent in-memory [AppDatabase]s for a two-device test.
///
/// Drift's "multiple databases" warning exists for the case where two
/// database instances share one `QueryExecutor`; these two have separate
/// in-memory executors, which is the whole point of simulating two
/// devices — so the warning is suppressed here once, rather than at every
/// call site that needs a second database.
Future<TwoDevices> openTwoDevices() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final deviceA = await openTestDatabase();
  final deviceB = await openTestDatabase();
  return TwoDevices(deviceA: deviceA, deviceB: deviceB);
}
