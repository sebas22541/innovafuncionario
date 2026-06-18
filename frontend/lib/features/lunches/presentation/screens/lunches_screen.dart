import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/excel_exporter.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../qr_scanner/infrastructure/models/qr_scan_result_model.dart';
import '../../../qr_scanner/presentation/widgets/qr_scanner_overlay.dart';
import '../../../permissions/infrastructure/services/exit_permits_api_service.dart';
import '../../infrastructure/services/lunches_api_service.dart';

class LunchScannerScreen extends StatefulWidget {
  const LunchScannerScreen({
    super.key,
    required this.currentUser,
    this.backToModeSelectionToken = 0,
    this.onModeActiveChanged,
  });

  final AppUser currentUser;
  final int backToModeSelectionToken;
  final ValueChanged<bool>? onModeActiveChanged;

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

  _ScannerMode? _selectedMode;
  LunchScanResponse? _lastLunchResponse;
  ExitPermitScanResponse? _lastExitPermitResponse;
  String? _lastError;
  bool _isHandlingDetection = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LunchScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.backToModeSelectionToken != oldWidget.backToModeSelectionToken &&
        _selectedMode != null) {
      _returnToModeSelection();
    }
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
      final selectedMode = _selectedMode;

      if (selectedMode == null) {
        return;
      }

      final response = selectedMode == _ScannerMode.lunch
          ? await dependencies.lunchesApiService.registerScan(
              qrValue: scan.value,
            )
          : await dependencies.exitPermitsApiService.registerQrScan(
              qrValue: scan.value,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        if (selectedMode == _ScannerMode.lunch) {
          _lastLunchResponse = response as LunchScanResponse;
          _lastExitPermitResponse = null;
        } else {
          _lastExitPermitResponse = response as ExitPermitScanResponse;
          _lastLunchResponse = null;
        }
      });
      AppAlert.showSuccess(
        context,
        selectedMode == _ScannerMode.lunch
            ? (response as LunchScanResponse).message
            : (response as ExitPermitScanResponse).message,
      );
    } on BackendApiException catch (error) {
      if (mounted) {
        setState(() {
          _lastError = error.message;
        });
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        final message = _selectedMode == _ScannerMode.exitPermit
            ? 'No fue posible registrar el permiso de salida.'
            : 'No fue posible registrar el almuerzo.';
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
    if (_selectedMode == null) {
      return _ScannerModeSelection(
        onSelected: (mode) {
          setState(() {
            _selectedMode = mode;
            _lastError = null;
            _lastLunchResponse = null;
            _lastExitPermitResponse = null;
          });
          widget.onModeActiveChanged?.call(true);
          _controller.start();
        },
      );
    }

    final selectedMode = _selectedMode!;

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
                        mode: selectedMode,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: _LunchScanResultCard(
                        mode: selectedMode,
                        lunchResponse: _lastLunchResponse,
                        exitPermitResponse: _lastExitPermitResponse,
                        errorMessage: _lastError,
                        isScanning: !_isHandlingDetection,
                        onChangeMode: _changeMode,
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
                      mode: selectedMode,
                    ),
                    const SizedBox(height: 12),
                    _LunchScanResultCard(
                      mode: selectedMode,
                      lunchResponse: _lastLunchResponse,
                      exitPermitResponse: _lastExitPermitResponse,
                      errorMessage: _lastError,
                      isScanning: !_isHandlingDetection,
                      onChangeMode: _changeMode,
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _changeMode() async {
    await _controller.stop();
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedMode = null;
      _lastError = null;
      _lastLunchResponse = null;
      _lastExitPermitResponse = null;
      _isHandlingDetection = false;
    });
    widget.onModeActiveChanged?.call(false);
  }

  void _returnToModeSelection() {
    _controller.stop();

    setState(() {
      _selectedMode = null;
      _lastError = null;
      _lastLunchResponse = null;
      _lastExitPermitResponse = null;
      _isHandlingDetection = false;
    });
    widget.onModeActiveChanged?.call(false);
  }
}

