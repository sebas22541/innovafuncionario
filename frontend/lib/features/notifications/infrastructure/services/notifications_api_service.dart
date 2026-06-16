import '../../../../shared/infrastructure/backend_api_client.dart';

class NotificationsApiService {
  NotificationsApiService(this._apiClient);

  final BackendApiClient _apiClient;

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _apiClient.postJson('/api/notificaciones/token', {
      'token': token,
      'platform': platform,
    });
  }

  Future<void> deleteDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _apiClient.deleteJsonWithBody('/api/notificaciones/token', {
      'token': token,
      'platform': platform,
    });
  }

  Future<List<ReceivedNotification>> fetchReceivedNotifications() async {
    final payload = await _apiClient.getJson('/api/notificaciones/recibidas');
    final rows = _readList(payload['data'], 'notificaciones');

    return rows
        .map(
          (row) => ReceivedNotification.fromJson(_readMap(row, 'notificacion')),
        )
        .toList(growable: false);
  }

  Future<void> markReceivedNotificationRead(int id) async {
    await _apiClient.putJson('/api/notificaciones/$id/leida', const {});
  }

  Future<NotificationSendResult> sendNotification({
    required String title,
    required String body,
    required bool sendToAll,
    required List<String> cargoCodigos,
    required List<int> oficinaIds,
    required List<String> cis,
    required List<String> tiposVinculo,
  }) async {
    final payload = await _apiClient.postJson('/api/notificaciones/enviar', {
      'title': title,
      'body': body,
      'sendToAll': sendToAll,
      'cargoCodigos': cargoCodigos,
      'oficinaIds': oficinaIds,
      'cis': cis,
      'tiposVinculo': tiposVinculo,
    });

    return NotificationSendResult.fromJson(
      _readMap(payload['data'], 'notificacion'),
    );
  }
}

class ReceivedNotification {
  const ReceivedNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.targetSection,
    required this.exitPermitId,
    required this.readAt,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String type;
  final String title;
  final String body;
  final String targetSection;
  final int? exitPermitId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  factory ReceivedNotification.fromJson(Map<String, dynamic> source) {
    return ReceivedNotification(
      id: _readInt(source['id'], 'id'),
      userId: _readInt(source['usuarioId'], 'usuarioId'),
      type: _readString(source['tipo'], 'tipo'),
      title: _readString(source['titulo'], 'titulo'),
      body: _readString(source['cuerpo'], 'cuerpo'),
      targetSection: _readString(source['destinoSeccion'], 'destinoSeccion'),
      exitPermitId: _readNullableInt(source['salidaId']),
      readAt: _readOptionalDate(source['leidaEn']),
      createdAt: DateTime.parse(_readString(source['createdAt'], 'createdAt')),
    );
  }
}

class NotificationSendResult {
  const NotificationSendResult({
    required this.requested,
    required this.sent,
    required this.failed,
    required this.removedInvalidTokens,
    this.message,
  });

  final int requested;
  final int sent;
  final int failed;
  final int removedInvalidTokens;
  final String? message;

  factory NotificationSendResult.fromJson(Map<String, dynamic> source) {
    return NotificationSendResult(
      requested: _readInt(source['requested'], 'requested'),
      sent: _readInt(source['sent'], 'sent'),
      failed: _readInt(source['failed'], 'failed'),
      removedInvalidTokens:
          _readNullableInt(source['removedInvalidTokens']) ?? 0,
      message: source['message'] as String?,
    );
  }
}

Map<String, dynamic> _readMap(dynamic source, String fieldName) {
  if (source is! Map<String, dynamic>) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}

int _readInt(dynamic value, String fieldName) {
  if (value is! int) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return value;
}

String _readString(dynamic value, String fieldName) {
  if (value is String) {
    return value;
  }

  if (value == null) {
    return '';
  }

  throw StateError('El campo $fieldName no tiene un formato valido.');
}

List<dynamic> _readList(dynamic source, String fieldName) {
  if (source is! List) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}

DateTime? _readOptionalDate(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value);
  }

  throw StateError('Se esperaba una fecha valida.');
}

int? _readNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  throw StateError('Se esperaba un numero valido.');
}
