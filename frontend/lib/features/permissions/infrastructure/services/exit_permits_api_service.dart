import '../../../../shared/infrastructure/backend_api_client.dart';

enum ExitPermitReason {
  work('TRABAJO', 'Trabajo'),
  personal('PARTICULAR', 'Particular');

  const ExitPermitReason(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ExitPermitReason fromApiValue(String value) {
    return value == work.apiValue ? work : personal;
  }
}

enum ExitPermitStatus {
  pending('PENDIENTE', 'Pendiente'),
  approved('APROBADO', 'Aprobado'),
  rejected('RECHAZADO', 'Rechazado');

  const ExitPermitStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ExitPermitStatus fromApiValue(String value) {
    return switch (value) {
      'APROBADO' => approved,
      'RECHAZADO' => rejected,
      _ => pending,
    };
  }
}

class ExitPermitsApiService {
  ExitPermitsApiService(this._apiClient);

  final BackendApiClient _apiClient;

  Future<ExitPermitRecord> createExitPermit({
    required ExitPermitReason reason,
    required String destination,
    required String description,
    required DateTime permitDate,
    required String startTime,
    required String? endTime,
  }) async {
    final payload = await _apiClient.postJson('/api/salidas', {
      'motivo': reason.apiValue,
      'lugarDestino': destination,
      'descripcion': description,
      'fechaPermiso': _dateOnly(permitDate),
      'horaInicio': startTime,
      'horaFinal': endTime,
    });

    return ExitPermitRecord.fromJson(_readMap(payload['data'], 'salida'));
  }

  Future<List<ExitPermitRecord>> fetchExitPermitsByDate(DateTime date) async {
    final payload = await _apiClient.getJson(
      '/api/salidas?fecha=${Uri.encodeQueryComponent(_dateOnly(date))}',
    );
    final rows = _readList(payload['data'], 'salidas');

    return rows.map(ExitPermitRecord.fromJson).toList(growable: false);
  }

  Future<List<ExitPermitRecord>> fetchPendingExitPermits() async {
    final payload = await _apiClient.getJson('/api/salidas/pendientes');
    final rows = _readList(payload['data'], 'salidas');

    return rows.map(ExitPermitRecord.fromJson).toList(growable: false);
  }

  Future<ExitPermitRecord> reviewExitPermit({
    required int id,
    required ExitPermitStatus status,
  }) async {
    final payload = await _apiClient.putJson('/api/salidas/$id/estado', {
      'estado': status.apiValue,
    });

    return ExitPermitRecord.fromJson(_readMap(payload['data'], 'salida'));
  }
}

class ExitPermitRecord {
  const ExitPermitRecord({
    required this.id,
    required this.userId,
    required this.reason,
    required this.status,
    required this.destination,
    required this.description,
    required this.permitDate,
    required this.startTime,
    required this.endTime,
    required this.applicantFullName,
    required this.applicantCi,
    required this.applicantItemNumber,
    required this.applicantJobTitle,
    required this.applicantOfficeId,
    required this.applicantOffice,
    required this.approvedById,
    required this.approvedByName,
    required this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final ExitPermitReason reason;
  final ExitPermitStatus status;
  final String destination;
  final String description;
  final DateTime permitDate;
  final String startTime;
  final String endTime;
  final String applicantFullName;
  final String applicantCi;
  final String applicantItemNumber;
  final String applicantJobTitle;
  final int? applicantOfficeId;
  final String applicantOffice;
  final int? approvedById;
  final String approvedByName;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ExitPermitRecord.fromJson(Map<String, dynamic> source) {
    return ExitPermitRecord(
      id: _readInt(source['id'], 'id'),
      userId: _readInt(source['usuarioId'], 'usuarioId'),
      reason: ExitPermitReason.fromApiValue(
        _readString(source['motivo'], 'motivo'),
      ),
      status: ExitPermitStatus.fromApiValue(
        _readString(source['estado'], 'estado'),
      ),
      destination: _readString(source['lugarDestino'], 'lugarDestino'),
      description: _readString(source['descripcion'], 'descripcion'),
      permitDate: DateTime.parse(
        _readString(source['fechaPermiso'], 'fechaPermiso'),
      ),
      startTime: _readString(source['horaInicio'], 'horaInicio'),
      endTime: _readString(source['horaFinal'], 'horaFinal'),
      applicantFullName: _readString(
        source['solicitanteNombreCompleto'],
        'solicitanteNombreCompleto',
      ),
      applicantCi: _readString(source['solicitanteCi'], 'solicitanteCi'),
      applicantItemNumber: _readString(
        source['solicitanteNumeroItem'],
        'solicitanteNumeroItem',
      ),
      applicantJobTitle: _readString(
        source['solicitanteCargo'],
        'solicitanteCargo',
      ),
      applicantOfficeId: source['solicitanteOficinaId'] as int?,
      applicantOffice: _readString(
        source['solicitanteOficina'],
        'solicitanteOficina',
      ),
      approvedById: source['aprobadoPorId'] as int?,
      approvedByName: _readString(
        source['aprobadoPorNombre'],
        'aprobadoPorNombre',
      ),
      approvedAt: _readOptionalDate(source['aprobadoEn']),
      createdAt: DateTime.parse(
        _readString(source['createdAt'], 'createdAt'),
      ).toLocal(),
      updatedAt: DateTime.parse(
        _readString(source['updatedAt'], 'updatedAt'),
      ).toLocal(),
    );
  }
}

DateTime? _readOptionalDate(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return DateTime.parse(value).toLocal();
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

int _readInt(dynamic value, String fieldName) {
  if (value is! int) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return value;
}

String _readString(dynamic value, String fieldName) {
  if (value is! String) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return value;
}

String _dateOnly(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
