enum AppUserRole {
  admin,
  adminHealth,
  adminConsultants,
  adminTemporary,
  control,
  credentials,
  lunch,
  userReader,
  external,
}

extension AppUserRoleX on AppUserRole {
  String get apiValue {
    switch (this) {
      case AppUserRole.admin:
        return 'ADMIN';
      case AppUserRole.adminHealth:
        return 'ADMIN_SALUD';
      case AppUserRole.adminConsultants:
        return 'ADMIN_CONSULTORES';
      case AppUserRole.adminTemporary:
        return 'ADMIN_EVENTUALES';
      case AppUserRole.control:
        return 'CONTROL';
      case AppUserRole.credentials:
        return 'CREDENCIALES';
      case AppUserRole.lunch:
        return 'ALMUERZO';
      case AppUserRole.userReader:
        return 'LECTOR_USUARIOS';
      case AppUserRole.external:
        return 'OPERADOR';
    }
  }

  String get label {
    switch (this) {
      case AppUserRole.admin:
        return 'Administrador';
      case AppUserRole.adminHealth:
        return 'Admin (salud)';
      case AppUserRole.adminConsultants:
        return 'Admin (consultores)';
      case AppUserRole.adminTemporary:
        return 'Admin (eventuales)';
      case AppUserRole.control:
        return 'Control';
      case AppUserRole.credentials:
        return 'Credenciales';
      case AppUserRole.lunch:
        return 'Almuerzo';
      case AppUserRole.userReader:
        return 'Lector de usuarios';
      case AppUserRole.external:
        return 'Funcionario';
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
    required this.celular,
    required this.tipoVinculo,
    this.contratoNumero = '',
    this.contratoInicio,
    this.contratoFin,
    required this.unidad,
    required this.cargo,
    required this.lugar,
    required this.numeroItem,
    required this.activo,
    this.cargoCodigo,
    this.subcargoCodigo,
    this.subcargo = '',
    this.cargoEfectivoCodigo,
    this.cargoEfectivo = '',
    this.fotoUrl,
    this.officeId,
    this.officeName,
    this.officeCode,
    this.primaryOfficeId,
    this.primaryOfficeName,
    this.commissionOfficeId,
    this.commissionOfficeName,
    this.hasCommission = false,
    this.nombreVisible,
    this.personaId,
    this.qrCode,
    this.qrPayload,
    this.authToken,
  });

  final int? id;
  final String email;
  final AppUserRole role;
  final String nombreCompleto;
  final String primerApellido;
  final String segundoApellido;
  final String tercerApellido;
  final String ci;
  final String celular;
  final String tipoVinculo;
  final String contratoNumero;
  final String? contratoInicio;
  final String? contratoFin;
  final String unidad;
  final String cargo;
  final String lugar;
  final String numeroItem;
  final bool activo;
  final String? cargoCodigo;
  final String? subcargoCodigo;
  final String subcargo;
  final String? cargoEfectivoCodigo;
  final String cargoEfectivo;
  final String? fotoUrl;
  final int? officeId;
  final String? officeName;
  final String? officeCode;
  final int? primaryOfficeId;
  final String? primaryOfficeName;
  final int? commissionOfficeId;
  final String? commissionOfficeName;
  final bool hasCommission;
  final String? nombreVisible;
  final int? personaId;
  final String? qrCode;
  final String? qrPayload;
  final String? authToken;

