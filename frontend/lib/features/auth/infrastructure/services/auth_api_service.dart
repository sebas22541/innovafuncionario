import 'dart:typed_data';

import '../../domain/entities/cargo_option.dart';
import '../../domain/entities/office_option.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';

class AuthApiService {
  AuthApiService(this._apiClient);

  final BackendApiClient _apiClient;
  static const Duration _dashboardCacheTtl = Duration(seconds: 20);
  static const Duration _referenceCacheTtl = Duration(minutes: 5);
  DashboardSummary? _dashboardSummaryCache;
  DateTime? _dashboardSummaryCacheAt;
  List<OfficeOption>? _officesCache;
  DateTime? _officesCacheAt;
  List<CargoOption>? _cargosCache;
  DateTime? _cargosCacheAt;

  Future<DashboardSummary> fetchDashboardSummary() async {
    if (_isCacheFresh(_dashboardSummaryCacheAt, _dashboardCacheTtl)) {
      final cachedSummary = _dashboardSummaryCache;

      if (cachedSummary != null) {
        return cachedSummary;
      }
    }

    final payload = await _apiClient.getJson('/api/inicio/resumen');
    final summary = DashboardSummary.fromJson(_readMap(payload['data'], 'resumen'));
    _dashboardSummaryCache = summary;
    _dashboardSummaryCacheAt = DateTime.now();
    return summary;
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final payload = await _apiClient.postJson('/api/auth/login', {
      'email': email,
      'password': password,
    });

    return AppUser.fromJson(_readMap(payload['data'], 'usuario'));
  }

  Future<AppUser> updateProfileNames({
    required String email,
    required String nombreCompleto,
    required String primerApellido,
    required String segundoApellido,
    required String tercerApellido,
    String? fotoData,
  }) async {
    final payload = await _apiClient.putJson('/api/auth/profile', {
      'email': email,
      'nombreCompleto': nombreCompleto,
      'primerApellido': primerApellido,
      'segundoApellido': segundoApellido,
      'tercerApellido': tercerApellido,
      'fotoData': fotoData,
    });

    return AppUser.fromJson(_readMap(payload['data'], 'usuario'));
  }

  Future<DynamicQrSession> generateDynamicQr({
    required String email,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final payload = await _apiClient.postJson('/api/auth/qr/dynamic', {
      'email': email,
      'latitud': latitude,
      'longitud': longitude,
      'accuracy': accuracy,
    });

    return DynamicQrSession.fromJson(_readMap(payload['data'], 'qrDinamico'));
  }

  Future<DynamicQrSession?> fetchActiveDynamicQr({
    required String email,
  }) async {
    final payload = await _apiClient.getJson(
      '/api/auth/qr/dynamic?email=${Uri.encodeQueryComponent(email)}',
    );
    final data = payload['data'];

    if (data == null) {
      return null;
    }

    return DynamicQrSession.fromJson(_readMap(data, 'qrDinamicoActivo'));
  }

  Future<UserCredential> generateCredential({required String email}) async {
    final payload = await _apiClient.postJson('/api/auth/credential', {
      'email': email,
    });

    return UserCredential.fromJson(_readMap(payload['data'], 'credencial'));
  }

  Future<Uint8List> downloadCredentialPdf({required String email}) {
    return _apiClient.postBytes('/api/auth/credential/pdf', {
      'email': email,
    });
  }

  Future<AppUser> register({
    required String email,
    required String password,
    required String nombreCompleto,
    required String primerApellido,
    required String segundoApellido,
    required String tercerApellido,
    required String ci,
    required String tipoVinculo,
    required int? oficinaId,
    required String? cargoCodigo,
    required String unidad,
    required String cargo,
    required String numeroItem,
    required bool activo,
    required String fotoData,
  }) async {
    final payload = await _apiClient.postJson('/api/auth/register', {
      'email': email,
      'password': password,
      'nombreCompleto': nombreCompleto,
      'primerApellido': primerApellido,
      'segundoApellido': segundoApellido,
      'tercerApellido': tercerApellido,
      'ci': ci,
      'tipoVinculo': tipoVinculo,
      'oficinaId': oficinaId,
      'cargoCodigo': cargoCodigo,
      'unidad': unidad,
      'cargo': cargo,
      'numeroItem': numeroItem,
      'activo': activo,
      'fotoData': fotoData,
    });
    _dashboardSummaryCache = null;
    _dashboardSummaryCacheAt = null;

    return AppUser.fromJson(_readMap(payload['data'], 'usuario'));
  }

  Future<List<AppUser>> fetchUsers({required String requesterEmail}) async {
    final payload = await _apiClient.getJson(
      '/api/usuarios?requesterEmail=${Uri.encodeQueryComponent(requesterEmail)}',
    );
    final users = _readList(payload['data'], 'usuarios');

    return users.map(AppUser.fromJson).toList(growable: false);
  }

  Future<AppUser> createManagedUser({
    required String requesterEmail,
    required AppUserRole role,
    required String email,
    required String password,
    required String nombreCompleto,
    required String primerApellido,
    required String segundoApellido,
    required String tercerApellido,
    required String ci,
    required String tipoVinculo,
    required int? oficinaId,
    required String? cargoCodigo,
    required String unidad,
    required String cargo,
    required String numeroItem,
    required bool activo,
    required String fotoData,
  }) async {
    final payload = await _apiClient.postJson('/api/usuarios', {
      'requesterEmail': requesterEmail,
      'rol': role.apiValue,
      'email': email,
      'password': password,
      'nombreCompleto': nombreCompleto,
      'primerApellido': primerApellido,
      'segundoApellido': segundoApellido,
      'tercerApellido': tercerApellido,
      'ci': ci,
      'tipoVinculo': tipoVinculo,
      'oficinaId': oficinaId,
      'cargoCodigo': cargoCodigo,
      'unidad': unidad,
      'cargo': cargo,
      'numeroItem': numeroItem,
      'activo': activo,
      'fotoData': fotoData,
    });
    _dashboardSummaryCache = null;
    _dashboardSummaryCacheAt = null;

    return AppUser.fromJson(_readMap(payload['data'], 'usuario'));
  }

  Future<AppUser> updateUserActiveStatus({
    required String requesterEmail,
    required int userId,
    required bool activo,
  }) async {
    final payload = await _apiClient.putJson('/api/usuarios/$userId', {
      'requesterEmail': requesterEmail,
      'activo': activo,
    });

    return AppUser.fromJson(_readMap(payload['data'], 'usuario'));
  }

  Future<List<OfficeOption>> fetchOffices({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheFresh(_officesCacheAt, _referenceCacheTtl)) {
      return _officesCache ?? const [];
    }

    final payload = await _apiClient.getJson('/api/oficinas');
    final offices = _readList(payload['data'], 'oficinas');
    final parsedOffices = offices
        .map(OfficeOption.fromJson)
        .toList(growable: false);
    _officesCache = parsedOffices;
    _officesCacheAt = DateTime.now();

    return parsedOffices;
  }

  Future<List<CargoOption>> fetchCargos({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheFresh(_cargosCacheAt, _referenceCacheTtl)) {
      return _cargosCache ?? const [];
    }

    final payload = await _apiClient.getJson('/api/cargos');
    final cargos = _readList(payload['data'], 'cargos');
    final parsedCargos = cargos
        .map(CargoOption.fromJson)
        .toList(growable: false);
    _cargosCache = parsedCargos;
    _cargosCacheAt = DateTime.now();

    return parsedCargos;
  }

  bool _isCacheFresh(DateTime? cachedAt, Duration ttl) {
    if (cachedAt == null) {
      return false;
    }

    return DateTime.now().difference(cachedAt) <= ttl;
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.registeredUsers,
    required this.offices,
    required this.events,
  });

