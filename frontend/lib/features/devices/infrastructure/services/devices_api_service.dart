import '../../../../shared/infrastructure/backend_api_client.dart';

class DevicesApiService {
  const DevicesApiService(this._apiClient);

  final BackendApiClient _apiClient;

  Future<DeviceHeartbeatResponse> sendHeartbeat(
    Map<String, dynamic> status,
  ) async {
    final payload = await _apiClient.postJson(
      '/api/celulares/heartbeat',
      status,
    );

    return DeviceHeartbeatResponse.fromJson(_readMap(payload['data']));
  }

  Future<List<ManagedDevice>> fetchDevices() async {
    final payload = await _apiClient.getJson('/api/celulares');
    final rows = _readList(payload['data']);

    return rows
        .map((row) => ManagedDevice.fromJson(_readMap(row)))
        .toList(growable: false);
  }

  Future<void> requestLogout(String deviceId) async {
    await _apiClient.postJson(
      '/api/celulares/${Uri.encodeComponent(deviceId)}/cerrar-sesion',
      const {},
    );
  }

  Future<void> requestLogin(String deviceId) async {
    await _apiClient.postJson(
      '/api/celulares/${Uri.encodeComponent(deviceId)}/iniciar-sesion',
      const {},
    );
  }
}

class DeviceHeartbeatResponse {
  const DeviceHeartbeatResponse({required this.forceLogout});

  final bool forceLogout;

  factory DeviceHeartbeatResponse.fromJson(Map<String, dynamic> source) {
    return DeviceHeartbeatResponse(forceLogout: source['forceLogout'] == true);
  }
}

class ManagedDevice {
  const ManagedDevice({
    required this.deviceId,
    required this.userId,
    required this.userName,
    required this.userCi,
    required this.platform,
    required this.manufacturer,
    required this.model,
    required this.androidSdk,
    required this.batteryLevel,
    required this.isCharging,
    required this.brightness,
    required this.kioskEnabled,
    required this.isOnline,
    required this.lastSeenAt,
    required this.logoutRequestedAt,
  });

  final String deviceId;
  final int userId;
  final String userName;
  final String userCi;
  final String platform;
  final String manufacturer;
  final String model;
  final int? androidSdk;
  final int? batteryLevel;
  final bool? isCharging;
  final int? brightness;
  final bool kioskEnabled;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime? logoutRequestedAt;

  factory ManagedDevice.fromJson(Map<String, dynamic> source) {
    return ManagedDevice(
      deviceId: _readString(source['deviceId']),
      userId: _readInt(source['userId']),
      userName: _readString(source['userName']),
      userCi: _readString(source['userCi']),
      platform: _readString(source['platform']),
      manufacturer: _readString(source['manufacturer']),
      model: _readString(source['model']),
      androidSdk: _readNullableInt(source['androidSdk']),
      batteryLevel: _readNullableInt(source['batteryLevel']),
      isCharging: source['isCharging'] is bool
          ? source['isCharging'] as bool
          : null,
      brightness: _readNullableInt(source['brightness']),
      kioskEnabled: source['kioskEnabled'] == true,
      isOnline: source['isOnline'] == true,
      lastSeenAt: _readNullableDate(source['lastSeenAt']),
      logoutRequestedAt: _readNullableDate(source['logoutRequestedAt']),
    );
  }
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw StateError('La respuesta no tiene un formato valido.');
  }

  return value;
}

List<dynamic> _readList(dynamic value) {
  if (value is! List) {
    throw StateError('La respuesta no tiene un formato valido.');
  }

  return value;
}

String _readString(dynamic value) {
  return value is String ? value : '';
}

int _readInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return 0;
}

int? _readNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }

  return _readInt(value);
}

DateTime? _readNullableDate(dynamic value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value)?.toLocal();
}
