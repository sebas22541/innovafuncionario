import 'package:flutter_test/flutter_test.dart';
import 'package:qr_asistencia_app/features/qr_scanner/domain/usecases/get_qr_details_by_scan.dart';
import 'package:qr_asistencia_app/features/qr_scanner/infrastructure/datasources/in_memory_qr_details_datasource.dart';
import 'package:qr_asistencia_app/features/qr_scanner/infrastructure/repositories/qr_details_repository_impl.dart';

void main() {
  late GetQrDetailsByScan useCase;

  setUp(() {
    final repository = QrDetailsRepositoryImpl(InMemoryQrDetailsDataSource());
    useCase = GetQrDetailsByScan(repository);
  });

  test('returns qr details when scanned value is a direct code', () async {
    final result = await useCase('TURISMO-PLAZA-001');

    expect(result, isNotNull);
    expect(result?.code, 'TURISMO-PLAZA-001');
    expect(result?.title, 'Plaza central');
  });

  test('returns qr details when scanned value is a URL with code query', () async {
    final result = await useCase(
      'https://midominio.com/scan?code=ALCALDIA-QR-001',
    );

    expect(result, isNotNull);
    expect(result?.code, 'ALCALDIA-QR-001');
    expect(result?.fields['ubicacion'], 'Plaza principal');
  });

  test('returns null when no record is found', () async {
    final result = await useCase('QR-INEXISTENTE');

    expect(result, isNull);
  });
}
