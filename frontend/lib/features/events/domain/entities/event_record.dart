enum EventListType { attended, observed }

class EventControl {
  const EventControl({
    required this.id,
    required this.name,
    required this.order,
    this.startTime,
    this.endTime,
  });

  final int id;
  final String name;
  final int order;
  final String? startTime;
  final String? endTime;

  bool get hasTimeWindow => startTime != null && endTime != null;

  String get timeWindowLabel =>
      hasTimeWindow ? '$startTime a $endTime' : 'Sin restriccion horaria';
}

class EventControlDraft {
  const EventControlDraft({
    required this.name,
    required this.startTime,
    required this.endTime,
    this.id,
  });

  final int? id;
  final String name;
  final String startTime;
  final String endTime;
}

class EventAttendanceControl {
  const EventAttendanceControl({
    required this.id,
    required this.controlId,
    required this.controlName,
    required this.controlOrder,
    required this.status,
    required this.registeredAt,
    this.isLate = false,
    this.note,
  });

  final int id;
  final int controlId;
  final String controlName;
  final int controlOrder;
  final String status;
  final DateTime registeredAt;
  final bool isLate;
  final String? note;

  bool get isAttended => status == 'ASISTIO';
}

class EventOffice {
  const EventOffice({
    required this.id,
    required this.name,
    required this.code,
    required this.level,
  });

  final int id;
  final String name;
  final String code;
  final int level;

  String get displayLabel => '$name | Cod. $code';
}

class EventJobTitle {
  const EventJobTitle({required this.code, required this.name});

  final String code;
  final String name;

  String get displayLabel => '$name | Cod. $code';
}

class EventOfficeJobTitleSelection {
  const EventOfficeJobTitleSelection({
    required this.officeId,
    required this.jobTitleCodes,
  });

  final int officeId;
  final List<String> jobTitleCodes;

  bool get allowsAllJobTitles => jobTitleCodes.isEmpty;
}

class EventRosterEntry {
  const EventRosterEntry({
    required this.id,
    required this.personId,
    required this.fullName,
    required this.note,
    required this.registeredAt,
    this.lateRegisteredAt,
    this.controls = const [],
    this.registeredControlsCount = 0,
    this.attendedControlsCount = 0,
    this.observedControlsCount = 0,
    this.ci,
    this.numeroItem,
    this.tipoVinculo,
    this.officeName,
    this.jobTitle,
    this.qrValue,
  });

  final int id;
  final int personId;
  final String fullName;
  final String note;
  final DateTime registeredAt;
  final DateTime? lateRegisteredAt;
  final List<EventAttendanceControl> controls;
  final int registeredControlsCount;
  final int attendedControlsCount;
  final int observedControlsCount;
  final String? ci;
  final String? numeroItem;
  final String? tipoVinculo;
  final String? officeName;
  final String? jobTitle;
  final String? qrValue;

  bool get isLate => lateRegisteredAt != null;
}

class EventAbsenteeEntry {
  const EventAbsenteeEntry({
    required this.personId,
    required this.fullName,
    this.ci,
    this.tipoVinculo,
    this.officeName,
    this.jobTitle,
    this.requirementReason,
  });

  final int personId;
  final String fullName;
  final String? ci;
  final String? tipoVinculo;
  final String? officeName;
  final String? jobTitle;
  final String? requirementReason;
}

class EventRecordDraft {
  const EventRecordDraft({
    required this.name,
    required this.date,
    required this.officeIds,
    this.finalOfficeIds = const [],
    required this.jobTitleCodes,
    this.officeJobTitleSelections = const [],
    this.excludedOfficeIds = const [],
    required this.controls,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final DateTime date;
  final List<int> officeIds;
  final List<int> finalOfficeIds;
  final List<String> jobTitleCodes;
  final List<EventOfficeJobTitleSelection> officeJobTitleSelections;
  final List<int> excludedOfficeIds;
  final List<EventControlDraft> controls;
  final String address;
  final double latitude;
  final double longitude;
}

class EventRecord {
  const EventRecord({
    required this.id,
    required this.name,
    required this.date,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.address,
    this.latitude,
    this.longitude,
    this.controls = const [],
    this.offices = const [],
    this.jobTitles = const [],
    this.selectedJobTitleCodes = const [],
    this.officeJobTitleSelections = const [],
    this.selectedOfficeIds = const [],
    this.excludedOfficeIds = const [],
    this.attended = const [],
    this.observed = const [],
    this.late = const [],
    this.nonRequired = const [],
    this.absentees = const [],
    this.attendedCount,
    this.observedCount,
    this.lateCount,
    this.nonRequiredCount,
    this.absenteeCount,
    this.officeCountOverride,
    this.jobTitleCountOverride,
    this.hasDetailedAttendanceData = true,
  });

  final int id;
  final String name;
  final DateTime date;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? address;
  final double? latitude;
  final double? longitude;
  final List<EventControl> controls;
  final List<EventOffice> offices;
  final List<EventJobTitle> jobTitles;
  final List<String> selectedJobTitleCodes;
  final List<EventOfficeJobTitleSelection> officeJobTitleSelections;
  final List<int> selectedOfficeIds;
  final List<int> excludedOfficeIds;
  final List<EventRosterEntry> attended;
  final List<EventRosterEntry> observed;
  final List<EventRosterEntry> late;
  final List<EventRosterEntry> nonRequired;
  final List<EventAbsenteeEntry> absentees;
  final int? attendedCount;
  final int? observedCount;
  final int? lateCount;
  final int? nonRequiredCount;
  final int? absenteeCount;
  final int? officeCountOverride;
  final int? jobTitleCountOverride;
  final bool hasDetailedAttendanceData;

  int get resolvedAttendedCount => attendedCount ?? attended.length;

  int get resolvedObservedCount => observedCount ?? observed.length;

  int get resolvedLateCount => lateCount ?? late.length;

  int get resolvedNonRequiredCount => nonRequiredCount ?? nonRequired.length;

  int get resolvedAbsenteeCount => absenteeCount ?? absentees.length;

  int get totalTrackedPeople =>
      resolvedAttendedCount + resolvedObservedCount + resolvedAbsenteeCount;

  int get officeCount => officeCountOverride ?? offices.length;

  String get officeCountLabel {
    if (officeCount == 0 && jobTitleCount > 0) {
      return 'Por cargos';
    }

    if (officeCount == 0) {
      return 'Sin oficinas';
    }

    if (officeCount == 1) {
      return '1 oficina';
    }

    return '$officeCount oficinas';
  }

  String get officeLabel {
    if (offices.isEmpty && jobTitleCount > 0) {
      return 'Por cargos';
    }

    if (offices.isEmpty) {
      return 'Sin oficinas';
    }

    return officeCountLabel;
  }

  String get officeNames => offices.map((office) => office.name).join(', ');

  int get jobTitleCount => jobTitleCountOverride ?? jobTitles.length;

  String get jobTitleCountLabel {
    if (jobTitleCount == 0) {
      return 'Todos los cargos';
    }

    if (jobTitleCount == 1) {
      return '1 cargo';
    }

    return '$jobTitleCount cargos';
  }

  int get controlsCount => controls.length;

  String get controlsLabel {
    if (controlsCount == 1) {
      return '1 control';
    }

    return '$controlsCount controles';
  }

  bool get hasLocation => latitude != null && longitude != null;
}
