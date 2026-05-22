class QrGenerationMapRecord {
  const QrGenerationMapRecord({
    required this.id,
    required this.source,
    required this.personaId,
    required this.userId,
    required this.fullName,
    required this.ci,
    required this.email,
    required this.officeName,
    required this.qrCode,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.generatedAt,
    required this.expiresAt,
    required this.eventId,
    required this.eventName,
    required this.controlId,
    required this.controlName,
    required this.status,
    required this.note,
    required this.registrationSource,
  });

  final String id;
  final QrGenerationMapSource source;
  final int personaId;
  final int? userId;
  final String fullName;
  final String ci;
  final String? email;
  final String? officeName;
  final String? qrCode;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime generatedAt;
  final DateTime? expiresAt;
  final int? eventId;
  final String? eventName;
  final int? controlId;
  final String? controlName;
  final String? status;
  final String? note;
  final String? registrationSource;
}

enum QrGenerationMapSource { eventScans, qrGenerations }

extension QrGenerationMapSourceX on QrGenerationMapSource {
  String get apiValue {
    switch (this) {
      case QrGenerationMapSource.eventScans:
        return 'eventos';
      case QrGenerationMapSource.qrGenerations:
        return 'generaciones';
    }
  }

  String get label {
    switch (this) {
      case QrGenerationMapSource.eventScans:
        return 'Solo eventos';
      case QrGenerationMapSource.qrGenerations:
        return 'QR generados';
    }
  }
}

enum QrGenerationMapFilter { user, ci }

extension QrGenerationMapFilterX on QrGenerationMapFilter {
  String get apiValue {
    switch (this) {
      case QrGenerationMapFilter.user:
        return 'usuario';
      case QrGenerationMapFilter.ci:
        return 'ci';
    }
  }

  String get label {
    switch (this) {
      case QrGenerationMapFilter.user:
        return 'Usuario';
      case QrGenerationMapFilter.ci:
        return 'CI';
    }
  }
}
