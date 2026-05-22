enum AttendanceReportFilter { all, attended, observed }

class AttendanceReportPerson {
  const AttendanceReportPerson({
    required this.id,
    required this.ci,
    required this.fullName,
    required this.isActive,
    this.personaId,
    this.userId,
    this.officeName,
    this.jobTitle,
    this.tipoVinculo,
    this.numeroItem,
    this.email,
    this.photoUrl,
    this.qrCode,
  });

  final int id;
  final int? personaId;
  final int? userId;
  final String ci;
  final String fullName;
  final String? officeName;
  final String? jobTitle;
  final String? tipoVinculo;
  final String? numeroItem;
  final String? email;
  final String? photoUrl;
  final String? qrCode;
  final bool isActive;
}

class AttendanceReportRecord {
  const AttendanceReportRecord({
    required this.id,
    required this.personId,
    required this.ci,
    required this.fullName,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.registeredAt,
    required this.status,
    this.officeName,
    this.eventAddress,
    this.note,
  });

  final int id;
  final int personId;
  final String ci;
  final String fullName;
  final String? officeName;
  final int eventId;
  final String eventName;
  final DateTime eventDate;
  final DateTime registeredAt;
  final String status;
  final String? eventAddress;
  final String? note;

  bool get isAttended => status == 'ASISTIO';
}

class AttendanceReport {
  const AttendanceReport({
    required this.person,
    required this.records,
    required this.filter,
  });

  final AttendanceReportPerson person;
  final List<AttendanceReportRecord> records;
  final AttendanceReportFilter filter;
}
