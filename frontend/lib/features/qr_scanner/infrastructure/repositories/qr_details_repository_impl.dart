import '../../domain/entities/qr_details.dart';
import '../../domain/repositories/qr_details_repository.dart';
import '../datasources/qr_details_datasource.dart';

class QrDetailsRepositoryImpl implements QrDetailsRepository {
  const QrDetailsRepositoryImpl(this._dataSource);

  final QrDetailsDataSource _dataSource;

  @override
  Future<QrDetails?> getByScannedValue(
    String scannedValue, {
    int? eventId,
  }) async {
    // Flujo de consulta al escanear:
    // valor crudo de camara -> backend valida el tipo de QR y resuelve la persona.
    // Se conserva la URL completa para reconocer los QRs de credenciales impresas.
    final rawQrValue = scannedValue.trim();

    if (rawQrValue.isEmpty) {
      return null;
    }

    final result = await _dataSource.getByLookupCode(
      rawQrValue,
      eventId: eventId,
    );
    return result?.toEntity();
  }
}
