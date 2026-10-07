import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

void main() {
  group('SlotPrescriptionCodec', () {
    test('round-trips a built-in prescription with meta and setType', () {
      final myo = SlotPrescription.builtIns.firstWhere(
        (p) => p.name == 'Myo 1+3',
      );

      final decoded = SlotPrescriptionCodec.decode(
        SlotPrescriptionCodec.encode(myo),
      );

      expect(decoded, isNotNull);
      expect(decoded!.name, myo.name);
      expect(decoded.note, myo.note);
      expect(decoded.segments.length, myo.segments.length);
      for (var i = 0; i < myo.segments.length; i++) {
        final original = myo.segments[i];
        final round = decoded.segments[i];
        expect(round.sets, original.sets);
        expect(round.repsMin, original.repsMin);
        expect(round.repsMax, original.repsMax);
        expect(round.intent, original.intent);
        expect(round.percentOf1Rm, original.percentOf1Rm);
        expect(round.setType, original.setType);
        expect(round.restSeconds, original.restSeconds);
        expect(round.meta, original.meta);
      }
    });

    test('round-trips a hand-built ramp-to-max prescription', () {
      const p = SlotPrescription(
        name: 'Custom ramp',
        note: 'Work up heavy',
        segments: [
          WorkSegment(
            sets: 1,
            repsMin: 1,
            repsMax: 3,
            intent: Intent.rampToMax,
            percentOf1Rm: null,
            restSeconds: 300,
          ),
        ],
      );

      final decoded = SlotPrescriptionCodec.decode(
        SlotPrescriptionCodec.encode(p),
      );

      expect(decoded, isNotNull);
      expect(decoded!.name, p.name);
      expect(decoded.note, p.note);
      expect(decoded.segments.single.sets, p.segments.single.sets);
      expect(decoded.segments.single.repsMin, p.segments.single.repsMin);
      expect(decoded.segments.single.repsMax, p.segments.single.repsMax);
      expect(decoded.segments.single.intent, Intent.rampToMax);
      expect(decoded.segments.single.percentOf1Rm, isNull);
      expect(decoded.segments.single.setType, SetType.standard);
      expect(
        decoded.segments.single.restSeconds,
        p.segments.single.restSeconds,
      );
      expect(decoded.segments.single.meta, isEmpty);
    });

    test('decode(null) returns null', () {
      expect(SlotPrescriptionCodec.decode(null), isNull);
    });

    test('decode empty string returns null', () {
      expect(SlotPrescriptionCodec.decode(''), isNull);
    });

    test('decode invalid json returns null instead of throwing', () {
      expect(SlotPrescriptionCodec.decode('not json'), isNull);
    });

    test('decode with mismatched codecVersion returns null', () {
      final raw = jsonEncode({'codecVersion': 99, 'name': 'x', 'segments': []});
      expect(SlotPrescriptionCodec.decode(raw), isNull);
    });
  });
}
