const lunchRegistrationQrPayload = 'INNOVA_FUNCIONARIO:ALMUERZO:REGISTRO:1';
const exitPermitRegistrationQrPayload = 'INNOVA_FUNCIONARIO:SALIDAS:REGISTRO:1';

enum AttendanceRegistrationQrType { lunch, exitPermit }

AttendanceRegistrationQrType? parseAttendanceRegistrationQr(String value) {
  final normalized = value.trim();

  if (normalized == lunchRegistrationQrPayload) {
    return AttendanceRegistrationQrType.lunch;
  }

  if (normalized == exitPermitRegistrationQrPayload) {
    return AttendanceRegistrationQrType.exitPermit;
  }

  return null;
}
