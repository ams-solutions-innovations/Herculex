import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingAiScanService', () {
    late SharedPreferences prefs;
    late PendingAiScanService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = PendingAiScanService(prefs);
    });

    test('a stored legacy supplement scan context falls back to food', () async {
      SharedPreferences.setMockInitialValues({
        'herculex_pending_ai_scan_context':
            '{"type":"supplement","createdAt":"${DateTime.now().toIso8601String()}"}',
      });
      prefs = await SharedPreferences.getInstance();
      service = PendingAiScanService(prefs);

      final retrieved = service.getPendingContext();

      expect(retrieved, isNotNull);
      expect(retrieved!.type, equals(AiScanContextType.food));
    });

    test('stores and retrieves food scan context with meal and date', () async {
      final now = DateTime.now();
      final context = PendingAiScanContext(
        type: AiScanContextType.food,
        mealKey: 'lunch',
        dateIso: now.toIso8601String(),
        extra: {'barcode': '123456789'},
      );

      await service.setPendingContext(context);
      final retrieved = service.getPendingContext();

      expect(retrieved, isNotNull);
      expect(retrieved!.type, equals(AiScanContextType.food));
      expect(retrieved.mealKey, equals('lunch'));
      expect(retrieved.dateIso, equals(now.toIso8601String()));
      expect(retrieved.extra?['barcode'], equals('123456789'));
    });

    test('clears pending context', () async {
      final context = PendingAiScanContext(type: AiScanContextType.exercise);

      await service.setPendingContext(context);
      expect(service.getPendingContext(), isNotNull);

      await service.clearPendingContext();
      expect(service.getPendingContext(), isNull);
    });

    test('ignores expired context older than 1 hour', () async {
      final oldTime = DateTime.now().subtract(const Duration(hours: 2));
      final context = PendingAiScanContext(
        type: AiScanContextType.bodyFat,
        createdAt: oldTime,
      );

      await service.setPendingContext(context);
      expect(context.isExpired, isTrue);

      final retrieved = service.getPendingContext();
      expect(retrieved, isNull);
    });
  });
}