enum _ScannerMode {
  lunch('Almuerzo', Icons.restaurant_menu_rounded),
  exitPermit('Permiso de salida', Icons.assignment_turned_in_rounded);

  const _ScannerMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

class LunchesAdminScreen extends StatefulWidget {
  const LunchesAdminScreen({super.key});

  @override
  State<LunchesAdminScreen> createState() => _LunchesAdminScreenState();
}

class _ScannerModeSelection extends StatelessWidget {
  const _ScannerModeSelection({required this.onSelected});

  final ValueChanged<_ScannerMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Selecciona el tipo de registro',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final buttons = [
                _ScannerModeButton(
                  mode: _ScannerMode.lunch,
                  onTap: () => onSelected(_ScannerMode.lunch),
                ),
                _ScannerModeButton(
                  mode: _ScannerMode.exitPermit,
                  onTap: () => onSelected(_ScannerMode.exitPermit),
                ),
              ];

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: buttons.first),
                    const SizedBox(width: 14),
                    Expanded(child: buttons.last),
                  ],
                );
              }

              return Column(
                children: [
                  buttons.first,
                  const SizedBox(height: 12),
                  buttons.last,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ScannerModeButton extends StatelessWidget {
  const _ScannerModeButton({required this.mode, required this.onTap});

  final _ScannerMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 136,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(mode.icon, size: 30),
        label: Text(
          mode.label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LunchesAdminScreenState extends State<LunchesAdminScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  LunchRecordStatus? _selectedStatus;
  List<LunchRecord> _records = const [];
  bool _isLoading = true;
  bool _isExporting = false;
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

  Future<void> _exportExcel() async {
    if (_isExporting) {
      return;
    }

    final range = await _pickExportRange(context, _selectedDate);

    if (range == null) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final records = <LunchRecord>[];

      for (final date in _datesInRange(range)) {
        records.addAll(
          await dependencies.lunchesApiService.fetchLunches(
            date: date,
            query: _searchController.text,
            status: _selectedStatus,
          ),
        );
      }

      await exportExcelWorkbook(
        fileName:
            'almuerzos_${_fileDate(range.start)}_${_fileDate(range.end)}.xlsx',
        sheetName: 'Almuerzos',
        headers: const [
          'Fecha',
          'Funcionario',
          'CI',
          'Item',
          'Cargo',
          'Oficina',
          'Estado',
          'Hora salida',
          'Hora retorno',
          'Registrado salida por',
          'Registrado retorno por',
          'Salida registrada en',
          'Retorno registrado en',
        ],
        rows: [
          for (final record in records)
            [
              _formatDate(record.date),
              record.employeeFullName,
              record.employeeCi,
              record.employeeItemNumber,
              record.employeeJobTitle,
              record.employeeOffice,
              record.status.label,
              record.departureTime,
              record.returnTime.isEmpty ? 'Pendiente' : record.returnTime,
              record.departureScannerName,
              record.returnScannerName,
              _formatDateTime(record.departureAt),
              record.returnAt == null ? '' : _formatDateTime(record.returnAt!),
            ],
        ],
      );

      if (mounted) {
        AppAlert.showSuccess(context, 'Excel de almuerzos generado.');
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible exportar almuerzos.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
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
                      OutlinedButton.icon(
                        onPressed: _isLoading || _isExporting
                            ? null
                            : _exportExcel,
                        icon: _isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.table_view_rounded),
                        label: Text(
                          _isExporting ? 'Exportando...' : 'Exportar Excel',
                        ),
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
    required this.mode,
  });

  final MobileScannerController controller;
  final bool isScannerActive;
  final void Function(BarcodeCapture capture) onDetect;
  final _ScannerMode mode;

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
                            ? mode.label
                            : 'Registrando',
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _ScannerHelp(mode: mode),
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
    required this.mode,
    required this.lunchResponse,
    required this.exitPermitResponse,
    required this.errorMessage,
    required this.isScanning,
    required this.onChangeMode,
  });

  final _ScannerMode mode;
  final LunchScanResponse? lunchResponse;
  final ExitPermitScanResponse? exitPermitResponse;
  final String? errorMessage;
  final bool isScanning;
  final VoidCallback onChangeMode;

  @override
  Widget build(BuildContext context) {
    final lunchRecord = lunchResponse?.record;
    final exitPermitRecord = exitPermitResponse?.record;
    final color = mode == _ScannerMode.lunch
        ? lunchResponse?.action == LunchScanAction.returnToWork
              ? Colors.green.shade700
              : AppPalette.orange
        : exitPermitResponse?.action == ExitPermitScanAction.arrival
        ? Colors.green.shade700
        : AppPalette.orange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mode == _ScannerMode.lunch
                        ? 'Registro de almuerzo'
                        : 'Registro de permiso de salida',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: onChangeMode,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  tooltip: 'Cambiar registro',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (mode == _ScannerMode.lunch) ...[
              _ResultBanner(
                icon: Icons.schedule_rounded,
                color: AppPalette.orange,
                text: 'Horario permitido para almuerzo: 12:00 a 15:00.',
              ),
              const SizedBox(height: 12),
            ],
            if (errorMessage != null)
              _ResultBanner(
                icon: Icons.error_outline_rounded,
                color: Colors.red.shade700,
                text: errorMessage!,
              )
            else if (lunchRecord != null) ...[
              _ResultBanner(
                icon: lunchResponse!.action == LunchScanAction.returnToWork
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                color: color,
                text: lunchResponse!.message,
              ),
              const SizedBox(height: 14),
              _ResultRow(
                label: 'Funcionario',
                value: lunchRecord.employeeFullName,
              ),
              _ResultRow(label: 'CI', value: lunchRecord.employeeCi),
              _ResultRow(label: 'Oficina', value: lunchRecord.employeeOffice),
              _ResultRow(label: 'Salida', value: lunchRecord.departureTime),
              _ResultRow(
                label: 'Retorno',
                value: lunchRecord.returnTime.isEmpty
                    ? 'Pendiente'
                    : lunchRecord.returnTime,
              ),
            ] else if (exitPermitRecord != null) ...[
              _ResultBanner(
                icon: exitPermitResponse!.action == ExitPermitScanAction.arrival
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                color: color,
                text: exitPermitResponse!.message,
              ),
              const SizedBox(height: 14),
              _ResultRow(
                label: 'Funcionario',
                value: exitPermitRecord.applicantFullName,
              ),
              _ResultRow(label: 'CI', value: exitPermitRecord.applicantCi),
              _ResultRow(
                label: 'Destino',
                value: exitPermitRecord.destination,
              ),
              _ResultRow(label: 'Salida', value: exitPermitRecord.startTime),
              _ResultRow(
                label: 'Llegada',
                value: exitPermitRecord.arrivalTime.isEmpty
                    ? 'Pendiente'
                    : exitPermitRecord.arrivalTime,
              ),
            ] else
              _ResultBanner(
                icon: Icons.qr_code_scanner_rounded,
                color: AppPalette.night,
                text: isScanning
                    ? 'Esperando QR de credencial para ${mode.label.toLowerCase()}.'
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
  const _ScannerHelp({required this.mode});

  final _ScannerMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xA154407E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        mode == _ScannerMode.lunch
            ? 'Alinea el QR de la credencial para registrar almuerzo.'
            : 'Alinea el QR de la credencial para registrar salida o llegada.',
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

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  return '${_formatDate(local)} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _fileDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}'
      '${local.month.toString().padLeft(2, '0')}'
      '${local.day.toString().padLeft(2, '0')}';
}

List<DateTime> _datesInRange(DateTimeRange range) {
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  final dates = <DateTime>[];

  for (
    var date = start;
    !date.isAfter(end);
    date = date.add(const Duration(days: 1))
  ) {
    dates.add(date);
  }

  return dates;
}

Future<DateTimeRange?> _pickExportRange(
  BuildContext context,
  DateTime selectedDate,
) {
  final now = DateTime.now();
  final initialDate = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );

  return showDateRangePicker(
    context: context,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 1),
    initialDateRange: DateTimeRange(start: initialDate, end: initialDate),
  );
}
