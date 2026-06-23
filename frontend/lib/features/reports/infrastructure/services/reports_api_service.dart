import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../domain/entities/attendance_report.dart';
import '../../domain/entities/qr_generation_map_record.dart';

class ReportsApiService {
  const ReportsApiService(this._apiClient);

  final BackendApiClient _apiClient;

  Future<AttendanceReport> fetchByCi({
    required String ci,
    required AttendanceReportFilter filter,
  }) async {
    final estado = switch (filter) {
      AttendanceReportFilter.all => 'TODOS',
      AttendanceReportFilter.attended => 'ASISTIO',
      AttendanceReportFilter.observed => 'OBSERVADO',
    };

    final payload = await _apiClient.getJson(
      '/api/reportes/asistencias?ci=${Uri.encodeQueryComponent(ci)}&estado=$estado',
    );
    final data = _readMap(payload['data'], 'reporte');
    final person = _readMap(data['person'], 'person');
    final records = _readList(data['records'], 'records');

    return AttendanceReport(
      person: AttendanceReportPerson(
        id: _readInt(person['id'], 'person.id'),
        personaId: _readNullableInt(person['personaId']),
        userId: _readNullableInt(person['usuarioId']),
        ci: _readString(person['ci'], 'person.ci'),
        fullName: _readString(
          person['nombreCompleto'],
          'person.nombreCompleto',
        ),
        officeName:
            _readNullableString(person['oficina']) ??
            _readNullableString(person['unidad']),
        jobTitle: _readNullableString(person['cargo']),
        tipoVinculo: _readNullableString(person['tipoVinculo']),
        numeroItem: _readNullableString(person['numeroItem']),
        email: _readNullableString(person['email']),
        photoUrl:
            _readNullableString(person['fotoUrl']) ??
            _readNullableString(person['fotoBase64']),
        qrCode: _readNullableString(person['codigoQr']),
        isActive: person['activo'] as bool? ?? true,
      ),
      records: records
          .map(
            (source) => AttendanceReportRecord(
              id: _readInt(source['id'], 'record.id'),
              personId: _readInt(source['personaId'], 'record.personaId'),
              ci: _readString(source['ci'], 'record.ci'),
              fullName: _readString(
                source['nombreCompleto'],
                'record.nombreCompleto',
              ),
              officeName:
                  _readNullableString(source['oficina']) ??
                  _readNullableString(source['unidad']),
              eventId: _readInt(source['eventoId'], 'record.eventoId'),
              eventName: _readString(
                source['eventoNombre'],
                'record.eventoNombre',
              ),
              eventDate: DateTime.parse(
                _readString(source['eventoFecha'], 'record.eventoFecha'),
              ).toLocal(),
              registeredAt: DateTime.parse(
                _readString(source['registradoEn'], 'record.registradoEn'),
              ).toLocal(),
              status: _readString(source['estado'], 'record.estado'),
              registeredControlsCount:
                  _readNullableInt(source['controlesRegistrados']) ?? 0,
              attendedControlsCount:
                  _readNullableInt(source['controlesAsistidos']) ?? 0,
              observedControlsCount:
                  _readNullableInt(source['controlesObservados']) ?? 0,
              eventAddress: _readNullableString(source['eventoDireccion']),
              note: _readNullableString(source['observacion']),
            ),
          )
          .toList(growable: false),
      filter: filter,
    );
  }

