import '../../../../shared/infrastructure/backend_api_client.dart';
import '../models/qr_details_model.dart';
import 'qr_details_datasource.dart';

class ApiQrDetailsDataSource implements QrDetailsDataSource {
  const ApiQrDetailsDataSource(this._apiClient);

  final BackendApiClient _apiClient;

  @override
  Future<QrDetailsModel?> getByLookupCode(
    String lookupCode, {
    int? eventId,
  }) async {
    try {
      // El scanner nunca consulta por la imagen del QR.
      // Solo envia el lookupCode normalizado para que el backend resuelva la persona.
      final query = eventId == null ? '' : '?eventId=$eventId';
      final payload = await _apiClient.getJson(
        '/api/personas/qr/${Uri.encodeComponent(lookupCode)}$query',
      );
      return _parseDetailsPayload(payload['data'], fallbackCode: lookupCode);
    } on BackendApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  @override
  Future<QrDetailsModel?> getByCi(String ci, {int? eventId}) async {
    try {
      final query = eventId == null ? '' : '?eventId=$eventId';
      final payload = await _apiClient.getJson(
        '/api/personas/ci/${Uri.encodeComponent(ci)}$query',
      );
      return _parseDetailsPayload(payload['data'], fallbackCode: ci);
    } on BackendApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  QrDetailsModel _parseDetailsPayload(
    dynamic source, {
    required String fallbackCode,
  }) {
    if (source is! Map<String, dynamic>) {
      throw StateError('La persona recibida no tiene un formato valido.');
    }

    final unitName = source['unidad'] as String?;
    final jobTitle = source['cargo'] as String?;
    final tipoVinculo = source['tipoVinculo'] as String?;
    final officeId = source['oficinaId'] as int?;
    final officeName = source['oficinaNombre'] as String?;
    final officeCode = source['oficinaCodigo'] as String?;
    final cargoCodigo = source['cargoCodigo'] as String?;
    final updatedAt =
        (source['updatedAt'] as String?) ?? DateTime.now().toIso8601String();
    final eventAttendance = source['eventoRegistro'] as Map<String, dynamic>?;
    final eventPermission = source['eventoPermiso'] as Map<String, dynamic>?;
    final resolvedOfficeName = officeName ?? unitName;
    final firstName =
        (source['nombres'] as String?)?.trim() ??
        ((source['nombreCompleto'] as String?)?.trim() ?? 'Sin nombre');
    final lastNames = [
      (source['primerApellido'] as String?)?.trim(),
      (source['segundoApellido'] as String?)?.trim(),
      (source['tercerApellido'] as String?)?.trim(),
    ].where((value) => value != null && value.isNotEmpty).join(' ');
    final fields = <String, String>{
      'CI': (source['ci'] as String?) ?? 'Sin CI',
      'Nombre': firstName.isEmpty ? 'Sin nombre' : firstName,
      'Apellidos': lastNames.isEmpty ? 'Sin apellidos' : lastNames,
      'Oficina': resolvedOfficeName ?? 'Sin oficina',
      'Tipo vinculo': (tipoVinculo?.trim().isNotEmpty ?? false)
          ? tipoVinculo!.trim()
          : 'Sin tipo de vinculo',
      'Cargo': (jobTitle?.trim().isNotEmpty ?? false)
          ? jobTitle!.trim()
          : 'Sin cargo',
    };

    return QrDetailsModel(
      id: '${source['id']}',
      code: (source['codigoQr'] as String?) ?? fallbackCode,
      title: (source['nombreCompleto'] as String?) ?? 'Persona registrada',
      description:
          (source['descripcion'] as String?) ??
          'Persona registrada en la base de datos.',
      status: (source['activo'] as bool? ?? false) ? 'active' : 'inactive',
      fields: fields,
      updatedAt: DateTime.parse(updatedAt),
      officeId: officeId,
      officeName: resolvedOfficeName,
      officeCode: officeCode,
      cargoCodigo: cargoCodigo,
      photoUrl: (source['fotoUrl'] ?? source['fotoBase64']) as String?,
      canRegisterInActiveEvent: eventPermission?['permitido'] as bool?,
      eventRegistrationMessage: eventPermission?['mensaje'] as String?,
      eventAttendance: eventAttendance == null
          ? null
          : QrEventAttendanceRecordModel(
              status: (eventAttendance['estado'] as String?) ?? 'OBSERVADO',
              registeredAt: DateTime.parse(
                (eventAttendance['registradoEn'] as String?) ??
                    DateTime.now().toIso8601String(),
              ),
              registeredControlsCount:
                  eventAttendance['controlesRegistrados'] as int? ?? 0,
              attendedControlsCount:
                  eventAttendance['controlesAsistidos'] as int? ?? 0,
              observedControlsCount:
                  eventAttendance['controlesObservados'] as int? ?? 0,
              controls: ((eventAttendance['controles'] as List?) ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .map(
                    (control) => QrEventControlRecordModel(
                      id: control['id'] as int? ?? 0,
                      controlId: control['controlId'] as int? ?? 0,
                      controlName:
                          (control['controlNombre'] as String?) ?? 'Control',
                      controlOrder: control['controlOrden'] as int? ?? 0,
                      status: (control['estado'] as String?) ?? 'OBSERVADO',
                      registeredAt: DateTime.parse(
                        (control['registradoEn'] as String?) ??
                            DateTime.now().toIso8601String(),
                      ),
                      note: control['observacion'] as String?,
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}
