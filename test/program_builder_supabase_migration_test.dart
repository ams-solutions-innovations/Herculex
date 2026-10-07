import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path = 'supabase/migrations/20260908200007_program_builder_v39.sql';

  test(
    'v39 migration contains every synced planner table and owner policy',
    () {
      final file = File(path);
      expect(file.existsSync(), isTrue);
      final sql = file.readAsStringSync().toLowerCase();

      const tables = [
        'program_exercise_slots',
        'program_slot_pool_members',
        'exercise_preferences',
        'gym_equipment',
        'rotation_assignments',
        'prescription_templates',
        'physique_programming_profiles',
      ];
      for (final table in tables) {
        expect(sql, contains('create table public.$table'));
        expect(sql, contains("'$table'"));
      }

      expect(sql, contains('enable row level security'));
      expect(sql, contains('to authenticated'));
      expect(sql, contains('(select auth.uid()) = user_id'));
      expect(
        sql,
        contains('grant select, insert, update, delete on public.%i'),
      );
    },
  );

  test('v39 migration persists immutable workout prescription targets', () {
    final sql = File(path).readAsStringSync().toLowerCase();
    for (final field in [
      'planned_reps_min',
      'planned_reps_max',
      'planned_weight_kg',
      'planned_rpe_x10',
      'planned_rir',
      'planned_percent_of1_rm',
      'planned_intent',
      'planned_training_method',
      'planned_prescription_why',
      'rotation_assignment_id',
    ]) {
      expect(sql, contains(field));
    }
  });
}
