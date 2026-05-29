enum EventListType { attended, observed }

class EventControl {
  const EventControl({
    required this.id,
    required this.name,
    required this.order,
  });

  final int id;
  final String name;
  final int order;
}

class EventControlDraft {
  const EventControlDraft({
    required this.name,
    this.id,
  });

  final int? id;
  final String name;
}

class EventAttendanceControl {
  const EventAttendanceControl({
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
    this.controls = const [],
    this.registeredControlsCount = 0,
    this.attendedControlsCount = 0,
    this.observedControlsCount = 0,
    this.ci,
    this.tipoVinculo,
    this.officeName,
    this.qrValue,
  });

  final int id;
  final int personId;
  final String fullName;
  final String note;
  final DateTime registeredAt;
  final List<EventAttendanceControl> controls;
  final int registeredControlsCount;
  final int attendedControlsCount;
  final int observedControlsCount;
  final String? ci;
  final String? tipoVinculo;
  final String? officeName;
  final String? qrValue;
}

class EventRecordDraft {
  const EventRecordDraft({
    required this.name,
    required this.date,
    required this.officeIds,
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
    this.attendedCount,
    this.observedCount,
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
  final int? attendedCount;
  final int? observedCount;
  final bool hasDetailedAttendanceData;

  int get resolvedAttendedCount => attendedCount ?? attended.length;

  int get resolvedObservedCount => observedCount ?? observed.length;

  int get totalTrackedPeople => resolvedAttendedCount + resolvedObservedCount;

  int get officeCount => offices.length;

  String get officeCountLabel {
    if (officeCount == 1) {
      return '1 oficina';
    }

    return '$officeCount oficinas';
  }

  String get officeLabel {
    if (offices.isEmpty) {
      return 'Sin oficinas';
    }

    return officeCountLabel;
  }

  String get officeNames => offices.map((office) => office.name).join(', ');

  int get jobTitleCount => jobTitles.length;

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
