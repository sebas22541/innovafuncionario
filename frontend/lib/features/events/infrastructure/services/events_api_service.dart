import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../domain/entities/event_record.dart';

class EventsApiService {
  EventsApiService(this._apiClient);

  final BackendApiClient _apiClient;
  static const Duration _referenceCacheTtl = Duration(minutes: 5);
  static const Duration _eventSummaryCacheTtl = Duration(seconds: 20);
  List<EventOffice>? _officesCache;
  DateTime? _officesCacheAt;
  List<EventRecord>? _eventSummaryCache;
  DateTime? _eventSummaryCacheAt;

  Future<List<EventOffice>> fetchOffices({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheFresh(_officesCacheAt, _referenceCacheTtl)) {
      return _officesCache ?? const [];
    }

    final payload = await _apiClient.getJson('/api/oficinas');
    final items = _readList(payload['data'], 'oficinas');
    final offices = items.map(_parseOffice).toList(growable: false);
    _officesCache = offices;
    _officesCacheAt = DateTime.now();

    return offices;
  }

  Future<List<EventRecord>> fetchEvents({
    bool includeDetails = false,
    bool forceRefresh = false,
  }) async {
    if (!includeDetails &&
        !forceRefresh &&
        _isCacheFresh(_eventSummaryCacheAt, _eventSummaryCacheTtl)) {
      return _eventSummaryCache ?? const [];
    }

    final payload = await _apiClient.getJson(
      '/api/eventos?view=${includeDetails ? 'detail' : 'summary'}',
    );
    final items = _readList(payload['data'], 'eventos');
    final events = items.map(_parseEvent).toList(growable: false);

    if (!includeDetails) {
      _eventSummaryCache = events;
      _eventSummaryCacheAt = DateTime.now();
    }

    return events;
  }

  Future<EventRecord> fetchEventById(int eventId) async {
    final payload = await _apiClient.getJson('/api/eventos/$eventId');
    return _parseEvent(_readMap(payload['data'], 'evento'));
  }

  Future<EventRecord> createEvent({
    required EventRecordDraft draft,
    required String creatorEmail,
    required String creatorFullName,
  }) async {
    final payload = await _apiClient.postJson('/api/eventos', {
      'nombre': draft.name,
      'fechaEvento': _formatDateForApi(draft.date),
      'direccion': draft.address,
      'latitud': draft.latitude,
      'longitud': draft.longitude,
      'oficinaIds': draft.officeIds,
      'oficinaIdsExcluidos': draft.excludedOfficeIds,
      'controles': draft.controls
          .map(
            (control) => {
              if (control.id != null) 'id': control.id,
              'nombre': control.name,
            },
          )
          .toList(growable: false),
      'creatorEmail': creatorEmail,
      'creatorFullName': creatorFullName,
    });
    _clearEventSummaryCache();

    return _parseEvent(_readMap(payload['data'], 'evento'));
  }

  Future<EventRecord> updateEvent({
    required int eventId,
    required EventRecordDraft draft,
    required String requesterEmail,
  }) async {
    final payload = await _apiClient.putJson('/api/eventos/$eventId', {
      'nombre': draft.name,
      'fechaEvento': _formatDateForApi(draft.date),
      'direccion': draft.address,
      'latitud': draft.latitude,
      'longitud': draft.longitude,
      'oficinaIds': draft.officeIds,
      'oficinaIdsExcluidos': draft.excludedOfficeIds,
      'requesterEmail': requesterEmail,
      'controles': draft.controls
          .map(
            (control) => {
              if (control.id != null) 'id': control.id,
              'nombre': control.name,
            },
          )
          .toList(growable: false),
    });
    _clearEventSummaryCache();

    return _parseEvent(_readMap(payload['data'], 'evento'));
  }

  Future<void> deleteEvent({
    required int eventId,
    required String requesterEmail,
  }) async {
    final encodedEmail = Uri.encodeQueryComponent(requesterEmail);
    await _apiClient.deleteJson(
      '/api/eventos/$eventId?requesterEmail=$encodedEmail',
    );
    _clearEventSummaryCache();
  }

