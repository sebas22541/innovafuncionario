import 'dart:typed_data';

import '../../../../shared/infrastructure/backend_api_client.dart';

enum SwornDeclarationStatus {
  pending('PENDIENTE', 'Pendiente'),
  approved('APROBADO', 'Aprobado'),
  rejected('RECHAZADO', 'Rechazado');

  const SwornDeclarationStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static SwornDeclarationStatus fromApiValue(String value) {
    return switch (value) {
      'APROBADO' => approved,
      'RECHAZADO' => rejected,
      _ => pending,
    };
  }
}

class SwornDeclarationsApiService {
  SwornDeclarationsApiService(this._apiClient);

  final BackendApiClient _apiClient;

  Future<List<SwornDeclarationRecord>> fetchDeclarations({
    String? query,
    bool onlyMine = false,
  }) async {
    final queryParams = {
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (onlyMine) 'propias': 'true',
    };
    final queryText = queryParams.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final path = queryText.isEmpty
        ? '/api/declaraciones-juradas'
        : '/api/declaraciones-juradas?$queryText';
    final payload = await _apiClient.getJson(path);
    final rows = _readList(payload['data'], 'declaraciones');

    return rows.map(SwornDeclarationRecord.fromJson).toList(growable: false);
  }

  Future<SwornDeclarationRecord> createDeclaration({
    required int managementYear,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _apiClient.postJson('/api/declaraciones-juradas', {
      'gestion': managementYear,
      'payload': payload,
    });

    return SwornDeclarationRecord.fromJson(
      _readMap(response['data'], 'declaracion'),
    );
  }

  Future<SwornDeclarationRecord> reviewDeclaration({
    required int id,
    required SwornDeclarationStatus status,
    String observation = '',
  }) async {
    final response = await _apiClient.putJson(
      '/api/declaraciones-juradas/$id/estado',
      {
        'estado': status.apiValue,
        'observacion': observation,
      },
    );

    return SwornDeclarationRecord.fromJson(
      _readMap(response['data'], 'declaracion'),
    );
  }

  Future<Uint8List> downloadDeclarationPdf({required int id}) {
    return _apiClient.postBytes('/api/declaraciones-juradas/$id/pdf', {});
  }
}

class SwornDeclarationRecord {
  const SwornDeclarationRecord({
    required this.id,
    required this.userId,
    required this.managementYear,
    required this.status,
    required this.employeeFullName,
    required this.employeeCi,
    required this.employeeItemNumber,
    required this.employeeJobTitle,
    required this.employeeOffice,
    required this.payload,
    required this.reviewObservation,
    required this.reviewedByName,
    required this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final int managementYear;
  final SwornDeclarationStatus status;
  final String employeeFullName;
  final String employeeCi;
  final String employeeItemNumber;
  final String employeeJobTitle;
  final String employeeOffice;
  final Map<String, dynamic> payload;
  final String reviewObservation;
  final String reviewedByName;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SwornDeclarationRecord.fromJson(Map<String, dynamic> source) {
    return SwornDeclarationRecord(
      id: _readInt(source['id'], 'id'),
      userId: _readInt(source['usuarioId'], 'usuarioId'),
      managementYear: _readInt(source['gestion'], 'gestion'),
      status: SwornDeclarationStatus.fromApiValue(
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
      employeeOffice: _readString(
        source['funcionarioOficina'],
        'funcionarioOficina',
      ),
      payload: _readMap(source['payload'], 'payload'),
      reviewObservation: _readString(
        source['observacionRevision'],
        'observacionRevision',
      ),
      reviewedByName: _readString(
        source['revisadoPorNombre'],
        'revisadoPorNombre',
      ),
      reviewedAt: _readOptionalDate(source['revisadoEn']),
      createdAt: DateTime.parse(
        _readString(source['createdAt'], 'createdAt'),
      ).toLocal(),
      updatedAt: DateTime.parse(
        _readString(source['updatedAt'], 'updatedAt'),
      ).toLocal(),
    );
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

DateTime? _readOptionalDate(dynamic value) {
  if (value == null || value is! String || value.trim().isEmpty) {
    return null;
  }

  return DateTime.parse(value).toLocal();
}
