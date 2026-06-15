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

int? _readNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  throw StateError('Se esperaba un numero valido.');
}