  Future<void> registerAttendance({
    required int eventId,
    required int controlId,
    required EventListType listType,
    required String operatorEmail,
    required String operatorFullName,
    required double latitude,
    required double longitude,
    String? qrValue,
    String? ci,
    DateTime? scannedAt,
    double? accuracy,
    String? observation,
    Map<String, String>? payloadFields,
  }) async {
    await _apiClient.postJson('/api/asistencias', {
      'eventId': eventId,
      'controlId': controlId,
      'qrValue': qrValue,
      'ci': ci,
      'registrationSource': ci == null ? 'QR' : 'CI',
      'estado': listType == EventListType.attended ? 'ASISTIO' : 'OBSERVADO',
      'scannedAt': scannedAt?.toIso8601String(),
      'latitud': latitude,
      'longitud': longitude,
      'accuracy': accuracy,
      'observacion': observation,
      'payloadFields': payloadFields,
      'operatorEmail': operatorEmail,
      'operatorFullName': operatorFullName,
    });
    _clearEventSummaryCache();
  }

  EventRecord _parseEvent(Map<String, dynamic> source) {
    final createdBy = _readMap(source['creadoPor'], 'creadoPor');
    final offices = _parseEventOffices(source);
    final attended = _readList(
      source['asistieron'] ?? const [],
      'asistieron',
    ).map(_parseRosterEntry).toList(growable: false);
    final observed = _readList(
      source['observaron'] ?? const [],
      'observaron',
    ).map(_parseRosterEntry).toList(growable: false);

    return EventRecord(
      id: _readInt(source['id'], 'id'),
      name: _readString(source['nombre'], 'nombre'),
      date: DateTime.parse(
        _readString(source['fechaEvento'], 'fechaEvento'),
      ).toLocal(),
      createdBy: _readString(createdBy['nombreCompleto'], 'creadoPor'),
      createdAt: DateTime.parse(
        _readString(source['createdAt'], 'createdAt'),
      ).toLocal(),
      updatedAt: DateTime.parse(
        _readString(source['updatedAt'], 'updatedAt'),
      ).toLocal(),
      address: _readNullableString(source['direccion']),
      latitude: _readNullableDouble(source['latitud']),
      longitude: _readNullableDouble(source['longitud']),
      controls: _readList(
        source['controles'] ?? const [],
        'controles',
      ).map(_parseEventControl).toList(growable: false),
      offices: offices,
      selectedOfficeIds: _resolveSelectedOfficeIds(
        offices,
        source['oficinaIdsSeleccionados'],
      ),
      excludedOfficeIds: _readIntList(
        source['oficinaIdsExcluidos'],
        'oficinaIdsExcluidos',
      ),
      attended: attended,
      observed: observed,
      attendedCount:
          _readNullableInt(source['asistieronCount']) ?? attended.length,
      observedCount:
          _readNullableInt(source['observaronCount']) ?? observed.length,
      hasDetailedAttendanceData:
          source['detalleCompleto'] as bool? ?? true,
    );
  }

  bool _isCacheFresh(DateTime? cachedAt, Duration ttl) {
    if (cachedAt == null) {
      return false;
    }

    return DateTime.now().difference(cachedAt) <= ttl;
  }

  void _clearEventSummaryCache() {
    _eventSummaryCache = null;
    _eventSummaryCacheAt = null;
  }

  List<EventOffice> _parseEventOffices(Map<String, dynamic> source) {
    final officesSource = source['oficinas'];

    if (officesSource is List && officesSource.isNotEmpty) {
      return _readList(
        officesSource,
        'oficinas',
      ).map(_parseOffice).toList(growable: false);
    }

    final departmentsSource = source['departamentos'];

    if (departmentsSource is List && departmentsSource.isNotEmpty) {
      return _readList(
        departmentsSource,
        'departamentos',
      ).map(_parseLegacyDepartmentAsOffice).toList(growable: false);
    }

    return const [];
  }

  List<int> _resolveSelectedOfficeIds(
    List<EventOffice> offices,
    dynamic source,
  ) {
    final selectedOfficeIds = _readIntList(source, 'oficinaIdsSeleccionados');

    if (selectedOfficeIds.isNotEmpty || offices.isEmpty) {
      return selectedOfficeIds;
    }

    final availableCodes = offices
        .map((office) => _normalizeOfficeCode(office.code))
        .where((code) => code.isNotEmpty)
        .toSet();

    return offices
        .where((office) {
          final officeCode = _normalizeOfficeCode(office.code);

          if (officeCode.isEmpty) {
            return true;
          }

          return !availableCodes.any(
            (candidateCode) =>
                candidateCode != officeCode &&
                officeCode.startsWith('$candidateCode.'),
          );
        })
        .map((office) => office.id)
        .toList(growable: false);
  }

