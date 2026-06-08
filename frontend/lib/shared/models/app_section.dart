import 'package:flutter/material.dart';

enum AppSection {
  home,
  events,
  availableEvents,
  reports,
  map,
  users,
  credentials,
  permissionExits,
  myExitPermits,
  exitPermitRequests,
  lunches,
  lunchScanner,
  qrScanner,
  myQr,
  settings,
}

extension AppSectionX on AppSection {
  String get storageKey => name;

  String get label {
    switch (this) {
      case AppSection.home:
        return 'Inicio';
      case AppSection.events:
        return 'Eventos';
      case AppSection.availableEvents:
        return 'Eventos';
      case AppSection.reports:
        return 'Reportes';
      case AppSection.map:
        return 'Mapa';
      case AppSection.users:
        return 'Usuarios';
      case AppSection.credentials:
        return 'Credenciales';
      case AppSection.permissionExits:
        return 'Salidas';
      case AppSection.myExitPermits:
        return 'Mis solicitudes';
      case AppSection.exitPermitRequests:
        return 'Solicitudes recibidas';
      case AppSection.lunches:
        return 'Almuerzos';
      case AppSection.lunchScanner:
        return 'Escaner almuerzo';
      case AppSection.qrScanner:
        return 'Escanear';
      case AppSection.myQr:
        return 'Mi QR';
      case AppSection.settings:
        return 'Perfil';
    }
  }

  String get title {
    switch (this) {
      case AppSection.home:
        return 'Panel operativo';
      case AppSection.events:
        return 'Gestion de eventos';
      case AppSection.availableEvents:
        return 'Eventos por oficina';
      case AppSection.reports:
        return 'Reportes y consultas';
      case AppSection.map:
        return 'Mapa de QR';
      case AppSection.users:
        return 'Gestion de usuarios';
      case AppSection.credentials:
        return 'Credenciales';
      case AppSection.permissionExits:
        return 'Permisos';
      case AppSection.myExitPermits:
        return 'Mis solicitudes';
      case AppSection.exitPermitRequests:
        return 'Solicitudes recibidas';
      case AppSection.lunches:
        return 'Control de almuerzos';
      case AppSection.lunchScanner:
        return 'Escaner de almuerzo';
      case AppSection.qrScanner:
        return 'Escaneo QR';
      case AppSection.myQr:
        return 'Mi QR';
      case AppSection.settings:
        return 'Perfil y ajustes';
    }
  }

  IconData get icon {
    switch (this) {
      case AppSection.home:
        return Icons.home_rounded;
      case AppSection.events:
        return Icons.event_note_rounded;
      case AppSection.availableEvents:
        return Icons.event_available_rounded;
      case AppSection.reports:
        return Icons.assessment_outlined;
      case AppSection.map:
        return Icons.map_outlined;
      case AppSection.users:
        return Icons.people_alt_outlined;
      case AppSection.credentials:
        return Icons.badge_outlined;
      case AppSection.permissionExits:
        return Icons.exit_to_app_rounded;
      case AppSection.myExitPermits:
        return Icons.assignment_outlined;
      case AppSection.exitPermitRequests:
        return Icons.assignment_turned_in_outlined;
      case AppSection.lunches:
        return Icons.restaurant_menu_rounded;
      case AppSection.lunchScanner:
        return Icons.qr_code_scanner_rounded;
      case AppSection.qrScanner:
        return Icons.qr_code_scanner_rounded;
      case AppSection.myQr:
        return Icons.qr_code_2_rounded;
      case AppSection.settings:
        return Icons.person_outline_rounded;
    }
  }
}

AppSection? parseAppSection(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  for (final section in AppSection.values) {
    if (section.storageKey == value.trim()) {
      return section;
    }
  }

  return null;
}