  Future<List<QrGenerationMapRecord>> fetchQrGenerationRecords({
    required String requesterEmail,
    required QrGenerationMapFilter filterBy,
    required QrGenerationMapSource source,
    required DateTime generatedFrom,
    required DateTime generatedTo,
    int? eventId,
    int? controlId,
    String query = '',
  }) async {
    final normalizedFrom = DateTime(
      generatedFrom.year,
      generatedFrom.month,
      generatedFrom.day,
    );
    final normalizedTo = DateTime(
      generatedTo.year,
      generatedTo.month,
      generatedTo.day,
      23,
      59,
      59,
      999,
    );
    final payload = await _apiClient.getJson(
      '/api/reportes/qr-generaciones'
      '?requesterEmail=${Uri.encodeQueryComponent(requesterEmail)}'
      '&scope=${Uri.encodeQueryComponent(source.apiValue)}'
      '&filterBy=${Uri.encodeQueryComponent(filterBy.apiValue)}'
      '&generatedFrom=${Uri.encodeQueryComponent(normalizedFrom.toIso8601String())}'
      '&generatedTo=${Uri.encodeQueryComponent(normalizedTo.toIso8601String())}'
      '${eventId == null ? '' : '&eventId=$eventId'}'
      '${controlId == null ? '' : '&controlId=$controlId'}'
      '&query=${Uri.encodeQueryComponent(query.trim())}',
    );
    final data = _readMap(payload['data'], 'mapaQr');
    final records = _readList(data['records'], 'records');

    return records
        .map(
          (source) => QrGenerationMapRecord(
            id: _readString(source['id'], 'record.id'),
            source: _parseQrGenerationMapSource(
              _readString(source['source'], 'record.source'),
            ),
            personaId: _readInt(source['personaId'], 'record.personaId'),
            userId: _readNullableInt(source['usuarioId']),
            fullName: _readString(
              source['nombreCompleto'],
              'record.nombreCompleto',
            ),
            ci: _readString(source['ci'], 'record.ci'),
            email: _readNullableString(source['email']),
            officeName: _readNullableString(source['oficina']),
            qrCode: _readNullableString(source['codigoQr']),
            latitude: _readDouble(source['latitud'], 'record.latitud'),
            longitude: _readDouble(source['longitud'], 'record.longitud'),
            accuracy: _readNullableDouble(source['accuracy']),
            generatedAt: DateTime.parse(
              _readString(source['generatedAt'], 'record.generatedAt'),
            ).toLocal(),
            expiresAt: _readNullableString(source['expiresAt']) == null
                ? null
                : DateTime.parse(
                    _readString(source['expiresAt'], 'record.expiresAt'),
                  ).toLocal(),
            eventId: _readNullableInt(source['eventoId']),
            eventName: _readNullableString(source['eventoNombre']),
            controlId: _readNullableInt(source['controlId']),
            controlName: _readNullableString(source['controlNombre']),
            status: _readNullableString(source['estado']),
            note: _readNullableString(source['observacion']),
            registrationSource: _readNullableString(
              source['registrationSource'],
            ),
          ),
        )
        .toList(growable: false);
  }
}

QrGenerationMapSource _parseQrGenerationMapSource(String source) {
  switch (source.toUpperCase()) {
    case 'EVENTO':
      return QrGenerationMapSource.eventScans;
    case 'GENERACION':
      return QrGenerationMapSource.qrGenerations;
    default:
      throw StateError('El origen del punto del mapa no es valido.');
  }
}

Map<String, dynamic> _readMap(dynamic source, String fieldName) {
  if (source is! Map<String, dynamic>) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}

List<Map<String, dynamic>> _readList(dynamic source, String fieldName) {
  if (source is! List) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source
      .map((item) => _readMap(item, fieldName))
      .toList(growable: false);
}

String _readString(dynamic source, String fieldName) {
  if (source is! String) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}

String? _readNullableString(dynamic source) {
  if (source == null) {
    return null;
  }

  if (source is! String) {
    throw StateError('Se esperaba un valor de texto.');
  }

  return source;
}

int _readInt(dynamic source, String fieldName) {
  if (source is! int) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}

int? _readNullableInt(dynamic source) {
  if (source == null) {
    return null;
  }

  if (source is! int) {
    throw StateError('Se esperaba un valor numerico.');
  }

  return source;
}

double _readDouble(dynamic source, String fieldName) {
  if (source is int) {
    return source.toDouble();
  }

  if (source is double) {
    return source;
  }

  throw StateError('El campo $fieldName no tiene un formato valido.');
}

double? _readNullableDouble(dynamic source) {
  if (source == null) {
    return null;
  }

  if (source is int) {
    return source.toDouble();
  }

  if (source is double) {
    return source;
  }

  throw StateError('Se esperaba un valor numerico.');
}
