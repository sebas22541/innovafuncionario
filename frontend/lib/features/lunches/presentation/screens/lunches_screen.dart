import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../qr_scanner/infrastructure/models/qr_scan_result_model.dart';
import '../../../qr_scanner/presentation/widgets/qr_scanner_overlay.dart';
import '../../infrastructure/services/lunches_api_service.dart';

class LunchScannerScreen extends StatefulWidget {
  const LunchScannerScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<LunchScannerScreen> createState() => _LunchScannerScreenState();
}

class _LunchScannerScreenState extends State<LunchScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: true,
    facing: CameraFacing.front,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 900,
    formats: const [BarcodeFormat.qrCode],
  );

  LunchScanResponse? _lastResponse;
  String? _lastError;
  bool _isHandlingDetection = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_isHandlingDetection || capture.barcodes.isEmpty) {
      return;
    }

    final scan = QrScanResultModel.fromBarcode(capture.barcodes.first);

    if (scan.value.isEmpty) {
      return;
    }

    setState(() {
      _isHandlingDetection = true;
      _lastError = null;
    });

    await _controller.stop();

    try {
      final response = await dependencies.lunchesApiService.registerScan(
        qrValue: scan.value,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _lastResponse = response;
      });
      AppAlert.showSuccess(context, response.message);
    } on BackendApiException catch (error) {
      if (mounted) {
        setState(() {
          _lastError = error.message;
        });
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        const message = 'No fue posible registrar el almuerzo.';
        setState(() {
          _lastError = message;
        });
        AppAlert.showError(context, message);
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        await _controller.start();
        setState(() {
          _isHandlingDetection = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _LunchScannerViewport(
                        controller: _controller,
                        isScannerActive: !_isHandlingDetection,
                        onDetect: _handleDetect,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: _LunchScanResultCard(
                        response: _lastResponse,
                        errorMessage: _lastError,
                        isScanning: !_isHandlingDetection,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _LunchScannerViewport(
                      controller: _controller,
                      isScannerActive: !_isHandlingDetection,
                      onDetect: _handleDetect,
                    ),
                    const SizedBox(height: 12),
                    _LunchScanResultCard(
                      response: _lastResponse,
                      errorMessage: _lastError,
                      isScanning: !_isHandlingDetection,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class LunchesAdminScreen extends StatefulWidget {
  const LunchesAdminScreen({super.key});

  @override
  State<LunchesAdminScreen> createState() => _LunchesAdminScreenState();
}

class _LunchesAdminScreenState extends State<LunchesAdminScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  LunchRecordStatus? _selectedStatus;
  List<LunchRecord> _records = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await dependencies.lunchesApiService.fetchLunches(
        date: _selectedDate,
        query: _searchController.text,
        status: _selectedStatus,
      );

      if (mounted) {
        setState(() {
          _records = records;
        });
      }
    } on BackendApiException catch (error) {
      if (mounted) {
        setState(() {
          _records = const [];
          _errorMessage = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _records = const [];
          _errorMessage = 'No fue posible cargar los almuerzos.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final openCount = _records.where((record) => record.isOpen).length;
    final closedCount = _records.length - openCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Almuerzos',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      _PickerButton(
                        icon: Icons.calendar_month_rounded,
                        label: _formatDate(_selectedDate),
                        onTap: _pickDate,
                      ),
                      _StatusFilter(
                        value: _selectedStatus,
                        onChanged: (value) {
                          setState(() {
                            _selectedStatus = value;
                          });
                          _load();
                        },
                      ),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Actualizar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      labelText: 'Buscar',
                      hintText: 'Nombre, CI, item, cargo u oficina',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        onPressed: _load,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        tooltip: 'Buscar',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SummaryChip(
                        label: 'Registros',
                        value: '${_records.length}',
                      ),
                      _SummaryChip(label: 'En almuerzo', value: '$openCount'),
                      _SummaryChip(label: 'Retornados', value: '$closedCount'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _errorMessage != null
                  ? Text(_errorMessage!)
                  : _records.isEmpty
                  ? const Text('No hay registros de almuerzo para esta fecha.')
                  : _LunchRecordsTable(records: _records),
            ),
          ),
        ],
      ),
    );
  }
}

class _LunchScannerViewport extends StatelessWidget {
  const _LunchScannerViewport({
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
                        errorBuilder: (context, error) =>
                            _ScannerErrorState(error: error),
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
                      child: _ScannerBadge(
                        text: isScannerActive
                            ? 'Camara frontal'
                            : 'Registrando',
                      ),
                    ),
                    const Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _ScannerHelp(),
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

class _LunchScanResultCard extends StatelessWidget {
  const _LunchScanResultCard({
    required this.response,
    required this.errorMessage,
    required this.isScanning,
  });

  final LunchScanResponse? response;
  final String? errorMessage;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final record = response?.record;
    final color = response?.action == LunchScanAction.returnToWork
        ? Colors.green.shade700
        : AppPalette.orange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registro de almuerzo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (errorMessage != null)
              _ResultBanner(
                icon: Icons.error_outline_rounded,
                color: Colors.red.shade700,
                text: errorMessage!,
              )
            else if (record != null) ...[
              _ResultBanner(
                icon: response!.action == LunchScanAction.returnToWork
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                color: color,
                text: response!.message,
              ),
              const SizedBox(height: 14),
              _ResultRow(label: 'Funcionario', value: record.employeeFullName),
              _ResultRow(label: 'CI', value: record.employeeCi),
              _ResultRow(label: 'Oficina', value: record.employeeOffice),
              _ResultRow(label: 'Salida', value: record.departureTime),
              _ResultRow(
                label: 'Retorno',
                value: record.returnTime.isEmpty
                    ? 'Pendiente'
                    : record.returnTime,
              ),
            ] else
              _ResultBanner(
                icon: Icons.qr_code_scanner_rounded,
                color: AppPalette.night,
                text: isScanning
                    ? 'Esperando QR de credencial.'
                    : 'Procesando lectura.',
              ),
          ],
        ),
      ),
    );
  }
}

