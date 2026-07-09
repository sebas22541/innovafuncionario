import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/file_downloader.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../auth/domain/entities/cargo_option.dart';
import '../../../auth/domain/entities/office_option.dart';
import '../../infrastructure/services/ratings_api_service.dart';

enum _RatingsReportFilter { dateRange, cargo, office, search }

class RatingsScreen extends StatefulWidget {
  const RatingsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _reportSearchController = TextEditingController();
  final TextEditingController _officeSearchController = TextEditingController();
  List<AppUser> _users = const [];
  List<CargoOption> _cargos = const [];
  List<OfficeOption> _offices = const [];
  List<ActiveRatingQr> _activeQrs = const [];
  List<RatingSummary> _report = const [];
  RatingQr? _ratingQr;
  bool _isLoadingUsers = true;
  bool _isLoadingCargos = true;
  bool _isLoadingOffices = true;
  bool _isLoadingActiveQrs = true;
  bool _isGenerating = false;
  bool _isLoadingReport = false;
  bool _hasLoadedReport = false;
  bool _isExportingPdf = false;
  bool _isDownloadingQr = false;
  String _query = '';
  String _reportQuery = '';
  String _startDate = _todayText();
  String _endDate = _todayText();
  CargoOption? _selectedCargo;
  OfficeOption? _selectedOffice;
  String _officeQuery = '';
  _RatingsReportFilter? _activeReportFilter;
  Timer? _searchDebounce;
  Timer? _reportSearchDebounce;
  Timer? _officeSearchDebounce;

  List<AppUser> get _filteredUsers {
    final query = _normalize(_query);

    if (query.length < 2) {
      return const [];
    }

    final users = _users.where((user) => user.activo).toList(growable: false);

    return users
        .where(
          (user) => _normalize(
            '${user.fullName} ${user.ci} ${user.cargoEfectivo} ${user.officeName} ${user.unidad}',
          ).contains(query),
        )
        .take(30)
        .toList(growable: false);
  }

  List<RatingSummary> get _filteredReport => _report;

  List<OfficeOption> get _filteredOffices {
    final query = _normalize(_officeQuery);

    if (query.length < 2) {
      return const [];
    }

    return _offices
        .where(
          (office) => _normalize(
            '${office.name} ${office.code} ${office.level}',
          ).contains(query),
        )
        .take(20)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _startDateController.text = _startDate;
    _endDateController.text = _endDate;
    _loadUsers();
    _loadCargos();
    _loadOffices();
    _loadActiveQrs();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reportSearchDebounce?.cancel();
    _searchController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _reportSearchController.dispose();
    _officeSearchController.dispose();
    _officeSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);

