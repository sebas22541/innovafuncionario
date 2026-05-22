enum AppUserRole { admin, control, external }

extension AppUserRoleX on AppUserRole {
  String get apiValue {
    switch (this) {
      case AppUserRole.admin:
        return 'ADMIN';
      case AppUserRole.control:
        return 'CONTROL';
      case AppUserRole.external:
        return 'OPERADOR';
    }
  }

  String get label {
    switch (this) {
      case AppUserRole.admin:
        return 'Administrador';
      case AppUserRole.control:
        return 'Control';
      case AppUserRole.external:
        return 'Usuario externo';
    }
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    required this.nombreCompleto,
    required this.primerApellido,
    required this.segundoApellido,
    required this.tercerApellido,
    required this.ci,
    required this.tipoVinculo,
    required this.unidad,
    required this.cargo,
    required this.numeroItem,
    required this.activo,
    this.fotoUrl,
    this.officeId,
    this.officeName,
    this.officeCode,
    this.nombreVisible,
    this.personaId,
    this.qrCode,
    this.qrPayload,
  });

  final int? id;
  final String email;
  final AppUserRole role;
  final String nombreCompleto;
  final String primerApellido;
  final String segundoApellido;
  final String tercerApellido;
  final String ci;
  final String tipoVinculo;
  final String unidad;
  final String cargo;
  final String numeroItem;
  final bool activo;
  final String? fotoUrl;
  final int? officeId;
  final String? officeName;
  final String? officeCode;
  final String? nombreVisible;
  final int? personaId;
  final String? qrCode;
  final String? qrPayload;

  factory AppUser.fromJson(Map<String, dynamic> source) {
    return AppUser(
      id: source['id'] as int?,
      email: _readString(source['email'], 'email'),
      role: _readRole(source['rol']),
      nombreCompleto: _readString(source['nombreCompleto'], 'nombreCompleto'),
      primerApellido: _readString(source['primerApellido'], 'primerApellido'),
      segundoApellido: _readString(
        source['segundoApellido'],
        'segundoApellido',
      ),
      tercerApellido: _readString(source['tercerApellido'], 'tercerApellido'),
      ci: _readString(source['ci'], 'ci'),
      tipoVinculo: _readString(source['tipoVinculo'], 'tipoVinculo'),
      unidad: _readString(source['unidad'], 'unidad'),
      cargo: _readString(source['cargo'], 'cargo'),
      numeroItem: _readString(source['numeroItem'], 'numeroItem'),
      activo: source['activo'] as bool? ?? true,
      fotoUrl: (source['fotoUrl'] ?? source['fotoBase64']) as String?,
      officeId: source['oficinaId'] as int?,
      officeName: source['oficinaNombre'] as String?,
      officeCode: source['oficinaCodigo'] as String?,
      nombreVisible: source['nombreVisible'] as String?,
      personaId: source['personaId'] as int?,
      qrCode: source['qrCode'] as String?,
      qrPayload: source['qrPayload'] as String?,
    );
  }

  String get fullName {
    final builtName = [
      nombreCompleto,
      primerApellido,
      segundoApellido,
      tercerApellido,
    ].where((part) => part.trim().isNotEmpty).join(' ');

    if (builtName.isNotEmpty) {
      return builtName;
    }

    return nombreVisible?.trim().isNotEmpty == true
        ? nombreVisible!.trim()
        : nombreCompleto;
  }

  String get firstName {
    final parts = nombreCompleto
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) {
      return fullName;
    }

    return parts.first;
  }

  String get estadoLabel => activo ? 'Activo' : 'Inactivo';

  String get roleLabel => role.label;

  bool get isAdmin => role == AppUserRole.admin;

  bool get isControl => role == AppUserRole.control;

  bool get isExternalUser => role == AppUserRole.external;

  bool get canManageEvents => isAdmin;

  bool get canUseEventsPanel => isAdmin || isControl;

  bool get canUseEventScanner => isAdmin || isControl;

  bool get hasPhoto => fotoUrl?.trim().isNotEmpty == true;

  bool get hasQr =>
      qrCode?.trim().isNotEmpty == true || qrPayload?.trim().isNotEmpty == true;

  String get initial {
    final normalized = fullName.trim();

    if (normalized.isEmpty) {
      return 'U';
    }

    return normalized.substring(0, 1).toUpperCase();
  }
}

String _readString(dynamic value, String fieldName) {
  if (value is! String) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return value;
}

AppUserRole _readRole(dynamic value) {
  if (value == 'ADMIN') {
    return AppUserRole.admin;
  }

  if (value == 'CONTROL') {
    return AppUserRole.control;
  }

  return AppUserRole.external;
}
