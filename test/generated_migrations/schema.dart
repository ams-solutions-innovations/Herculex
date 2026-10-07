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
import 'schema_v29.dart' as v29;
import 'schema_v30.dart' as v30;
import 'schema_v31.dart' as v31;
import 'schema_v32.dart' as v32;
import 'schema_v34.dart' as v34;
import 'schema_v37.dart' as v37;
import 'schema_v38.dart' as v38;

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
      case 29:
        return v29.DatabaseAtV29(db);
      case 30:
        return v30.DatabaseAtV30(db);
      case 31:
        return v31.DatabaseAtV31(db);
      case 32:
        return v32.DatabaseAtV32(db);
      case 34:
        return v34.DatabaseAtV34(db);
      case 37:
        return v37.DatabaseAtV37(db);
      case 38:
        return v38.DatabaseAtV38(db);
      default:
        throw MissingSchemaException(version, versions);
    }
  }

  static const versions = const [
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    34,
    37,
    38,
  ];
}
