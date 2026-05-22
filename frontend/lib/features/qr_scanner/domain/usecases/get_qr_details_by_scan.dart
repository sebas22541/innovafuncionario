import '../entities/qr_details.dart';
import '../repositories/qr_details_repository.dart';

class GetQrDetailsByScan {
  const GetQrDetailsByScan(this._repository);

  final QrDetailsRepository _repository;

  Future<QrDetails?> call(String scannedValue, {int? eventId}) async {
    final normalizedValue = scannedValue.trim();

    if (normalizedValue.isEmpty) {
      return null;
    }

    return _repository.getByScannedValue(normalizedValue, eventId: eventId);
  }
}
