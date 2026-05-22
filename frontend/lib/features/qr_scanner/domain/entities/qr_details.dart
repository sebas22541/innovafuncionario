class QrEventControlRecord {
  const QrEventControlRecord({
    required this.id,
    required this.controlId,
    required this.controlName,
    required this.controlOrder,
    required this.status,
    required this.registeredAt,
    this.note,
  });

  final int id;
  final int controlId;
  final String controlName;
  final int controlOrder;
  final String status;
  final DateTime registeredAt;
  final String? note;

  bool get isAttended => status == 'ASISTIO';
}

class QrEventAttendanceRecord {
  const QrEventAttendanceRecord({
    required this.status,
    required this.registeredAt,
    this.controls = const [],
    this.registeredControlsCount = 0,
    this.attendedControlsCount = 0,
    this.observedControlsCount = 0,
  });

  final String status;
  final DateTime registeredAt;
  final List<QrEventControlRecord> controls;
  final int registeredControlsCount;
  final int attendedControlsCount;
  final int observedControlsCount;
}

class QrDetails {
  const QrDetails({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.status,
    required this.fields,
    required this.updatedAt,
    this.officeId,
    this.officeName,
    this.officeCode,
    this.photoUrl,
    this.eventAttendance,
  });

  final String id;
  final String code;
  final String title;
  final String description;
  final String status;
  final Map<String, String> fields;
  final DateTime updatedAt;
  final int? officeId;
  final String? officeName;
  final String? officeCode;
  final String? photoUrl;
  final QrEventAttendanceRecord? eventAttendance;
}