  AppUser withAuthToken(String? authToken) {
    return AppUser(
      id: id,
      email: email,
      role: role,
      nombreCompleto: nombreCompleto,
      primerApellido: primerApellido,
      segundoApellido: segundoApellido,
      tercerApellido: tercerApellido,
      ci: ci,
      celular: celular,
      tipoVinculo: tipoVinculo,
      contratoNumero: contratoNumero,
      contratoInicio: contratoInicio,
      contratoFin: contratoFin,
      unidad: unidad,
      cargo: cargo,
      lugar: lugar,
      numeroItem: numeroItem,
      activo: activo,
      cargoCodigo: cargoCodigo,
      subcargoCodigo: subcargoCodigo,
      subcargo: subcargo,
      cargoEfectivoCodigo: cargoEfectivoCodigo,
      cargoEfectivo: cargoEfectivo,
      fotoUrl: fotoUrl,
      officeId: officeId,
      officeName: officeName,
      officeCode: officeCode,
      primaryOfficeId: primaryOfficeId,
      primaryOfficeName: primaryOfficeName,
      commissionOfficeId: commissionOfficeId,
      commissionOfficeName: commissionOfficeName,
      hasCommission: hasCommission,
      nombreVisible: nombreVisible,
      personaId: personaId,
      qrCode: qrCode,
      qrPayload: qrPayload,
      authToken: authToken,
    );
  }

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
      celular: source['celular'] as String? ?? '',
      tipoVinculo: _readString(source['tipoVinculo'], 'tipoVinculo'),
      contratoNumero: source['contratoNumero'] as String? ?? '',
      contratoInicio: source['contratoInicio'] as String?,
      contratoFin: source['contratoFin'] as String?,
      unidad: _readString(source['unidad'], 'unidad'),
      cargo: _readString(source['cargo'], 'cargo'),
      lugar: source['lugar'] as String? ?? '',
      numeroItem: _readString(source['numeroItem'], 'numeroItem'),
      activo: source['activo'] as bool? ?? true,
      cargoCodigo: source['cargoCodigo'] as String?,
      subcargoCodigo: source['subcargoCodigo'] as String?,
      subcargo: source['subcargo'] as String? ?? '',
      cargoEfectivoCodigo: source['cargoEfectivoCodigo'] as String?,
      cargoEfectivo: source['cargoEfectivo'] as String? ?? '',
      fotoUrl: (source['fotoUrl'] ?? source['fotoBase64']) as String?,
      officeId: source['oficinaId'] as int?,
      officeName: source['oficinaNombre'] as String?,
      officeCode: source['oficinaCodigo'] as String?,
      primaryOfficeId: source['oficinaPrincipalId'] as int?,
      primaryOfficeName: source['oficinaPrincipalNombre'] as String?,
      commissionOfficeId: source['oficinaComisionId'] as int?,
      commissionOfficeName: source['oficinaComisionNombre'] as String?,
      hasCommission: source['tieneComision'] as bool? ?? false,
      nombreVisible: source['nombreVisible'] as String?,
      personaId: source['personaId'] as int?,
      qrCode: source['qrCode'] as String?,
      qrPayload: source['qrPayload'] as String?,
      authToken: source['authToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'rol': role.apiValue,
      'nombreCompleto': nombreCompleto,
      'primerApellido': primerApellido,
      'segundoApellido': segundoApellido,
      'tercerApellido': tercerApellido,
      'ci': ci,
      'celular': celular,
      'tipoVinculo': tipoVinculo,
      'contratoNumero': contratoNumero,
      'contratoInicio': contratoInicio,
      'contratoFin': contratoFin,
      'unidad': unidad,
      'cargo': cargo,
      'lugar': lugar,
      'cargoCodigo': cargoCodigo,
      'subcargoCodigo': subcargoCodigo,
      'subcargo': subcargo,
      'cargoEfectivoCodigo': cargoEfectivoCodigo,
      'cargoEfectivo': cargoEfectivo,
      'numeroItem': numeroItem,
      'activo': activo,
      'fotoUrl': fotoUrl,
      'oficinaId': officeId,
      'oficinaNombre': officeName,
      'oficinaCodigo': officeCode,
      'oficinaPrincipalId': primaryOfficeId,
      'oficinaPrincipalNombre': primaryOfficeName,
      'oficinaComisionId': commissionOfficeId,
      'oficinaComisionNombre': commissionOfficeName,
      'tieneComision': hasCommission,
      'nombreVisible': nombreVisible,
      'personaId': personaId,
      'qrCode': qrCode,
      'qrPayload': qrPayload,
      'authToken': authToken,
    };
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

  bool get isAdmin =>
      role == AppUserRole.admin || role == AppUserRole.adminHealth;

  bool get isAdminHealth => role == AppUserRole.adminHealth;

  bool get isAdminConsultants => role == AppUserRole.adminConsultants;

  bool get isAdminTemporary => role == AppUserRole.adminTemporary;

  bool get isScopedUserAdmin =>
      isAdminHealth || isAdminConsultants || isAdminTemporary;

  bool get canManageUsers => isAdmin || isScopedUserAdmin;

  bool get canEditUsers => canManageUsers;

  bool get canViewUsers => canManageUsers || role == AppUserRole.userReader;

  bool get isControl => role == AppUserRole.control;

  bool get isCredentials => role == AppUserRole.credentials;

  bool get isLunchControl => role == AppUserRole.lunch;

  bool get isUserReader => role == AppUserRole.userReader;

  bool get isExternalUser => role == AppUserRole.external;

  bool get canManageEvents => isAdmin;

  bool get canUseEventsPanel => isAdmin || isControl;

  bool get canUseEventScanner => isAdmin || isControl;

  String? get effectiveCargoCode {
    final effective = cargoEfectivoCodigo?.trim();
    if (effective != null && effective.isNotEmpty) {
      return effective;
    }

    final sub = subcargoCodigo?.trim();
    if (sub != null && sub.isNotEmpty) {
      return sub;
    }

    if (subcargo.trim().isNotEmpty) {
      return null;
    }

    final base = cargoCodigo?.trim();
    return base == null || base.isEmpty ? null : base;
  }

  String get effectiveCargo {
    final effective = cargoEfectivo.trim();
    if (effective.isNotEmpty) {
      return effective;
    }

    final sub = subcargo.trim();
    if (sub.isNotEmpty) {
      return sub;
    }

    return cargo;
  }

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

  if (value == 'ADMIN_SALUD') {
    return AppUserRole.adminHealth;
  }

  if (value == 'ADMIN_CONSULTORES') {
    return AppUserRole.adminConsultants;
  }

  if (value == 'ADMIN_EVENTUALES') {
    return AppUserRole.adminTemporary;
  }

  if (value == 'CONTROL') {
    return AppUserRole.control;
  }

  if (value == 'CREDENCIALES') {
    return AppUserRole.credentials;
  }

  if (value == 'ALMUERZO') {
    return AppUserRole.lunch;
  }

  if (value == 'LECTOR_USUARIOS') {
    return AppUserRole.userReader;
  }

  return AppUserRole.external;
}
