import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/widgets/base64_avatar.dart';
import '../../../events/domain/entities/event_record.dart';
import '../../domain/entities/attendance_report.dart';

const double _reportPdfFontSize = 8;
const Map<int, pw.TableColumnWidth> _eventReportPdfColumnWidths = {
  0: pw.FixedColumnWidth(20),
  1: pw.FixedColumnWidth(62),
  2: pw.FixedColumnWidth(92),
  3: pw.FixedColumnWidth(132),
  4: pw.FixedColumnWidth(76),
  5: pw.FixedColumnWidth(60),
};

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final TextEditingController _ciController = TextEditingController();
  final ScrollController _pageScrollController = ScrollController();
  List<EventRecord> _events = const [];
  AttendanceReport? _report;
  EventRecord? _eventReport;
  int? _selectedEventId;
  bool _isLoading = false;
  bool _isLoadingEvents = false;
  bool _isLoadingEventReport = false;
  bool _isExporting = false;
  bool _isExportingEventPdf = false;
  String? _errorMessage;
  String? _eventErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadEventOptions();
  }

  @override
  void dispose() {
    _ciController.dispose();
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEventOptions() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingEvents = true;
      _eventErrorMessage = null;
    });

    try {
      final events = await dependencies.eventsApiService.fetchEvents();

      if (!mounted) {
        return;
      }

      EventRecord? selectedEvent;

      if (_selectedEventId != null) {
        for (final event in events) {
          if (event.id == _selectedEventId) {
            selectedEvent = event;
            break;
          }
        }
      }

      setState(() {
        _events = events;
        _eventReport = selectedEvent;

        if (_selectedEventId != null && selectedEvent == null) {
          _selectedEventId = null;
        }
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _eventErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _eventErrorMessage = 'No fue posible cargar los eventos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  Future<void> _search() async {
    final ci = _ciController.text.trim();

    if (ci.length < 3) {
      setState(() {
        _errorMessage = 'Ingresa un CI valido para buscar.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final report = await dependencies.reportsApiService.fetchByCi(
        ci: ci,
        filter: AttendanceReportFilter.all,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _report = report;
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _report = null;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _report = null;
        _errorMessage = 'No fue posible generar el reporte.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showDetailsDialog(AttendanceReport report) {
    return showDialog<void>(
      context: context,
      builder: (context) => _ReportDetailsDialog(report: report),
    );
  }

  Future<void> _loadEventReport() async {
    final selectedEventId = _selectedEventId;

    if (selectedEventId == null) {
      setState(() {
        _eventReport = null;
        _eventErrorMessage = 'Selecciona un evento para ver el reporte.';
      });
      return;
    }

    setState(() {
      _isLoadingEventReport = true;
      _eventErrorMessage = null;
    });

    try {
      final events = await dependencies.eventsApiService.fetchEvents();
      EventRecord? selectedEvent;

      for (final event in events) {
        if (event.id == selectedEventId) {
          selectedEvent = event;
          break;
        }
      }

      if (!mounted) {
        return;
      }

      if (selectedEvent == null) {
        setState(() {
          _events = events;
          _eventReport = null;
          _eventErrorMessage =
              'No se encontro el evento seleccionado para el reporte.';
        });
        return;
      }

      setState(() {
        _events = events;
        _eventReport = selectedEvent;
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _eventReport = null;
        _eventErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _eventReport = null;
        _eventErrorMessage = 'No fue posible cargar el reporte del evento.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEventReport = false;
        });
      }
    }
  }

  EventRecord? _findEventById(int? eventId) {
    if (eventId == null) {
      return null;
    }

    for (final event in _events) {
      if (event.id == eventId) {
        return event;
      }
    }

    return null;
  }

  Future<void> _openEventPicker() async {
    if (_isLoadingEvents) {
      return;
    }

    final selectedEventId = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _EventPickerSheet(events: _events, selectedEventId: _selectedEventId),
    );

    if (!mounted ||
        selectedEventId == null ||
        selectedEventId == _selectedEventId) {
      return;
    }

    setState(() {
      _selectedEventId = selectedEventId;
      _eventReport = null;
      _eventErrorMessage = null;
    });

    await _loadEventReport();
  }

  Future<void> _exportPdf() async {
    final report = _report;

    if (report == null || report.records.isEmpty) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final document = pw.Document();
      final rows = report.records
          .map(
            (record) => [
              record.eventName,
              _formatDateTime(record.eventDate),
              record.officeName ?? 'Sin oficina',
              record.isAttended ? 'Asistio' : 'Observado',
              record.eventAddress ?? 'Sin direccion',
            ],
          )
          .toList(growable: false);

      document.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Text(
              'Reporte de asistencias',
              style: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'CI: ${report.person.ci}',
              style: const pw.TextStyle(fontSize: _reportPdfFontSize),
            ),
            pw.Text(
              'Nombre: ${report.person.fullName}',
              style: const pw.TextStyle(fontSize: _reportPdfFontSize),
            ),
            pw.Text(
              'Oficina: ${report.person.officeName ?? 'Sin oficina'}',
              style: const pw.TextStyle(fontSize: _reportPdfFontSize),
            ),
            if ((report.person.email ?? '').isNotEmpty)
              pw.Text(
                'Correo: ${report.person.email}',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              ),
            if ((report.person.jobTitle ?? '').isNotEmpty)
              pw.Text(
                'Cargo: ${report.person.jobTitle}',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              ),
            if ((report.person.numeroItem ?? '').isNotEmpty)
              pw.Text(
                'Numero item: ${report.person.numeroItem}',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              ),
            if ((report.person.qrCode ?? '').isNotEmpty)
              pw.Text(
                'Codigo QR: ${report.person.qrCode}',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Evento',
                'Fecha',
                'Oficina',
                'Estado',
                'Direccion',
              ],
              data: rows,
              headerStyle: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE7DFF6),
              ),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => document.save(),
        name: 'reporte-${report.person.ci}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _exportEventPdf() async {
    final event = _eventReport;

    if (event == null) {
      return;
    }

    setState(() {
      _isExportingEventPdf = true;
    });

    try {
      final document = pw.Document();
      final attendedRows = _buildEventPdfRows(
        _sortEventRosterEntries(event.attended),
      );
      final observedRows = _buildEventPdfRows(
        _sortEventRosterEntries(event.observed),
      );

      document.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Text(
              'Reporte del evento',
              style: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Evento: ${event.name}',
              style: const pw.TextStyle(fontSize: _reportPdfFontSize),
            ),
            pw.Text(
              'Fecha: ${_formatDateTime(event.date)}',
              style: const pw.TextStyle(fontSize: _reportPdfFontSize),
            ),
            pw.Text(
              'Direccion: ${event.address?.trim().isNotEmpty == true ? event.address! : 'Sin direccion'}',
              style: const pw.TextStyle(fontSize: _reportPdfFontSize),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Asistieron (${event.attended.length})',
              style: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (attendedRows.isEmpty)
              pw.Text(
                'No hay personas registradas como asistidas.',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'N°',
                  'CI',
                  'Nombre',
                  'Tipo',
                  'Oficina',
                  'Escaneado',
                ],
                columnWidths: _eventReportPdfColumnWidths,
                data: attendedRows,
                headerStyle: pw.TextStyle(
                  fontSize: _reportPdfFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE7DFF6),
                ),
              ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Observados (${event.observed.length})',
              style: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (observedRows.isEmpty)
              pw.Text(
                'No hay personas registradas como observadas.',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'N°',
                  'CI',
                  'Nombre',
                  'Tipo',
                  'Oficina',
                  'Escaneado',
                ],
                columnWidths: _eventReportPdfColumnWidths,
                data: observedRows,
                headerStyle: pw.TextStyle(
                  fontSize: _reportPdfFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF1ECF9),
                ),
              ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => document.save(),
        name: _buildEventReportFilename(event),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExportingEventPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final eventReport = _eventReport;
    final selectedEvent = _findEventById(_selectedEventId);

    return Scrollbar(
      controller: _pageScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _pageScrollController,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reportes por CI',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Busca una persona por CI y revisa en que eventos asistio o fue observada.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _ciController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por CI',
                        hintText: 'Ingresa el CI de la persona',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _search,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.search_rounded),
                          label: const Text('Buscar'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              report == null ||
                                  report.records.isEmpty ||
                                  _isExporting
                              ? null
                              : _exportPdf,
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Descargar PDF'),
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _errorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD94841),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (report == null && !_isLoading && _errorMessage == null)
              const _ReportsHintState()
            else if (report != null) ...[
              _ReportPersonCard(
                report: report,
                onViewDetails: () => _showDetailsDialog(report),
              ),
              const SizedBox(height: 16),
              if (report.records.isEmpty)
                const _EmptyReportState()
              else
                _ReportDetailsHintCard(
                  report: report,
                  onViewDetails: () => _showDetailsDialog(report),
                ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reportes por evento',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Selecciona un evento y veras tablas separadas con las personas asistidas y observadas.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    _EventPickerField(
                      label: 'Seleccionar evento',
                      value: selectedEvent == null
                          ? null
                          : _eventSearchLabel(selectedEvent),
                      hintText: _isLoadingEvents
                          ? 'Cargando eventos...'
                          : 'Buscar evento por nombre o fecha',
                      onTap: _isLoadingEvents ? null : _openEventPicker,
                    ),
                    if (_isLoadingEvents) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              eventReport == null ||
                                  _isExportingEventPdf ||
                                  _isLoadingEventReport
                              ? null
                              : _exportEventPdf,
                          icon: _isExportingEventPdf
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(
                            _isLoadingEventReport
                                ? 'Generando reporte...'
                                : 'Descargar PDF',
                          ),
                        ),
                      ],
                    ),
                    if (_eventErrorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _eventErrorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD94841),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (eventReport == null &&
                !_isLoadingEvents &&
                !_isLoadingEventReport &&
                _eventErrorMessage == null)
              const _EventReportsHintState()
            else if (eventReport != null)
              _EventReportCard(event: eventReport),
          ],
        ),
      ),
    );
  }
}

