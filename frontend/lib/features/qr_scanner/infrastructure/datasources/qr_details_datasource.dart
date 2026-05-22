import '../models/qr_details_model.dart';

abstract class QrDetailsDataSource {
  Future<QrDetailsModel?> getByLookupCode(String lookupCode, {int? eventId});
  Future<QrDetailsModel?> getByCi(String ci, {int? eventId});
}
