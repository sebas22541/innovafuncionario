class QrScanResult {
  const QrScanResult({
    required this.value,
    required this.displayValue,
    required this.format,
    required this.payloadType,
    required this.payloadFields,
    required this.scannedAt,
  });

  final String value;
  final String displayValue;
  final String format;
  final String payloadType;
  final Map<String, String> payloadFields;
  final DateTime scannedAt;
}
