/// Supported retail barcode symbologies used by the local food catalogue.
enum RetailBarcodeFormat { ean8, upcA, ean13, gtin14 }

class NormalizedBarcode {
  final String value;
  final RetailBarcodeFormat format;

  const NormalizedBarcode(this.value, this.format);

  /// Equivalent database representations that are safe to try locally.
  ///
  /// UPC-A is sometimes stored as an EAN-13 with a leading zero. This is a
  /// symbology conversion, not a country/origin inference.
  List<String> get lookupCandidates => switch (format) {
    RetailBarcodeFormat.upcA => [value, '0$value'],
    RetailBarcodeFormat.ean13 when value.startsWith('0') => [
      value,
      value.substring(1),
    ],
    _ => [value],
  };
}

/// Removes scanner formatting and validates retail check digits.
///
/// Country prefixes are intentionally treated as opaque identifier digits;
/// this function never uses them to infer where a product was made.
NormalizedBarcode? normalizeBarcode(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;

  final format = switch (digits.length) {
    8 => RetailBarcodeFormat.ean8,
    12 => RetailBarcodeFormat.upcA,
    13 => RetailBarcodeFormat.ean13,
    14 => RetailBarcodeFormat.gtin14,
    _ => null,
  };
  if (format == null || !_hasValidCheckDigit(digits)) return null;
  return NormalizedBarcode(digits, format);
}

bool _hasValidCheckDigit(String digits) {
  var sum = 0;
  var weight = 3;
  for (var i = digits.length - 2; i >= 0; i--) {
    sum += int.parse(digits[i]) * weight;
    weight = weight == 3 ? 1 : 3;
  }
  final expected = (10 - (sum % 10)) % 10;
  return expected == int.parse(digits[digits.length - 1]);
}
