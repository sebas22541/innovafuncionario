import 'dart:convert';

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
    // valor crudo de camara -> lookupCode estable -> backend -> detalle de persona.
    final lookupCode = _extractLookupCode(scannedValue);

    if (lookupCode == null || lookupCode.isEmpty) {
      return null;
    }

    final result = await _dataSource.getByLookupCode(
      lookupCode,
      eventId: eventId,
    );
    return result?.toEntity();
  }

  String? _extractLookupCode(String scannedValue) {
    // Prioridad de extraccion:
    // 1. JSON del QR emitido por la app.
    // 2. URL con query params o ultimo segmento del path.
    // 3. Texto crudo, en mayusculas, para compatibilidad.
    final trimmedValue = scannedValue.trim();

    if (trimmedValue.isEmpty) {
      return null;
    }

    final qrPayload = _tryParseQrPayload(trimmedValue);

    if (qrPayload != null) {
      const payloadLookupKeys = [
        'codigoQr',
        'qrCode',
        'codigo_qr',
        'code',
        'id',
        'qr',
        'slug',
        'token',
      ];

      for (final key in payloadLookupKeys) {
        final value = qrPayload[key];

        if (value is String && value.trim().isNotEmpty) {
          return value.trim().toUpperCase();
        }
      }
    }

    final uri = Uri.tryParse(trimmedValue);

    if (uri == null) {
      return trimmedValue.toUpperCase();
    }

    const lookupKeys = ['code', 'id', 'qr', 'slug', 'token'];

    for (final key in lookupKeys) {
      final value = uri.queryParameters[key]?.trim();

      if (value != null && value.isNotEmpty) {
        return value.toUpperCase();
      }
    }

    if (uri.pathSegments.isNotEmpty) {
      final lastSegment = uri.pathSegments.last.trim();

      if (lastSegment.isNotEmpty) {
        return lastSegment.toUpperCase();
      }
    }

    return trimmedValue.toUpperCase();
  }

  Map<String, dynamic>? _tryParseQrPayload(String scannedValue) {
    try {
      final parsedValue = jsonDecode(scannedValue);

      if (parsedValue is Map<String, dynamic>) {
        return parsedValue;
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
