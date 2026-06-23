import '../../../../shared/infrastructure/backend_api_client.dart';

enum LunchRecordStatus {
  open('ABIERTO', 'En almuerzo'),
  closed('CERRADO', 'Retornado');

  const LunchRecordStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LunchRecordStatus fromApiValue(String value) {
    return value == closed.apiValue ? closed : open;
  }
}

enum LunchScanAction {
  departure('SALIDA', 'Salida'),
  returnToWork('RETORNO', 'Retorno');

  const LunchScanAction(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LunchScanAction fromApiValue(String value) {
    return value == returnToWork.apiValue ? returnToWork : departure;
  }
}

class LunchesApiService {
  LunchesApiService(this._apiClient);

  final BackendApiClient _apiClient;

  Future<LunchScanResponse> registerScan({required String qrValue}) async {
    final payload = await _apiClient.postJson('/api/almuerzos/scan', {
      'qrValue': qrValue,
    });

    return LunchScanResponse.fromJson(_readMap(payload['data'], 'almuerzo'));
  }

  Future<List<LunchRecord>> fetchLunches({
    required DateTime date,
    String? query,
    LunchRecordStatus? status,
  }) async {
    final queryParams = {
      'fecha': _dateOnly(date),
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (status != null) 'estado': '${status.apiValue}S',
    };
    final queryText = queryParams.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final payload = await _apiClient.getJson('/api/almuerzos?$queryText');
    final rows = _readList(payload['data'], 'almuerzos');

    return rows.map(LunchRecord.fromJson).toList(growable: false);
  }
}

class LunchScanResponse {
  const LunchScanResponse({
    required this.action,
    required this.message,
    required this.record,
  });

  final LunchScanAction action;
  final String message;
  final LunchRecord record;

  factory LunchScanResponse.fromJson(Map<String, dynamic> source) {
    return LunchScanResponse(
      action: LunchScanAction.fromApiValue(_readString(source['accion'], 'accion')),
      message: _readString(source['mensaje'], 'mensaje'),
      record: LunchRecord.fromJson(_readMap(source['registro'], 'registro')),
    );
  }
}

class LunchRecord {
  const LunchRecord({
    required this.id,
    required this.userId,
    required this.date,
    required this.departureTime,
    required this.departureAt,
    required this.returnTime,
    required this.returnAt,
    required this.status,
    required this.employeeFullName,
    required this.employeeCi,
    required this.employeeItemNumber,
    required this.employeeJobTitle,
    required this.employeeOfficeId,
    required this.employeeOffice,
    required this.departureScannerId,
    required this.departureScannerName,
    required this.returnScannerId,
    required this.returnScannerName,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final DateTime date;
  final String departureTime;
  final DateTime departureAt;
  final String returnTime;
  final DateTime? returnAt;
  final LunchRecordStatus status;
  final String employeeFullName;
  final String employeeCi;
  final String employeeItemNumber;
  final String employeeJobTitle;
  final int? employeeOfficeId;
  final String employeeOffice;
  final int? departureScannerId;
  final String departureScannerName;
  final int? returnScannerId;
  final String returnScannerName;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOpen => status == LunchRecordStatus.open;

  factory LunchRecord.fromJson(Map<String, dynamic> source) {
    return LunchRecord(
      id: _readInt(source['id'], 'id'),
      userId: _readInt(source['usuarioId'], 'usuarioId'),
      date: DateTime.parse(_readString(source['fecha'], 'fecha')),
      departureTime: _readString(source['horaSalida'], 'horaSalida'),
      departureAt: DateTime.parse(
        _readString(source['salidaEn'], 'salidaEn'),
      ).toLocal(),
      returnTime: _readString(source['horaRetorno'], 'horaRetorno'),
      returnAt: _readOptionalDate(source['retornoEn']),
      status: LunchRecordStatus.fromApiValue(
        _readString(source['estado'], 'estado'),
      ),
      employeeFullName: _readString(
        source['funcionarioNombreCompleto'],
        'funcionarioNombreCompleto',
      ),
      employeeCi: _readString(source['funcionarioCi'], 'funcionarioCi'),
      employeeItemNumber: _readString(
        source['funcionarioNumeroItem'],
        'funcionarioNumeroItem',
      ),
      employeeJobTitle: _readString(
        source['funcionarioCargo'],
        'funcionarioCargo',
      ),
      employeeOfficeId: source['funcionarioOficinaId'] as int?,
      employeeOffice: _readString(
        source['funcionarioOficina'],
        'funcionarioOficina',
      ),
      departureScannerId: source['registradoSalidaPorId'] as int?,
      departureScannerName: _readString(
        source['registradoSalidaPorNombre'],
        'registradoSalidaPorNombre',
      ),
      returnScannerId: source['registradoRetornoPorId'] as int?,
      returnScannerName: _readString(
        source['registradoRetornoPorNombre'],
        'registradoRetornoPorNombre',
      ),
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
