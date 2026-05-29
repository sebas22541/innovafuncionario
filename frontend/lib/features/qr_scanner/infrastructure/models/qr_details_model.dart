import '../../domain/entities/qr_details.dart';

class QrEventControlRecordModel {
  const QrEventControlRecordModel({
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

  QrEventControlRecord toEntity() {
    return QrEventControlRecord(
      id: id,
      controlId: controlId,
      controlName: controlName,
      controlOrder: controlOrder,
      status: status,
      registeredAt: registeredAt,
      note: note,
    );
  }
}

class QrEventAttendanceRecordModel {
  const QrEventAttendanceRecordModel({
    required this.status,
    required this.registeredAt,
    this.controls = const [],
    this.registeredControlsCount = 0,
    this.attendedControlsCount = 0,
    this.observedControlsCount = 0,
  });

  final String status;
  final DateTime registeredAt;
  final List<QrEventControlRecordModel> controls;
  final int registeredControlsCount;
  final int attendedControlsCount;
  final int observedControlsCount;

  QrEventAttendanceRecord toEntity() {
    return QrEventAttendanceRecord(
      status: status,
      registeredAt: registeredAt,
      controls: controls.map((control) => control.toEntity()).toList(
        growable: false,
      ),
      registeredControlsCount: registeredControlsCount,
      attendedControlsCount: attendedControlsCount,
      observedControlsCount: observedControlsCount,
    );
  }
}

class QrDetailsModel {
  const QrDetailsModel({
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
  final QrEventAttendanceRecordModel? eventAttendance;

  factory QrDetailsModel.fromMap(Map<String, dynamic> map) {
    return QrDetailsModel(
      id: map['id'] as String,
      code: map['code'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      status: map['status'] as String,
      fields: Map<String, String>.from(map['fields'] as Map),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      officeId: map['officeId'] as int?,
      officeName: map['officeName'] as String?,
      officeCode: map['officeCode'] as String?,
      cargoCodigo: map['cargoCodigo'] as String?,
      photoUrl: (map['photoUrl'] ?? map['photoBase64']) as String?,
      eventAttendance: null,
    );
  }

  QrDetails toEntity() {
    return QrDetails(
      id: id,
      code: code,
      title: title,
      description: description,
      status: status,
      fields: fields,
      updatedAt: updatedAt,
      officeId: officeId,
      officeName: officeName,
      officeCode: officeCode,
      cargoCodigo: cargoCodigo,
      photoUrl: photoUrl,
      eventAttendance: eventAttendance?.toEntity(),
    );
  }
}
