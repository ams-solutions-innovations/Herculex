import 'package:flutter_test/flutter_test.dart';

import 'support/test_database.dart';

void main() {
  test('HerculRuleImporter seeds the database correctly', () async {
    final db = await openTestDatabase();

    // Test that the database has rules imported from asset on creation
    final rules = await db.select(db.herculRules).get();

    expect(rules, isNotEmpty);
    expect(rules.length, greaterThan(10));

    final sample = rules.first;
    expect(sample.id, isNotEmpty);
    expect(sample.copyNormal, isNotEmpty);
    expect(sample.copyHonest, isNotEmpty);

    await db.close();
  });
}
