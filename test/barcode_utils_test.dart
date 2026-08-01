import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/barcode_utils.dart';

void main() {
  group('normalizeBarcode', () {
    test('accepts EAN-8, UPC-A, EAN-13 and GTIN-14', () {
      expect(normalizeBarcode('96385074')?.format, RetailBarcodeFormat.ean8);
      expect(
        normalizeBarcode('036000291452')?.format,
        RetailBarcodeFormat.upcA,
      );
      expect(
        normalizeBarcode('4006381333931')?.format,
        RetailBarcodeFormat.ean13,
      );
      expect(
        normalizeBarcode('00012345600012')?.format,
        RetailBarcodeFormat.gtin14,
      );
    });

    test('strips scanner separators but preserves leading zeroes', () {
      final result = normalizeBarcode('0-36000-29145-2');
      expect(result?.value, '036000291452');
      expect(result?.lookupCandidates, ['036000291452', '0036000291452']);
    });

    test('rejects unsupported length, non-digits and bad check digit', () {
      expect(normalizeBarcode('1234567890'), isNull);
      expect(normalizeBarcode('123456789013'), isNull);
      expect(normalizeBarcode('400638133393A'), isNull);
    });

    test('does not infer product origin from the prefix', () {
      final result = normalizeBarcode('4006381333931');
      expect(result?.value, '4006381333931');
      expect(result?.format, RetailBarcodeFormat.ean13);
    });
  });
}
