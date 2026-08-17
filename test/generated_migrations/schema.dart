// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';
import 'package:drift/internal/migrations.dart';
import 'schema_v23.dart' as v23;
import 'schema_v24.dart' as v24;
import 'schema_v25.dart' as v25;
import 'schema_v26.dart' as v26;
import 'schema_v27.dart' as v27;
import 'schema_v28.dart' as v28;

class GeneratedHelper implements SchemaInstantiationHelper {
  @override
  GeneratedDatabase databaseForVersion(QueryExecutor db, int version) {
    switch (version) {
      case 23:
        return v23.DatabaseAtV23(db);
      case 24:
        return v24.DatabaseAtV24(db);
      case 25:
        return v25.DatabaseAtV25(db);
      case 26:
        return v26.DatabaseAtV26(db);
      case 27:
        return v27.DatabaseAtV27(db);
      case 28:
        return v28.DatabaseAtV28(db);
      default:
        throw MissingSchemaException(version, versions);
    }
  }

  static const versions = const [23, 24, 25, 26, 27, 28];
}
