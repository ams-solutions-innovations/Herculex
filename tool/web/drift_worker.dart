// Entry point for web/drift_worker.js — the worker drift runs the wasm
// sqlite3 database in. Compiled by tool/web/fetch_web_assets.ps1 so it always
// matches the drift version in pubspec.lock.
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