  EventOffice _parseOffice(Map<String, dynamic> source) {
    return EventOffice(
      id: _readInt(source['id'], 'oficina.id'),
      name: _readString(source['nombre'], 'oficina.nombre'),
      code: _readString(source['codigo'], 'oficina.codigo'),
      level: _readInt(source['nivel'], 'oficina.nivel'),
    );
  }

  EventOffice _parseLegacyDepartmentAsOffice(Map<String, dynamic> source) {
    return EventOffice(
      id: _readInt(source['id'], 'departamento.id'),
      name: _readString(source['nombre'], 'departamento.nombre'),
      code: 'legacy-${_readInt(source['id'], 'departamento.id')}',
      level: 0,
    );
  }

  EventRosterEntry _parseRosterEntry(Map<String, dynamic> source) {
    final controls = _readList(
      source['controles'] ?? const [],
      'asistencia.controles',
    ).map(_parseAttendanceControl).toList(growable: false);

    return EventRosterEntry(
      id: _readInt(source['id'], 'asistencia.id'),
      personId: _readInt(source['personaId'], 'asistencia.personaId'),
      ci: _readNullableString(source['ci']),
      fullName: _readString(
        source['nombreCompleto'],
        'asistencia.nombreCompleto',
      ),
      note: _readString(source['observacion'], 'asistencia.observacion'),
      registeredAt: DateTime.parse(
        _readString(source['registradoEn'], 'asistencia.registradoEn'),
      ).toLocal(),
      controls: controls,
      registeredControlsCount:
          _readNullableInt(source['controlesRegistrados']) ?? controls.length,
      attendedControlsCount:
          _readNullableInt(source['controlesAsistidos']) ??
          controls.where((control) => control.isAttended).length,
      observedControlsCount:
          _readNullableInt(source['controlesObservados']) ??
          controls.where((control) => !control.isAttended).length,
      officeName:
          _readNullableString(source['oficina']) ??
          _readNullableString(source['unidad']) ??
          _readNullableString(source['departamento']),
      tipoVinculo: _readNullableString(source['tipoVinculo']),
      qrValue: _readNullableString(source['qrLeido']),
    );
  }

  EventControl _parseEventControl(Map<String, dynamic> source) {
    return EventControl(
      id: _readInt(source['id'], 'control.id'),
      name: _readString(source['nombre'], 'control.nombre'),
      order: _readInt(source['orden'], 'control.orden'),
    );
  }

  EventAttendanceControl _parseAttendanceControl(Map<String, dynamic> source) {
    return EventAttendanceControl(
      id: _readInt(source['id'], 'controlRegistro.id'),
      controlId: _readInt(source['controlId'], 'controlRegistro.controlId'),
      controlName: _readString(
        source['controlNombre'],
        'controlRegistro.controlNombre',
      ),
      controlOrder: _readInt(
        source['controlOrden'],
        'controlRegistro.controlOrden',
      ),
      status: _readString(source['estado'], 'controlRegistro.estado'),
      registeredAt: DateTime.parse(
        _readString(source['registradoEn'], 'controlRegistro.registradoEn'),
      ).toLocal(),
      note: _readNullableString(source['observacion']),
    );
  }
}

List<Map<String, dynamic>> _readList(dynamic source, String fieldName) {
  if (source is! List) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source
      .map((item) => _readMap(item, fieldName))
      .toList(growable: false);
}

Map<String, dynamic> _readMap(dynamic source, String fieldName) {
  if (source is! Map<String, dynamic>) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
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

List<int> _readIntList(dynamic source, String fieldName) {
  if (source == null) {
    return const [];
  }

  if (source is! List) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source
      .map((item) => _readInt(item, fieldName))
      .toList(growable: false);
}

String _formatDateForApi(DateTime date) {
  return date.toIso8601String();
}

String _normalizeOfficeCode(String code) {
  return code.trim().replaceFirst(RegExp(r'\.+$'), '');
}
