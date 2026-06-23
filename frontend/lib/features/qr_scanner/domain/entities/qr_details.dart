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

  QrEventAttendanceRecord copyWith({
    String? status,
    DateTime? registeredAt,
    List<QrEventControlRecord>? controls,
    int? registeredControlsCount,
    int? attendedControlsCount,
    int? observedControlsCount,
  }) {
    return QrEventAttendanceRecord(
      status: status ?? this.status,
      registeredAt: registeredAt ?? this.registeredAt,
      controls: controls ?? this.controls,
      registeredControlsCount:
          registeredControlsCount ?? this.registeredControlsCount,
      attendedControlsCount:
          attendedControlsCount ?? this.attendedControlsCount,
      observedControlsCount:
          observedControlsCount ?? this.observedControlsCount,
    );
  }
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
    this.cargoCodigo,
    this.photoUrl,
    this.eventAttendance,
    this.canRegisterInActiveEvent,
    this.eventRegistrationMessage,
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
  final String? cargoCodigo;
  final String? photoUrl;
  final QrEventAttendanceRecord? eventAttendance;
  final bool? canRegisterInActiveEvent;
  final String? eventRegistrationMessage;

  QrDetails copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    String? status,
    Map<String, String>? fields,
    DateTime? updatedAt,
    int? officeId,
    String? officeName,
    String? officeCode,
    String? cargoCodigo,
    String? photoUrl,
    QrEventAttendanceRecord? eventAttendance,
    bool? canRegisterInActiveEvent,
    String? eventRegistrationMessage,
  }) {
    return QrDetails(
      id: id ?? this.id,
      code: code ?? this.code,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      fields: fields ?? this.fields,
      updatedAt: updatedAt ?? this.updatedAt,
      officeId: officeId ?? this.officeId,
      officeName: officeName ?? this.officeName,
      officeCode: officeCode ?? this.officeCode,
      cargoCodigo: cargoCodigo ?? this.cargoCodigo,
      photoUrl: photoUrl ?? this.photoUrl,
      eventAttendance: eventAttendance ?? this.eventAttendance,
      canRegisterInActiveEvent:
          canRegisterInActiveEvent ?? this.canRegisterInActiveEvent,
      eventRegistrationMessage:
          eventRegistrationMessage ?? this.eventRegistrationMessage,
    );
  }
}