  final int registeredUsers;
  final int offices;
  final int events;

  factory DashboardSummary.fromJson(Map<String, dynamic> source) {
    return DashboardSummary(
      registeredUsers: _readInt(
        source['usuariosRegistrados'],
        'usuariosRegistrados',
      ),
      offices: _readInt(source['oficinas'], 'oficinas'),
      events: _readInt(source['eventos'], 'eventos'),
    );
  }
}

class DynamicQrSession {
  const DynamicQrSession({
    required this.qrCode,
    required this.qrPayload,
    required this.generatedAt,
    required this.expiresAt,
    required this.ttlSeconds,
    required this.location,
  });

  final String qrCode;
  final String qrPayload;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final int ttlSeconds;
  final DynamicQrLocationSnapshot location;

  factory DynamicQrSession.fromJson(Map<String, dynamic> source) {
    return DynamicQrSession(
      qrCode: _readString(source['qrCode'], 'qrCode'),
      qrPayload: _readString(source['qrPayload'], 'qrPayload'),
      generatedAt: DateTime.parse(
        _readString(source['generatedAt'], 'generatedAt'),
      ).toLocal(),
      expiresAt: DateTime.parse(
        _readString(source['expiresAt'], 'expiresAt'),
      ).toLocal(),
      ttlSeconds: _readInt(source['ttlSeconds'], 'ttlSeconds'),
      location: DynamicQrLocationSnapshot.fromJson(
        _readMap(source['location'], 'location'),
      ),
    );
  }
}

class DynamicQrLocationSnapshot {
  const DynamicQrLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;

  factory DynamicQrLocationSnapshot.fromJson(Map<String, dynamic> source) {
    return DynamicQrLocationSnapshot(
      latitude: _readDouble(source['latitud'], 'latitud'),
      longitude: _readDouble(source['longitud'], 'longitud'),
      accuracy: _readNullableDouble(source['accuracy']),
    );
  }
}

class UserCredential {
  const UserCredential({
    required this.frontImageUrl,
    required this.pdfUrl,
    required this.qrPayload,
    required this.generatedAt,
  });

  final String frontImageUrl;
  final String pdfUrl;
  final String qrPayload;
  final DateTime generatedAt;

  factory UserCredential.fromJson(Map<String, dynamic> source) {
    return UserCredential(
      frontImageUrl: _readString(source['frontImageUrl'], 'frontImageUrl'),
      pdfUrl: _readString(source['pdfUrl'], 'pdfUrl'),
      qrPayload: _readString(source['qrPayload'], 'qrPayload'),
      generatedAt: DateTime.parse(
        _readString(source['generatedAt'], 'generatedAt'),
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

double _readDouble(dynamic value, String fieldName) {
  if (value is int) {
    return value.toDouble();
  }

  if (value is double) {
    return value;
  }

  throw StateError('El campo $fieldName no tiene un formato valido.');
}

double? _readNullableDouble(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value.toDouble();
  }

  if (value is double) {
    return value;
  }

  throw StateError('Se esperaba un valor numerico.');
}
