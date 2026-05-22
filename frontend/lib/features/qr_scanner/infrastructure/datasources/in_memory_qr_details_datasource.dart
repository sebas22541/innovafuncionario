import '../models/qr_details_model.dart';
import 'qr_details_datasource.dart';

class InMemoryQrDetailsDataSource implements QrDetailsDataSource {
  InMemoryQrDetailsDataSource();

  final Map<String, Map<String, dynamic>> _records = {
    'ALCALDIA-QR-001': {
      'id': '1',
      'code': 'ALCALDIA-QR-001',
      'title': 'Punto de informacion principal',
      'description':
          'Registro base de ejemplo para pruebas de lectura y consulta.',
      'status': 'active',
      'fields': {
        'categoria': 'informacion',
        'ubicacion': 'Plaza principal',
        'responsable': 'Direccion de turismo',
      },
      'updatedAt': '2026-05-10T18:20:00.000',
    },
    'TURISMO-PLAZA-001': {
      'id': '2',
      'code': 'TURISMO-PLAZA-001',
      'title': 'Plaza central',
      'description':
          'Ficha temporal preparada para conectar luego con base de datos.',
      'status': 'active',
      'fields': {
        'categoria': 'turismo',
        'horario': '08:00 - 20:00',
        'idioma': 'es',
      },
      'updatedAt': '2026-05-10T18:25:00.000',
    },
    'EVENTO-2026-001': {
      'id': '3',
      'code': 'EVENTO-2026-001',
      'title': 'Evento municipal',
      'description':
          'Ejemplo de contenido para validar la consulta posterior al escaneo.',
      'status': 'draft',
      'fields': {
        'categoria': 'evento',
        'fecha': '2026-06-01',
        'zona': 'Centro',
      },
      'updatedAt': '2026-05-10T18:30:00.000',
    },
  };

  @override
  Future<QrDetailsModel?> getByLookupCode(
    String lookupCode, {
    int? eventId,
  }) async {
    final normalizedCode = lookupCode.trim().toUpperCase();
    final record = _records[normalizedCode];

    if (record == null) {
      return null;
    }

    return QrDetailsModel.fromMap(record);
  }

  @override
  Future<QrDetailsModel?> getByCi(String ci, {int? eventId}) async {
    return null;
  }
}