    try {
      final users = await dependencies.authApiService.fetchUsers(
        requesterEmail: widget.currentUser.email,
      );
      if (!mounted) {
        return;
      }
      setState(() => _users = users);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar funcionarios.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  Future<void> _loadCargos() async {
    setState(() => _isLoadingCargos = true);

    try {
      final cargos = await dependencies.authApiService.fetchCargos();
      if (!mounted) {
        return;
      }
      setState(() => _cargos = cargos);
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar cargos.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingCargos = false);
      }
    }
  }

  Future<void> _loadOffices() async {
    setState(() => _isLoadingOffices = true);

    try {
      final offices = await dependencies.authApiService.fetchOffices();
      if (!mounted) {
        return;
      }
      setState(() => _offices = offices);
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar oficinas.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingOffices = false);
      }
    }
  }

  Future<void> _loadActiveQrs() async {
    setState(() => _isLoadingActiveQrs = true);

    try {
      final qrs = await dependencies.ratingsApiService.fetchActiveQrs();
      if (!mounted) {
        return;
      }
      setState(() => _activeQrs = qrs);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar QR activos.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingActiveQrs = false);
      }
    }
  }

  Future<void> _loadReport({
    _RatingsReportFilter filter = _RatingsReportFilter.dateRange,
  }) async {
    setState(() {
      _isLoadingReport = true;
      _hasLoadedReport = true;
      _activeReportFilter = filter;
    });

    try {
      final report = await dependencies.ratingsApiService.fetchReport(
        fechaInicio: filter == _RatingsReportFilter.dateRange
            ? _startDate
            : null,
        fechaFin: filter == _RatingsReportFilter.dateRange ? _endDate : null,
        cargoCodigo: filter == _RatingsReportFilter.cargo
            ? _selectedCargo?.code
            : null,
        oficinaId: filter == _RatingsReportFilter.office
            ? _selectedOffice?.id
            : null,
        query: filter == _RatingsReportFilter.search ? _reportQuery : null,
      );
      if (!mounted) {
        return;
      }
      setState(() => _report = report.funcionarios);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar el reporte.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingReport = false);
      }
    }
  }

  Future<void> _generateQr(AppUser user) async {
    final userId = user.id;

    if (userId == null || _isGenerating) {
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final qr = await dependencies.ratingsApiService.generateQr(
        funcionarioId: userId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _ratingQr = qr);
      await _loadActiveQrs();
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible generar el QR.');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _showActiveQr(ActiveRatingQr qr) {
    setState(() {
      _ratingQr = RatingQr(
        funcionario: RatingFuncionario(
          id: qr.funcionarioId,
          nombreCompleto: qr.nombreCompleto,
          ci: qr.ci,
          cargo: qr.cargo,
          oficina: qr.oficina,
        ),
        token: qr.token,
        url: qr.url,
      );
    });
  }

  Future<void> _copyQrUrl() async {
    final url = _ratingQr?.url;

    if (url == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));

    if (mounted) {
      AppAlert.showSuccess(context, 'Enlace copiado.');
    }
  }

  Future<void> _downloadQrImage() async {
    final qr = _ratingQr;

    if (qr == null || _isDownloadingQr) {
      return;
    }

    setState(() => _isDownloadingQr = true);

    try {
      final painter = QrPainter(
        data: qr.url,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      );
      const imageSize = 900.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, imageSize, imageSize),
          Paint()..color = Colors.white,
        );
      painter.paint(canvas, const Size(imageSize, imageSize));
      final image = await recorder.endRecording().toImage(
        imageSize.toInt(),
        imageSize.toInt(),
      );
      final imageData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (imageData == null) {
        throw StateError('No fue posible crear la imagen QR.');
      }

      await downloadFile(
        fileName:
            'qr-calificacion-${_safeFileName(qr.funcionario.nombreCompleto)}.png',
        bytes: imageData.buffer.asUint8List(),
        mimeType: 'image/png',
      );

      if (mounted) {
        AppAlert.showSuccess(context, 'QR descargado.');
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible descargar el QR.');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingQr = false);
      }
    }
  }

  Future<void> _exportReportPdf() async {
    final rows = _filteredReport;

    if (rows.isEmpty || _isExportingPdf) {
      AppAlert.showWarning(context, 'No hay datos para exportar.');
      return;
    }

    setState(() => _isExportingPdf = true);

    try {
      final document = pw.Document();

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => [
            pw.Text(
              'Reporte de calificaciones',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            if (_activeReportFilter == _RatingsReportFilter.dateRange)
              pw.Text('Rango: $_startDate a $_endDate'),
            if (_activeReportFilter == _RatingsReportFilter.cargo &&
                _selectedCargo != null)
              pw.Text('Cargo: ${_selectedCargo!.name}'),
            if (_activeReportFilter == _RatingsReportFilter.office &&
                _selectedOffice != null)
              pw.Text('Oficina: ${_selectedOffice!.name}'),
            if (_activeReportFilter == _RatingsReportFilter.search &&
                _reportQuery.trim().isNotEmpty)
              pw.Text('Filtro: ${_reportQuery.trim()}'),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: const {
                0: pw.FixedColumnWidth(54),
                1: pw.FixedColumnWidth(130),
                2: pw.FixedColumnWidth(120),
                3: pw.FixedColumnWidth(140),
                4: pw.FixedColumnWidth(45),
                5: pw.FixedColumnWidth(45),
                6: pw.FixedColumnWidth(45),
              },
              headers: const [
                'CI',
                'Nombre',
                'Cargo',
                'Oficina',
                'Feliz',
                'Neutral',
                'Enojada',
              ],
              data: rows
                  .map(
                    (row) => [
                      row.ci,
                      row.nombreCompleto,
                      row.cargo,
                      row.oficina,
                      '${row.feliz}',
                      '${row.neutral}',
                      '${row.enojada}',
                    ],
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) => document.save(),
        name: 'reporte-calificaciones-$_startDate-$_endDate.pdf',
      );
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible generar el PDF.');
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Future<void> _pickStartDate() async {
    final initialDate = DateTime.tryParse(_startDate) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('es', 'BO'),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _startDate = _formatDate(selected);
      _startDateController.text = _startDate;
      if (DateTime.parse(_endDate).isBefore(DateTime.parse(_startDate))) {
        _endDate = _startDate;
        _endDateController.text = _endDate;
      }
    });
    _loadReport();
  }

  Future<void> _pickEndDate() async {
    final initialDate = DateTime.tryParse(_endDate) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('es', 'BO'),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _endDate = _formatDate(selected);
      _endDateController.text = _endDate;
      if (DateTime.parse(_endDate).isBefore(DateTime.parse(_startDate))) {
        _startDate = _endDate;
        _startDateController.text = _startDate;
      }
    });
    _loadReport();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() => _query = value);
      }
    });
  }

  void _onReportSearchChanged(String value) {
    _reportSearchDebounce?.cancel();
    _reportSearchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() => _reportQuery = value);
        final query = value.trim();

        if (query.length >= 2) {
          _loadReport(filter: _RatingsReportFilter.search);
        } else if (query.isEmpty) {
          setState(() {
            _report = const [];
            _hasLoadedReport = false;
            _activeReportFilter = null;
          });
        }
      }
    });
  }

  void _onOfficeSearchChanged(String value) {
    _officeSearchDebounce?.cancel();
    _officeSearchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _officeQuery = value;
        _selectedOffice = null;
      });

      if (value.trim().isEmpty &&
          _activeReportFilter == _RatingsReportFilter.office) {
        setState(() {
          _report = const [];
          _hasLoadedReport = false;
          _activeReportFilter = null;
        });
      }
    });
  }

  void _selectReportOffice(OfficeOption office) {
    setState(() {
      _selectedOffice = office;
      _officeQuery = office.name;
      _officeSearchController.text = office.name;
    });
    _loadReport(filter: _RatingsReportFilter.office);
  }

  void _refreshActiveReport() {
    _loadReport(filter: _activeReportFilter ?? _RatingsReportFilter.dateRange);
  }

  @override
  Widget build(BuildContext context) {
    final qr = _ratingQr;
    final filteredReport = _filteredReport;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generar QR de calificacion',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      labelText: 'Buscar funcionario',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_isLoadingUsers && _query.trim().length >= 2)
                    const Center(child: CircularProgressIndicator())
                  else if (_query.trim().length >= 2 &&
                      _filteredUsers.isNotEmpty)
                    _FuncionarioSelectList(
                      users: _filteredUsers,
                      isGenerating: _isGenerating,
                      onSelected: _generateQr,
                    )
                  else if (_query.trim().length >= 2)
                    const _SearchHint(
                      icon: Icons.search_off_rounded,
                      text: 'No se encontraron funcionarios.',
                    )
                  else
                    const _SearchHint(
                      icon: Icons.manage_search_rounded,
                      text: 'Escribe al menos 2 letras para buscar.',
                    ),
                  if (qr != null) ...[
                    const SizedBox(height: 22),
                    Center(
                      child: Column(
                        children: [
                          QrImageView(
                            data: qr.url,
                            version: QrVersions.auto,
                            size: 260,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            qr.funcionario.nombreCompleto,
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          SelectableText(qr.url, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _copyQrUrl,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copiar enlace'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _isDownloadingQr
                                ? null
                                : _downloadQrImage,
                            icon: _isDownloadingQr
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded),
                            label: const Text('Descargar imagen QR'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'QR activos para calificacion',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: _loadActiveQrs,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingActiveQrs)
                    const Center(child: CircularProgressIndicator())
                  else if (_activeQrs.isEmpty)
                    const _SearchHint(
                      icon: Icons.qr_code_2_rounded,
                      text: 'Todavia no hay QR activos de calificacion.',
                    )
                  else
                    Column(
                      children: _activeQrs
                          .map(
                            (qr) => _ActiveQrTile(
                              qr: qr,
                              onTap: () => _showActiveQr(qr),
                            ),
                          )
                          .toList(growable: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reporte por rango',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 760;
                      final controls = [
                        Expanded(
                          child: TextField(
                            controller: _startDateController,
                            readOnly: true,
                            onTap: _pickStartDate,
                            decoration: const InputDecoration(
                              labelText: 'Fecha inicio',
                              prefixIcon: Icon(Icons.today_rounded),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _endDateController,
                            readOnly: true,
                            onTap: _pickEndDate,
                            decoration: const InputDecoration(
                              labelText: 'Fecha fin',
                              prefixIcon: Icon(Icons.event_rounded),
                            ),
                          ),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCargo?.code,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cargo',
                              prefixIcon: Icon(Icons.work_outline_rounded),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Todos'),
                              ),
                              ..._cargos.map(
                                (cargo) => DropdownMenuItem<String>(
                                  value: cargo.code,
                                  child: Text(
                                    cargo.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: _isLoadingCargos
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedCargo =
                                          value == null || value.isEmpty
                                          ? null
                                          : _cargos.firstWhere(
                                              (cargo) => cargo.code == value,
                                            );
                                    });
                                    _loadReport(
                                      filter: _RatingsReportFilter.cargo,
                                    );
                                  },
                          ),
                        ),
                      ];

                      if (isWide) {
                        return Row(
                          children: [
                            controls[0],
                            const SizedBox(width: 10),
                            controls[1],
                            const SizedBox(width: 10),
                            controls[2],
                          ],
                        );
                      }

                      return Column(
                        children: [
                          controls[0],
                          const SizedBox(height: 10),
                          controls[1],
                          const SizedBox(height: 10),
                          controls[2],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _officeSearchController,
                    onChanged: _onOfficeSearchChanged,
                    decoration: InputDecoration(
                      labelText: 'Buscar oficina',
                      prefixIcon: const Icon(Icons.apartment_rounded),
                      suffixIcon: _officeSearchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar oficina',
                              onPressed: () {
                                _officeSearchDebounce?.cancel();
                                setState(() {
                                  _officeSearchController.clear();
                                  _officeQuery = '';
                                  _selectedOffice = null;
                                  if (_activeReportFilter ==
                                      _RatingsReportFilter.office) {
                                    _report = const [];
                                    _hasLoadedReport = false;
                                    _activeReportFilter = null;
                                  }
                                });
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  if (_isLoadingOffices && _officeQuery.trim().length >= 2) ...[
                    const SizedBox(height: 10),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (_officeQuery.trim().length >= 2 &&
                      _selectedOffice == null) ...[
                    const SizedBox(height: 10),
                    if (_filteredOffices.isEmpty)
                      const _SearchHint(
                        icon: Icons.search_off_rounded,
                        text: 'No se encontraron oficinas.',
                      )
                    else
                      _OfficeSelectList(
                        offices: _filteredOffices,
                        onSelected: _selectReportOffice,
                      ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _reportSearchController,
                          onChanged: _onReportSearchChanged,
                          decoration: const InputDecoration(
                            labelText: 'Buscar por CI o nombre',
                            prefixIcon: Icon(Icons.person_search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        onPressed: _refreshActiveReport,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _isExportingPdf ? null : _exportReportPdf,
                        icon: _isExportingPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('PDF'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingReport)
                    const Center(child: CircularProgressIndicator())
                  else if (!_hasLoadedReport)
                    const _SearchHint(
                      icon: Icons.manage_search_rounded,
                      text:
                          'Selecciona un rango, cargo si corresponde, y presiona actualizar para ver el reporte.',
                    )
                  else if (_report.isEmpty)
                    const _EmptyReport()
                  else if (filteredReport.isEmpty)
                    const _SearchHint(
                      icon: Icons.search_off_rounded,
                      text: 'No hay resultados para ese CI o nombre.',
                    )
                  else
                    _RatingSummaryGrid(rows: filteredReport),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingSummaryTile extends StatelessWidget {
  const _RatingSummaryTile({required this.summary});

  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final comments = summary.comentarios
        .where((comment) => comment.comentario.trim().isNotEmpty)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.nombreCompleto,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('CI ${summary.ci}'),
          const SizedBox(height: 4),
          Text(
            [
              summary.cargo,
              summary.oficina,
            ].where((value) => value.trim().isNotEmpty).join(' | '),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountPill(
                icon: Icons.sentiment_satisfied_alt_rounded,
                value: summary.feliz,
              ),
              _CountPill(
                icon: Icons.sentiment_neutral_rounded,
                value: summary.neutral,
              ),
              _CountPill(
                icon: Icons.sentiment_very_dissatisfied_rounded,
                value: summary.enojada,
              ),
            ],
          ),
          if (comments.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final comment in comments.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('- ${comment.comentario}'),
              ),
          ],
        ],
      ),
    );
  }
}

class _RatingSummaryGrid extends StatelessWidget {
  const _RatingSummaryGrid({required this.rows});

  final List<RatingSummary> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        const spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.start,
          children: rows
              .map(
                (row) => SizedBox(
                  width: itemWidth,
                  child: _RatingSummaryTile(summary: row),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _FuncionarioSelectList extends StatelessWidget {
  const _FuncionarioSelectList({
    required this.users,
    required this.isGenerating,
    required this.onSelected,
  });

  final List<AppUser> users;
  final bool isGenerating;
  final ValueChanged<AppUser> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: users.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final user = users[index];

          return ListTile(
            enabled: !isGenerating,
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(user.fullName),
            subtitle: Text(
              [
                if (user.ci.trim().isNotEmpty) 'CI ${user.ci}',
                user.cargoEfectivo,
                user.officeName ?? user.unidad,
              ].where((value) => value.trim().isNotEmpty).join(' | '),
            ),
            trailing: const Icon(Icons.qr_code_2_rounded),
            onTap: isGenerating ? null : () => onSelected(user),
          );
        },
      ),
    );
  }
}

class _OfficeSelectList extends StatelessWidget {
  const _OfficeSelectList({required this.offices, required this.onSelected});

  final List<OfficeOption> offices;
  final ValueChanged<OfficeOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: offices.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final office = offices[index];

          return ListTile(
            leading: const Icon(Icons.apartment_rounded),
            title: Text(office.name),
            subtitle: Text('Codigo ${office.code} | Nivel ${office.level}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onSelected(office),
          );
        },
      ),
    );
  }
}

class _ActiveQrTile extends StatelessWidget {
  const _ActiveQrTile({required this.qr, required this.onTap});

  final ActiveRatingQr qr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.qr_code_2_rounded),
        title: Text(
          qr.nombreCompleto,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            qr.cargo,
            qr.oficina,
          ].where((value) => value.trim().isNotEmpty).join(' | '),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppPalette.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 4),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text('No hay calificaciones registradas en la fecha.'),
      ),
    );
  }
}

String _normalize(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _todayText() => _formatDate(DateTime.now());

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _safeFileName(String value) {
  final safe = _normalize(
    value,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  return safe.isEmpty ? 'funcionario' : safe;
}
