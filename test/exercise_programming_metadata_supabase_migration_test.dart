import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v40 Supabase migration mirrors programming metadata columns', () {
    const path =
        'supabase/migrations/20260910100000_exercise_programming_metadata_v40.sql';
    final file = File(path);
    expect(file.existsSync(), isTrue);
    final sql = file.readAsStringSync().toLowerCase();

    for (final field in [
      'programming_difficulty',
      'programming_commonness',
      'allowed_training_styles',
      'technical_eligibility',
    ]) {
      expect(sql, contains(field));
    }
    expect(sql, contains("default 'advanced'"));
    expect(sql, contains("default 'specialty'"));
    expect(sql, contains("default '[]'"));
    expect(sql, contains("default 'manual_only'"));
    expect(sql, contains('technical_review'));
  });

  test('v41 Supabase migration mirrors programming metadata, disciplines, and scaling columns', () {
    const path =
        'supabase/migrations/20260913000000_exercise_programming_metadata_v41.sql';
    final file = File(path);
    expect(file.existsSync(), isTrue);
    final sql = file.readAsStringSync().toLowerCase();

    for (final field in [
      'disciplines',
      'prerequisite_slugs',
      'scaling_group',
      'scaling_order',
      'competition_anchor',
      'specialization_tags',
    ]) {
      expect(sql, contains(field));
    }
    expect(sql, contains("default 'manualonly'"));
    expect(sql, contains("check (programming_commonness in ('basic', 'common', 'specialty', 'manualonly'))"));
    expect(sql, contains('create index if not exists idx_exercise_catalog_scaling'));
  });
}

