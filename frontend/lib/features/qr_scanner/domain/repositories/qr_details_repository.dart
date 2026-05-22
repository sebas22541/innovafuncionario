import '../entities/qr_details.dart';

abstract class QrDetailsRepository {
  Future<QrDetails?> getByScannedValue(String scannedValue, {int? eventId});
}