class _LunchRecordsTable extends StatelessWidget {
  const _LunchRecordsTable({required this.records});

  final List<LunchRecord> records;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Funcionario')),
          DataColumn(label: Text('Salida')),
          DataColumn(label: Text('Llegada')),
        ],
        rows: [
          for (final record in records)
            DataRow(
              onSelectChanged: (_) => _showLunchRecordDetails(context, record),
              cells: [
                DataCell(Text(record.employeeFullName)),
                DataCell(Text(record.departureTime)),
                DataCell(
                  Text(record.returnTime.isEmpty ? '-' : record.returnTime),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

void _showLunchRecordDetails(BuildContext context, LunchRecord record) {
  showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(record.employeeFullName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ResultRow(label: 'CI', value: record.employeeCi),
              _ResultRow(label: 'Item', value: record.employeeItemNumber),
              _ResultRow(label: 'Cargo', value: record.employeeJobTitle),
              _ResultRow(label: 'Oficina', value: record.employeeOffice),
              _ResultRow(label: 'Salida', value: record.departureTime),
              _ResultRow(
                label: 'Llegada',
                value: record.returnTime.isEmpty
                    ? 'Pendiente'
                    : record.returnTime,
              ),
              _ResultRow(label: 'Estado', value: record.status.label),
              _ResultRow(
                label: 'Punto salida',
                value: record.departureScannerName,
              ),
              _ResultRow(
                label: 'Punto llegada',
                value: record.returnScannerName.isEmpty
                    ? '-'
                    : record.returnScannerName,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.value, required this.onChanged});

  final LunchRecordStatus? value;
  final ValueChanged<LunchRecordStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<LunchRecordStatus?>(
      value: value,
      hint: const Text('Todos'),
      items: const [
        DropdownMenuItem<LunchRecordStatus?>(value: null, child: Text('Todos')),
        DropdownMenuItem<LunchRecordStatus?>(
          value: LunchRecordStatus.open,
          child: Text('En almuerzo'),
        ),
        DropdownMenuItem<LunchRecordStatus?>(
          value: LunchRecordStatus.closed,
          child: Text('Retornados'),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      avatar: const Icon(Icons.restaurant_menu_rounded, size: 18),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(color: AppPalette.muted)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerBadge extends StatelessWidget {
  const _ScannerBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xA154407E),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ScannerHelp extends StatelessWidget {
  const _ScannerHelp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xA154407E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Alinea el QR de la credencial dentro del marco.',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ScannerErrorState extends StatelessWidget {
  const _ScannerErrorState({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Permite el acceso a la camara en el navegador y vuelve a cargar.',
      MobileScannerErrorCode.unsupported =>
        'Este navegador o dispositivo no permite el lector QR.',
      _ => 'No fue posible iniciar la camara.',
    };

    return Container(
      color: AppPalette.nightDeep,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}
