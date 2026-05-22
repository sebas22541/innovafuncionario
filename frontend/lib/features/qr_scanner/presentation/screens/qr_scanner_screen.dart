import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../events/domain/entities/event_record.dart';
import '../../domain/entities/qr_scan_result.dart';
import '../../infrastructure/models/qr_scan_result_model.dart';
import '../widgets/qr_scanner_overlay.dart';
import '../widgets/scanner_result_panel.dart';
import 'qr_scan_details_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.currentUser,
    this.activeEventId,
    this.activeEventName,
    this.activeEventOffices = const [],
    this.activeEventControls = const [],
  });

  final AppUser currentUser;
  final int? activeEventId;
  final String? activeEventName;
  final List<EventOffice> activeEventOffices;
  final List<EventControl> activeEventControls;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  // La camara se limita a QR para evitar ruido de otros codigos de barras.
  final MobileScannerController _controller = MobileScannerController(
    autoStart: true,
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 800,
    formats: const [BarcodeFormat.qrCode],
  );

  QrScanResultModel? _lastScanModel;
  final TextEditingController _ciController = TextEditingController();
  bool _isHandlingDetection = false;
  bool _isSearchingCi = false;

  @override
  void dispose() {
    _ciController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDetailsScreen({
    required QrScanResult scanResult,
    String? manualCi,
    dynamic prefetchedQrDetails,
  }) async {
    _isHandlingDetection = true;

    await _controller.stop();

    if (!mounted) {
      return;
    }

    final resultMessage = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => QrScanDetailsScreen(
          scanResult: scanResult,
          currentUser: widget.currentUser,
          activeEventId: widget.activeEventId,
          activeEventName: widget.activeEventName,
          activeEventOffices: widget.activeEventOffices,
          activeEventControls: widget.activeEventControls,
          manualCi: manualCi,
          prefetchedQrDetails: prefetchedQrDetails,
        ),
      ),
    );

    if (mounted && resultMessage != null && resultMessage.isNotEmpty) {
      AppAlert.showSuccess(context, resultMessage);
    }

    await _restartScanner();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    // Flujo visual de escaneo:
    // camara -> primer QR detectado -> detalle del QR -> posible registro -> reinicio.
    if (_isHandlingDetection || capture.barcodes.isEmpty) {
      return;
    }

    final barcode = capture.barcodes.first;
    final scanModel = QrScanResultModel.fromBarcode(barcode);

    if (scanModel.value.isEmpty) {
      return;
    }

    _isHandlingDetection = true;

    if (mounted) {
      setState(() {
        _lastScanModel = scanModel;
      });
    }

    await _openDetailsScreen(scanResult: scanModel.toEntity());
  }

  Future<void> _searchByCi() async {
    final ci = _ciController.text.trim();

    if (ci.length < 3) {
      AppAlert.showWarning(context, 'Ingresa un CI valido para buscar.');
      return;
    }

    FocusScope.of(context).unfocus();
    _isHandlingDetection = true;

    setState(() {
      _isSearchingCi = true;
    });

    try {
      final result = await dependencies.qrDetailsDataSource.getByCi(
        ci,
        eventId: widget.activeEventId,
      );

      if (!mounted) {
        return;
      }

      if (result == null) {
        AppAlert.showWarning(context, 'No se encontro una persona con ese CI.');
        return;
      }

      await _openDetailsScreen(
        scanResult: QrScanResult(
          value: 'CI:${ci.toUpperCase()}',
          displayValue: 'CI ${ci.toUpperCase()}',
          format: 'BUSQUEDA MANUAL',
          payloadType: 'CI',
          payloadFields: {'ci': ci.toUpperCase()},
          scannedAt: DateTime.now(),
        ),
        manualCi: ci,
        prefetchedQrDetails: result.toEntity(),
      );
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible buscar la persona por CI.');
    } finally {
      _isHandlingDetection = false;
      if (mounted) {
        setState(() {
          _isSearchingCi = false;
        });
      }
    }
  }

  Future<void> _restartScanner() async {
    // Se reinicia manualmente para evitar multiples registros de la misma lectura.
    if (!mounted) {
      return;
    }

    setState(() {
      _lastScanModel = null;
    });

    _isHandlingDetection = true;

    await _controller.stop();
    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!mounted) {
      return;
    }

    await _controller.start();
    _isHandlingDetection = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.activeEventName != null) ...[
                _ActiveEventCard(eventName: widget.activeEventName!),
                const SizedBox(height: 12),
              ],
              _ManualCiSearchCard(
                controller: _ciController,
                isSearching: _isSearchingCi,
                onSearch: _searchByCi,
              ),
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _ScannerViewport(
                        controller: _controller,
                        isScannerActive: _lastScanModel == null,
                        onDetect: _handleDetect,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          const _ScannerTipsCard(),
                          const SizedBox(height: 12),
                          ScannerResultPanel(
                            lastScan: _lastScanModel?.toEntity(),
                            onRestart: _restartScanner,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                const _ScannerTipsCard(),
                const SizedBox(height: 12),
                _ScannerViewport(
                  controller: _controller,
                  isScannerActive: _lastScanModel == null,
                  onDetect: _handleDetect,
                ),
                const SizedBox(height: 12),
                ScannerResultPanel(
                  lastScan: _lastScanModel?.toEntity(),
                  onRestart: _restartScanner,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ActiveEventCard extends StatelessWidget {
  const _ActiveEventCard({required this.eventName});

  final String eventName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: AppPalette.orange,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evento seleccionado',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    eventName,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualCiSearchCard extends StatelessWidget {
  const _ManualCiSearchCard({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registrar por CI',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Busca por CI y abre el mismo detalle del escaneo para registrar a la persona solo como Observado.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                labelText: 'Buscar por CI',
                hintText: 'Ingresa el CI de la persona',
                prefixIcon: const Icon(Icons.badge_rounded),
                suffixIcon: isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: onSearch,
                        icon: const Icon(Icons.search_rounded),
                        tooltip: 'Buscar CI',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerTipsCard extends StatelessWidget {
  const _ScannerTipsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Sugerencias de uso',
              style: TextStyle(
                color: AppPalette.ink,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            SizedBox(height: 12),
            _ScannerTipItem(
              title: 'Alinea el codigo',
              description: 'Mantelo dentro del marco hasta confirmar lectura.',
            ),
            SizedBox(height: 10),
            _ScannerTipItem(
              title: 'Evita reflejos',
              description: 'Mejora el enfoque con luz uniforme sobre el QR.',
            ),
            SizedBox(height: 10),
            _ScannerTipItem(
              title: 'Revisa el detalle',
              description:
                  'Despues de detectar el codigo, valida la informacion.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerTipItem extends StatelessWidget {
  const _ScannerTipItem({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppPalette.orangeSoft,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.check_rounded,
            size: 16,
            color: AppPalette.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScannerViewport extends StatelessWidget {
  const _ScannerViewport({
    required this.controller,
    required this.isScannerActive,
    required this.onDetect,
  });

  final MobileScannerController controller;
  final bool isScannerActive;
  final void Function(BarcodeCapture capture) onDetect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 0.95).clamp(420.0, 620.0);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MobileScanner(
                        controller: controller,
                        fit: BoxFit.cover,
                        onDetect: onDetect,
                        errorBuilder: (context, error) {
                          return _ScannerErrorState(error: error);
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: QrScannerOverlay(isActive: isScannerActive),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 16,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xA154407E),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppPalette.orange.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: Text(
                              isScannerActive ? 'Escaneando' : 'Lectura lista',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xA154407E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          isScannerActive
                              ? 'Alinea el codigo dentro del marco.'
                              : 'Codigo detectado. Revisa el detalle o vuelve a escanear.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScannerErrorState extends StatelessWidget {
  const _ScannerErrorState({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    String message;

    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        message =
            'Permite el acceso a la camara en el navegador y vuelve a cargar la pagina.';
      case MobileScannerErrorCode.unsupported:
        message = 'Este navegador o dispositivo no permite el lector QR.';
      default:
        message = 'No fue posible iniciar la camara. Verifica los permisos.';
    }

    return Container(
      color: AppPalette.nightDeep,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white,
                size: 42,
              ),
              const SizedBox(height: 16),
              const Text(
                'Camara no disponible',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppPalette.onDarkMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
