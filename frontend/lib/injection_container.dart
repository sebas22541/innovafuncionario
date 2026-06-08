import 'features/auth/infrastructure/services/auth_api_service.dart';
import 'features/events/infrastructure/services/events_api_service.dart';
import 'features/lunches/infrastructure/services/lunches_api_service.dart';
import 'features/permissions/infrastructure/services/exit_permits_api_service.dart';
import 'features/reports/infrastructure/services/reports_api_service.dart';
import 'features/qr_scanner/domain/repositories/qr_details_repository.dart';
import 'features/qr_scanner/domain/usecases/get_qr_details_by_scan.dart';
import 'features/qr_scanner/infrastructure/datasources/api_qr_details_datasource.dart';
import 'features/qr_scanner/infrastructure/datasources/qr_details_datasource.dart';
import 'features/qr_scanner/infrastructure/repositories/qr_details_repository_impl.dart';
import 'shared/infrastructure/backend_api_client.dart';

late final AppDependencies dependencies;

Future<void> initDependencies() async {
  final backendApiClient = BackendApiClient();
  final qrDetailsDataSource = ApiQrDetailsDataSource(backendApiClient);
  final qrDetailsRepository = QrDetailsRepositoryImpl(qrDetailsDataSource);
  final eventsApiService = EventsApiService(backendApiClient);
  final exitPermitsApiService = ExitPermitsApiService(backendApiClient);
  final lunchesApiService = LunchesApiService(backendApiClient);
  final authApiService = AuthApiService(backendApiClient);
  final reportsApiService = ReportsApiService(backendApiClient);

  dependencies = AppDependencies._(
    authApiService: authApiService,
    backendApiClient: backendApiClient,
    eventsApiService: eventsApiService,
    exitPermitsApiService: exitPermitsApiService,
    lunchesApiService: lunchesApiService,
    reportsApiService: reportsApiService,
    qrDetailsDataSource: qrDetailsDataSource,
    qrDetailsRepository: qrDetailsRepository,
    getQrDetailsByScan: GetQrDetailsByScan(qrDetailsRepository),
  );
}

class AppDependencies {
  const AppDependencies._({
    required this.authApiService,
    required this.backendApiClient,
    required this.eventsApiService,
    required this.exitPermitsApiService,
    required this.lunchesApiService,
    required this.reportsApiService,
    required this.qrDetailsDataSource,
    required this.qrDetailsRepository,
    required this.getQrDetailsByScan,
  });

  final AuthApiService authApiService;
  final BackendApiClient backendApiClient;
  final EventsApiService eventsApiService;
  final ExitPermitsApiService exitPermitsApiService;
  final LunchesApiService lunchesApiService;
  final ReportsApiService reportsApiService;
  final QrDetailsDataSource qrDetailsDataSource;
  final QrDetailsRepository qrDetailsRepository;
  final GetQrDetailsByScan getQrDetailsByScan;
}