class _ReportPersonCard extends StatelessWidget {
  const _ReportPersonCard({required this.report, required this.onViewDetails});

  final AttendanceReport report;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final attendedCount = report.records
        .where((item) => item.isAttended)
        .length;
    final observedCount = report.records.length - attendedCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Base64Avatar(
                  size: 78,
                  fallbackLabel: report.person.fullName,
                  photoSource: report.person.photoUrl,
                  borderRadius: BorderRadius.circular(22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                        onPressed: onViewDetails,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          alignment: Alignment.centerLeft,
                          foregroundColor: AppPalette.orange,
                        ),
                        child: Text(
                          report.person.fullName,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppPalette.orange,
                                decoration: TextDecoration.underline,
                                decorationColor: AppPalette.orange,
                              ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('CI: ${report.person.ci}'),
                      if ((report.person.email ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(report.person.email!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ReportInfoLine(
              label: 'Oficina',
              value: report.person.officeName ?? 'Sin oficina',
            ),
            if ((report.person.jobTitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              _ReportInfoLine(label: 'Cargo', value: report.person.jobTitle!),
            ],
            if ((report.person.tipoVinculo ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              _ReportInfoLine(
                label: 'Tipo',
                value: _tipoVinculoLabel(report.person.tipoVinculo!),
              ),
            ],
            if ((report.person.numeroItem ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              _ReportInfoLine(
                label: 'Numero item',
                value: report.person.numeroItem!,
              ),
            ],
            if ((report.person.qrCode ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              _ReportInfoLine(label: 'Codigo QR', value: report.person.qrCode!),
            ],
            const SizedBox(height: 10),
            Text(
              'Toca el nombre para ver el detalle de eventos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ReportChip(
                  icon: Icons.fact_check_outlined,
                  label: '${report.records.length} registros',
                ),
                _ReportChip(
                  icon: Icons.how_to_reg_rounded,
                  label: '$attendedCount asistio',
                ),
                _ReportChip(
                  icon: Icons.visibility_outlined,
                  label: '$observedCount observado',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              attendedCount == 1
                  ? 'Asistio a 1 evento.'
                  : 'Asistio a $attendedCount eventos.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportDetailsHintCard extends StatelessWidget {
  const _ReportDetailsHintCard({
    required this.report,
    required this.onViewDetails,
  });

  final AttendanceReport report;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle disponible',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              'Se encontraron ${report.records.length} registros para esta persona.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onViewDetails,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Ver eventos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportChip extends StatelessWidget {
  const _ReportChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppPalette.orange),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ReportsHintState extends StatelessWidget {
  const _ReportsHintState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.search_rounded, color: AppPalette.orange),
            ),
            const SizedBox(height: 14),
            Text(
              'Busca una persona para generar el reporte',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ingresa un CI y consulta todos sus registros disponibles.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventReportsHintState extends StatelessWidget {
  const _EventReportsHintState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.event_note_rounded,
                color: AppPalette.orange,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Selecciona un evento para generar el reporte',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando elijas un evento veras tablas separadas para asistidos y observados.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: AppPalette.orange,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Este usuario no asistio a ninguna',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando tenga registros del QR, aqui veras sus eventos.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventReportCard extends StatelessWidget {
  const _EventReportCard({required this.event});

  final EventRecord event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.name, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Fecha: ${_formatDateTime(event.date)}'),
            const SizedBox(height: 4),
            Text(
              event.address?.trim().isNotEmpty == true
                  ? 'Direccion: ${event.address!}'
                  : 'Sin direccion registrada.',
            ),
            const SizedBox(height: 4),
            Text('Creado por: ${event.createdBy}'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ReportChip(
                  icon: Icons.apartment_rounded,
                  label: event.officeCountLabel,
                ),
                _ReportChip(
                  icon: Icons.how_to_reg_rounded,
                  label: '${event.attended.length} asistieron',
                ),
                _ReportChip(
                  icon: Icons.visibility_outlined,
                  label: '${event.observed.length} observados',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _EventRosterTableSection(
              title: 'Asistidos',
              entries: _sortEventRosterEntries(event.attended),
              emptyMessage:
                  'Todavia no hay personas registradas como asistidas.',
            ),
            const SizedBox(height: 18),
            _EventRosterTableSection(
              title: 'Observados',
              entries: _sortEventRosterEntries(event.observed),
              emptyMessage:
                  'Todavia no hay personas registradas como observadas.',
              accentBackground: AppPalette.surfaceSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventRosterTableSection extends StatelessWidget {
  const _EventRosterTableSection({
    required this.title,
    required this.entries,
    required this.emptyMessage,
    this.accentBackground = AppPalette.orangeSoft,
  });

  final String title;
  final List<EventRosterEntry> entries;
  final String emptyMessage;
  final Color accentBackground;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppPalette.line),
            ),
            child: Text(emptyMessage),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(110),
                1: FixedColumnWidth(240),
                2: FixedColumnWidth(220),
                3: FixedColumnWidth(150),
                4: FixedColumnWidth(110),
              },
              border: TableBorder.all(color: AppPalette.line),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: accentBackground),
                  children: const [
                    _EventTableHeaderCell(label: 'CI'),
                    _EventTableHeaderCell(label: 'Nombre'),
                    _EventTableHeaderCell(label: 'Oficina'),
                    _EventTableHeaderCell(label: 'Escaneado'),
                    _EventTableHeaderCell(label: 'Tipo'),
                  ],
                ),
                for (final entry in entries)
                  TableRow(
                    children: [
                      _EventTableValueCell(
                        value: entry.ci?.trim().isNotEmpty == true
                            ? entry.ci!.trim()
                            : 'Sin CI',
                      ),
                      _EventTableValueCell(value: entry.fullName),
                      _EventTableValueCell(
                        value: entry.officeName ?? 'Sin oficina',
                      ),
                      _EventTableDateTimeCell(
                        dateTime: entry.registeredAt,
                      ),
                      _EventTableValueCell(
                        value: _eventRosterTipoLabel(entry.tipoVinculo),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EventTableHeaderCell extends StatelessWidget {
  const _EventTableHeaderCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EventTableValueCell extends StatelessWidget {
  const _EventTableValueCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _EventTableDateTimeCell extends StatelessWidget {
  const _EventTableDateTimeCell({required this.dateTime});

  final DateTime dateTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(dateTime),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            _formatTime(dateTime),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _EventPickerField extends StatelessWidget {
  const _EventPickerField({
    required this.label,
    required this.hintText,
    required this.onTap,
    this.value,
  });

  final String label;
  final String hintText;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    final hasValue = value != null && value!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: IgnorePointer(
            child: InputDecorator(
              isEmpty: !hasValue,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: isEnabled ? AppPalette.ink : AppPalette.muted,
                ),
              ),
              child: hasValue
                  ? Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _EventPickerSheet extends StatefulWidget {
  const _EventPickerSheet({
    required this.events,
    required this.selectedEventId,
  });

  final List<EventRecord> events;
  final int? selectedEventId;

  @override
  State<_EventPickerSheet> createState() => _EventPickerSheetState();
}

class _EventPickerSheetState extends State<_EventPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim();

    if (nextQuery == _query) {
      return;
    }

    setState(() {
      _query = nextQuery;
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.toLowerCase();
    final filteredEvents = widget.events
        .where((event) {
          if (normalizedQuery.isEmpty) {
            return true;
          }

          return _eventSearchLabel(
            event,
          ).toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppPalette.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Seleccionar evento',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Busca por nombre o fecha y desplaza la lista para elegir el evento.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Buscar evento',
                    hintText: 'Escribe el nombre o la fecha',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filteredEvents.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppPalette.surfaceSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppPalette.line),
                          ),
                          child: const Text(
                            'No se encontraron eventos con ese criterio.',
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _scrollController,
                            itemCount: filteredEvents.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final event = filteredEvents[index];
                              final isSelected =
                                  event.id == widget.selectedEventId;

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      Navigator.of(context).pop(event.id),
                                  borderRadius: BorderRadius.circular(18),
                                  child: Ink(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppPalette.orangeSoft
                                          : AppPalette.surfaceSoft,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppPalette.orange
                                            : AppPalette.line,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                event.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _formatDateTime(event.date),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          isSelected
                                              ? Icons.check_circle_rounded
                                              : Icons.chevron_right_rounded,
                                          color: isSelected
                                              ? AppPalette.orange
                                              : AppPalette.muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportDetailsDialog extends StatelessWidget {
  const _ReportDetailsDialog({required this.report});

  final AttendanceReport report;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Base64Avatar(
                size: 68,
                fallbackLabel: report.person.fullName,
                photoSource: report.person.photoUrl,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.person.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'CI: ${report.person.ci}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: report.records.isEmpty ? 80 : 340,
        child: report.records.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Este usuario no asistio a ninguna.'),
              )
            : Scrollbar(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: report.records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final record = report.records[index];

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppPalette.surfaceSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppPalette.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.eventName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('Fecha: ${_formatDate(record.eventDate)}'),
                          const SizedBox(height: 4),
                          Text('Hora: ${_formatTime(record.eventDate)}'),
                          const SizedBox(height: 4),
                          Text(
                            'Fecha escaneo: ${_formatDate(record.registeredAt)}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hora escaneo: ${_formatTime(record.registeredAt)}',
                          ),
                          if ((record.eventAddress ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Direccion: ${record.eventAddress}'),
                          ],
                          if ((record.note ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Nota: ${record.note}'),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ReportInfoLine extends StatelessWidget {
  const _ReportInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text('$label: $value');
  }
}

String _formatDateTime(DateTime dateTime) {
  return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
}

String _formatDate(DateTime dateTime) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  return '${dateTime.day.toString().padLeft(2, '0')} ${months[dateTime.month - 1]} ${dateTime.year}';
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');

  return '$hour:$minute';
}

List<List<String>> _buildEventPdfRows(List<EventRosterEntry> entries) {
  return entries
      .asMap()
      .entries
      .map(
        (entry) => [
          '${entry.key + 1}',
          entry.value.ci?.trim().isNotEmpty == true
              ? entry.value.ci!.trim()
              : 'Sin CI',
          entry.value.fullName,
          entry.value.officeName ?? 'Sin oficina',
          _formatDateTime(entry.value.registeredAt),
          _eventRosterTipoLabel(entry.value.tipoVinculo),
        ],
      )
      .toList(growable: false);
}

List<EventRosterEntry> _sortEventRosterEntries(List<EventRosterEntry> entries) {
  final sortedEntries = [...entries];

  sortedEntries.sort((left, right) {
    final typeOrderComparison = _eventRosterTypeOrder(
      left.tipoVinculo,
    ).compareTo(_eventRosterTypeOrder(right.tipoVinculo));

    if (typeOrderComparison != 0) {
      return typeOrderComparison;
    }

    final nameComparison = left.fullName.toLowerCase().compareTo(
      right.fullName.toLowerCase(),
    );

    if (nameComparison != 0) {
      return nameComparison;
    }

    return left.registeredAt.compareTo(right.registeredAt);
  });

  return sortedEntries;
}

int _eventRosterTypeOrder(String? tipoVinculo) {
  switch ((tipoVinculo ?? '').trim().toUpperCase()) {
    case 'ITEM':
      return 0;
    case 'EVENTUAL':
      return 1;
    case 'CONSULTOR':
      return 2;
    default:
      return 3;
  }
}

String _buildEventReportFilename(EventRecord event) {
  final normalizedName = event.name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  final safeName = normalizedName.isEmpty ? 'evento' : normalizedName;
  return 'reporte-evento-${event.id}-$safeName.pdf';
}

String _eventSearchLabel(EventRecord event) {
  return '${event.name} | ${_formatDateTime(event.date)}';
}

String _eventRosterTipoLabel(String? tipoVinculo) {
  final normalizedValue = (tipoVinculo ?? '').trim();

  if (normalizedValue.isEmpty) {
    return 'Sin tipo';
  }

  return _tipoVinculoLabel(normalizedValue);
}

String _tipoVinculoLabel(String value) {
  switch (value.toUpperCase()) {
    case 'ITEM':
      return 'Item';
    case 'EVENTUAL':
      return 'Eventual';
    case 'CONSULTOR':
      return 'Consultor';
    default:
      return value;
  }
}
