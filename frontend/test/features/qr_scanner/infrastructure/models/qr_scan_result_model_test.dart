import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_asistencia_app/features/qr_scanner/infrastructure/models/qr_scan_result_model.dart';

void main() {
  test('parses url payload fields from barcode', () {
    const barcode = Barcode(
      rawValue: 'https://midominio.com/scan?code=ALCALDIA-QR-001&zona=centro',
      displayValue:
          'https://midominio.com/scan?code=ALCALDIA-QR-001&zona=centro',
      format: BarcodeFormat.qrCode,
    );

    final result = QrScanResultModel.fromBarcode(barcode);

    expect(result.payloadType, 'URL');
    expect(result.payloadFields['dominio'], 'midominio.com');
    expect(result.payloadFields['parametro.code'], 'ALCALDIA-QR-001');
    expect(result.payloadFields['parametro.zona'], 'centro');
  });

  test('parses json payload fields from barcode', () {
    const barcode = Barcode(
      rawValue: '{"id":"55","nombre":"Museo","activo":true}',
      displayValue: '{"id":"55","nombre":"Museo","activo":true}',
      format: BarcodeFormat.qrCode,
    );

    final result = QrScanResultModel.fromBarcode(barcode);

    expect(result.payloadType, 'JSON');
    expect(result.payloadFields['id'], '55');
    expect(result.payloadFields['nombre'], 'Museo');
    expect(result.payloadFields['activo'], 'true');
  });
}
