import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/excel_exporter.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/base64_avatar.dart';
import '../../../auth/domain/entities/cargo_option.dart';
import '../../../auth/domain/entities/office_option.dart';
import '../../../events/domain/entities/event_record.dart';
import '../../domain/entities/attendance_report.dart';

const double _reportPdfFontSize = 8;
const Map<int, pw.TableColumnWidth> _personnelPdfColumnWidths = {
  0: pw.FixedColumnWidth(45),
  1: pw.FixedColumnWidth(58),
  2: pw.FixedColumnWidth(126),
  3: pw.FixedColumnWidth(58),
  4: pw.FixedColumnWidth(92),
  5: pw.FixedColumnWidth(116),
  6: pw.FixedColumnWidth(116),
  7: pw.FixedColumnWidth(50),
};
const int _healthOfficeLevel = 11;
const int _eventReportRowsPerPage = 20;
const _personnelTipoOptions = ['ITEM', 'EVENTUAL', 'CONSULTOR', 'SERVICIOS'];

enum _PersonnelExcelExportMode { normal, byItem }

enum _EventReportSortOrder { typeName, item, office, time }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _personnelSearchController =
      TextEditingController();
  final ScrollController _pageScrollController = ScrollController();
  List<EventRecord> _events = const [];
  List<AppUser> _personnelUsers = const [];
  List<OfficeOption> _personnelOffices = const [];
  List<CargoOption> _personnelCargos = const [];
  AttendanceReport? _report;
  EventRecord? _eventReport;
  int? _selectedEventId;
  _EventReportSortOrder _eventReportSortOrder = _EventReportSortOrder.typeName;
  _PersonnelStatusFilter _personnelStatus = _PersonnelStatusFilter.all;
  Set<String> _personnelTipos = {};
  Set<int> _personnelOfficeIds = {};
  Set<String> _personnelCargoCodes = {};
  bool _isLoading = false;
  bool _isLoadingEvents = false;
  bool _isLoadingPersonnel = false;
  bool _isLoadingEventReport = false;
  bool _isExporting = false;
  bool _isExportingEventPdf = false;
  bool _isExportingEventExcel = false;
  bool _isExportingNonRequiredEventPdf = false;
  bool _isExportingNonRequiredEventExcel = false;
  bool _isExportingPersonnelPdf = false;
  bool _isExportingPersonnelExcel = false;
  String? _errorMessage;
  String? _eventErrorMessage;
  String? _personnelErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadEventOptions();
  }

  @override
  void dispose() {
    _ciController.dispose();
    _personnelSearchController.dispose();
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
            selectedEvent = await dependencies.eventsApiService.fetchEventById(
              event.id,
            );
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
      final selectedEvent = await dependencies.eventsApiService.fetchEventById(
        selectedEventId,
      );
      final events = await dependencies.eventsApiService.fetchEvents(
        forceRefresh: true,
      );

      if (!mounted) {
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

  List<AppUser> get _filteredPersonnelUsers {
    final normalizedQuery = _normalizeSearch(_personnelSearchController.text);
    final selectedOfficeIds = _personnelOfficeIds;
    final selectedCargoCodes = _personnelCargoCodes;
    final selectedTipos = _personnelTipos;
    final filteredUsers = _personnelUsers
        .where((user) {
          if (user.role == AppUserRole.lunch) {
            return false;
          }

          switch (_personnelStatus) {
            case _PersonnelStatusFilter.active:
              if (!user.activo) {
                return false;
              }
              break;
            case _PersonnelStatusFilter.inactive:
              if (user.activo) {
                return false;
              }
              break;
            case _PersonnelStatusFilter.all:
              break;
          }

          if (selectedTipos.isNotEmpty &&
              !selectedTipos.contains(user.tipoVinculo.trim().toUpperCase())) {
            return false;
          }

          if (selectedOfficeIds.isNotEmpty &&
              !_userMatchesAnyOffice(user, selectedOfficeIds)) {
            return false;
          }

          if (selectedCargoCodes.isNotEmpty &&
              !_userMatchesAnyCargo(user, selectedCargoCodes)) {
            return false;
          }

          if (normalizedQuery.isNotEmpty) {
            final searchable = _normalizeSearch(
              [
                user.ci,
                user.fullName,
                user.numeroItem,
                user.tipoVinculo,
                user.primaryOfficeName,
                user.officeName,
                user.commissionOfficeName,
                user.effectiveCargo,
                user.cargo,
              ].whereType<String>().join(' '),
            );

            if (!searchable.contains(normalizedQuery)) {
              return false;
            }
          }

          return true;
        })
        .toList(growable: false);

    return _sortPersonnelUsers(filteredUsers);
  }

  Future<void> _ensurePersonnelReferences() async {
    if (_personnelUsers.isNotEmpty &&
        _personnelOffices.isNotEmpty &&
        _personnelCargos.isNotEmpty) {
      return;
    }

    setState(() {
      _isLoadingPersonnel = true;
      _personnelErrorMessage = null;
    });

    try {
      final results = await Future.wait([
        dependencies.authApiService.fetchUsers(
          requesterEmail: widget.currentUser.email,
        ),
        dependencies.authApiService.fetchOffices(),
        dependencies.authApiService.fetchCargos(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _personnelUsers = results[0] as List<AppUser>;
        _personnelOffices = results[1] as List<OfficeOption>;
        _personnelCargos = results[2] as List<CargoOption>;
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _personnelErrorMessage = error.message;
      });
      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      const message = 'No fue posible cargar los datos de personal.';
      setState(() {
        _personnelErrorMessage = message;
      });
      AppAlert.showError(context, message);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPersonnel = false;
        });
      }
    }
  }

  Future<void> _refreshPersonnelReferences() async {
    setState(() {
      _personnelUsers = const [];
    });
    await _ensurePersonnelReferences();
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

  Future<void> _pickPersonnelOffices() async {
    await _ensurePersonnelReferences();

    if (!mounted || _personnelOffices.isEmpty) {
      return;
    }

    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SelectionSheet<OfficeOption, int>(
        title: 'Seleccionar oficinas',
        items: _personnelOffices,
        selectedValues: _personnelOfficeIds,
        valueOf: (office) => office.id,
        titleOf: (office) => office.name,
        subtitleOf: (office) => 'Cod. ${office.code} | Nivel ${office.level}',
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _personnelOfficeIds = result;
    });
  }

  Future<void> _pickPersonnelCargos() async {
    await _ensurePersonnelReferences();

    if (!mounted || _personnelCargos.isEmpty) {
      return;
    }

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SelectionSheet<CargoOption, String>(
        title: 'Seleccionar cargos',
        items: _personnelCargos,
        selectedValues: _personnelCargoCodes,
        valueOf: (cargo) => cargo.code,
        titleOf: (cargo) => cargo.name,
        subtitleOf: (cargo) => 'Cod. ${cargo.code}',
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _personnelCargoCodes = result;
    });
  }

  void _togglePersonnelTipo(String tipo) {
    setState(() {
      if (_personnelTipos.contains(tipo)) {
        _personnelTipos.remove(tipo);
      } else {
        _personnelTipos.add(tipo);
      }
    });
  }

  void _clearPersonnelFilters() {
    setState(() {
      _personnelSearchController.clear();
      _personnelStatus = _PersonnelStatusFilter.all;
      _personnelTipos = {};
      _personnelOfficeIds = {};
      _personnelCargoCodes = {};
    });
  }

  String _personnelFiltersSummary() {
    final parts = <String>[_personnelStatus.label];

    if (_personnelTipos.isNotEmpty) {
      parts.add('Tipos: ${_personnelTipos.map(_tipoVinculoLabel).join(', ')}');
    }

    if (_personnelOfficeIds.isNotEmpty) {
      parts.add('${_personnelOfficeIds.length} oficinas');
    }

    if (_personnelCargoCodes.isNotEmpty) {
      parts.add('${_personnelCargoCodes.length} cargos');
    }

    final search = _personnelSearchController.text.trim();
    if (search.isNotEmpty) {
      parts.add('Busqueda: $search');
    }

    return parts.join(' | ');
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
        event,
        _sortEventRosterEntries(event.attended, _eventReportSortOrder),
      );
      final lateRows = _buildLateEventPdfRows(
        event,
        _sortEventRosterEntries(event.late, _eventReportSortOrder),
      );
      final observedRows = _buildEventPdfRows(
        event,
        _sortEventRosterEntries(event.observed, _eventReportSortOrder),
      );
      final absenteeRows = _buildEventAbsenteePdfRows(
        event,
        _sortEventAbsenteeEntries(event.absentees, _eventReportSortOrder),
      );
      final rosterHeaders = _buildEventPdfHeaders(event);
      final absenteeHeaders = _buildEventPdfHeaders(
        event,
        includeRequirementReason: true,
      );
      final rosterColumnWidths = _buildEventPdfColumnWidths(
        rosterHeaders.length,
      );
      final absenteeColumnWidths = _buildEventPdfColumnWidths(
        absenteeHeaders.length,
        includeRequirementReason: true,
      );

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
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
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Total',
                'Asistieron',
                'Retrasados',
                'Observados',
                'Faltaron',
              ],
              data: [
                [
                  '${event.totalTrackedPeople}',
                  '${event.resolvedAttendedCount}',
                  '${event.resolvedLateCount}',
                  '${event.resolvedObservedCount}',
                  '${event.resolvedAbsenteeCount}',
                ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE7DFF6),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Asistieron (${event.resolvedAttendedCount})',
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
                headers: rosterHeaders,
                columnWidths: rosterColumnWidths,
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
              'Retrasados (${event.resolvedLateCount})',
              style: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (lateRows.isEmpty)
              pw.Text(
                'No hay personas registradas fuera de horario.',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: rosterHeaders,
                columnWidths: rosterColumnWidths,
                data: lateRows,
                headerStyle: pw.TextStyle(
                  fontSize: _reportPdfFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFFE6CC),
                ),
              ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Observados (${event.resolvedObservedCount})',
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
                headers: rosterHeaders,
                columnWidths: rosterColumnWidths,
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
            pw.SizedBox(height: 18),
            pw.Text(
              'Faltaron (${event.resolvedAbsenteeCount})',
              style: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (absenteeRows.isEmpty)
              pw.Text(
                'No hay funcionarios elegidos pendientes de asistencia.',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: absenteeHeaders,
                columnWidths: absenteeColumnWidths,
                data: absenteeRows,
                headerStyle: pw.TextStyle(
                  fontSize: _reportPdfFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFFF3E0),
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

  Future<void> _exportNonRequiredEventPdf() async {
    final event = _eventReport;

    if (event == null) {
      return;
    }

    if (event.nonRequired.isEmpty) {
      AppAlert.showWarning(
        context,
        'Este evento no tiene asistentes no obligados.',
      );
      return;
    }

    setState(() {
      _isExportingNonRequiredEventPdf = true;
    });

    try {
      final document = pw.Document();
      final rows = _buildEventPdfRows(
        event,
        _sortEventRosterEntries(event.nonRequired, _eventReportSortOrder),
      );
      final rosterHeaders = _buildEventPdfHeaders(event);
      final rosterColumnWidths = _buildEventPdfColumnWidths(
        rosterHeaders.length,
      );

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) => [
            pw.Text(
              'Reporte de asistentes no obligados',
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
              'No obligados (${event.resolvedNonRequiredCount})',
              style: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: rosterHeaders,
              columnWidths: rosterColumnWidths,
              data: rows,
              headerStyle: pw.TextStyle(
                fontSize: _reportPdfFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFDDEBFF),
              ),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => document.save(),
        name: _buildNonRequiredEventReportFilename(event),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExportingNonRequiredEventPdf = false;
        });
      }
    }
  }

  Future<void> _exportNonRequiredEventExcel() async {
    final event = _eventReport;

    if (event == null) {
      return;
    }

    final rows = _buildEventExcelRowsForEntries(
      event,
      event.nonRequired,
      _eventReportSortOrder,
    );

    if (rows.isEmpty) {
      AppAlert.showWarning(
        context,
        'Este evento no tiene asistentes no obligados.',
      );
      return;
    }

    setState(() {
      _isExportingNonRequiredEventExcel = true;
    });

    try {
      await exportExcelWorkbook(
        fileName: _buildNonRequiredEventExcelFilename(event),
        sheetName: 'No obligados',
        headers: _buildEventExcelHeaders(event),
        rows: rows,
      );

      if (mounted) {
        AppAlert.showSuccess(context, 'Excel de no obligados generado.');
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible exportar no obligados.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingNonRequiredEventExcel = false;
        });
      }
    }
  }

  Future<void> _exportEventExcel() async {
    final event = _eventReport;

    if (event == null) {
      return;
    }

    final rows = _buildEventExcelRows(event, _eventReportSortOrder);

    if (rows.isEmpty) {
      AppAlert.showWarning(
        context,
        'No hay registros de control para exportar.',
      );
      return;
    }

    setState(() {
      _isExportingEventExcel = true;
    });

    try {
      await exportExcelWorkbook(
        fileName: _buildEventExcelFilename(event),
        sheetName: 'Reporte evento',
        headers: _buildEventExcelHeaders(event),
        rows: rows,
      );

      if (mounted) {
        AppAlert.showSuccess(context, 'Excel del evento generado.');
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible exportar el evento.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingEventExcel = false;
        });
      }
    }
  }

  Future<void> _selectPersonnelExcelExportMode() async {
    if (_isExportingPersonnelExcel) {
      return;
    }

    final mode = await showModalBottomSheet<_PersonnelExcelExportMode>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.table_view_rounded),
                  title: const Text('Reporte normal'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_PersonnelExcelExportMode.normal),
                ),
                ListTile(
                  leading: const Icon(Icons.format_list_numbered_rounded),
                  title: const Text('Reporte por item'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_PersonnelExcelExportMode.byItem),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mode == null) {
      return;
    }

    await _exportPersonnelExcel(mode);
  }

  Future<void> _exportPersonnelExcel(_PersonnelExcelExportMode mode) async {
    await _ensurePersonnelReferences();

    if (!mounted) {
      return;
    }

    final users = switch (mode) {
      _PersonnelExcelExportMode.normal => [..._filteredPersonnelUsers],
      _PersonnelExcelExportMode.byItem => _sortPersonnelUsersByItem(
        _filteredPersonnelUsers,
      ),
    };

    if (users.isEmpty) {
      AppAlert.showWarning(
        context,
        'No hay usuarios para exportar con esos filtros.',
      );
      return;
    }

    setState(() {
      _isExportingPersonnelExcel = true;
    });

    try {
      final suffix = mode == _PersonnelExcelExportMode.byItem
          ? 'por_item'
          : 'general';
      final headers = _personnelExcelHeaders(mode);
      final officeLevelsById = _buildOfficeLevelsById(_personnelOffices);
      final mayoraltyUsers = users
          .where((user) => !_isHealthPersonnelUser(user, officeLevelsById))
          .toList(growable: false);
      final healthUsers = users
          .where((user) => _isHealthPersonnelUser(user, officeLevelsById))
          .toList(growable: false);

      await exportExcelWorkbookSheets(
        fileName:
            'reporte-personal-$suffix-${_formatFilenameDate(DateTime.now())}.xlsx',
        sheets: [
          ExcelWorkbookSheet(
            sheetName: 'Alcaldia',
            headers: headers,
            rows: _buildPersonnelExcelRows(mayoraltyUsers, mode),
          ),
          ExcelWorkbookSheet(
            sheetName: 'Salud',
            headers: headers,
            rows: _buildPersonnelExcelRows(healthUsers, mode),
          ),
        ],
      );

      if (mounted) {
        AppAlert.showSuccess(context, 'Excel de personal generado.');
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible exportar personal.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPersonnelExcel = false;
        });
      }
    }
  }

  Future<void> _exportPersonnelPdf() async {
    await _ensurePersonnelReferences();

    if (!mounted) {
      return;
    }

    final users = _filteredPersonnelUsers;

    if (users.isEmpty) {
      AppAlert.showWarning(
        context,
        'No hay usuarios para exportar con esos filtros.',
      );
      return;
    }

    setState(() {
      _isExportingPersonnelPdf = true;
    });

    try {
      final document = pw.Document();
      final officeLevelsById = _buildOfficeLevelsById(_personnelOffices);
      final mayoraltyUsers = users
          .where((user) => !_isHealthPersonnelUser(user, officeLevelsById))
          .toList(growable: false);
      final healthUsers = users
          .where((user) => _isHealthPersonnelUser(user, officeLevelsById))
          .toList(growable: false);
      final filters = _personnelFiltersSummary();

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) {
            final content = <pw.Widget>[
              pw.Text(
                'Reporte de personal',
                style: pw.TextStyle(
                  fontSize: _reportPdfFontSize + 2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Total exportado: ${users.length}',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              ),
              pw.Text(
                'Alcaldia: ${mayoraltyUsers.length} | Salud: ${healthUsers.length}',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              ),
              pw.Text(
                'Filtros: $filters',
                style: const pw.TextStyle(fontSize: _reportPdfFontSize),
              ),
              pw.SizedBox(height: 12),
            ];

            content.addAll(
              _buildPersonnelPdfSection(
                title: 'Alcaldia',
                users: mayoraltyUsers,
              ),
            );

            if (healthUsers.isNotEmpty) {
              content.add(pw.SizedBox(height: 14));
              content.addAll(
                _buildPersonnelPdfSection(title: 'Salud', users: healthUsers),
              );
            }

            return content;
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => document.save(),
        name: 'reporte-personal-${_formatFilenameDate(DateTime.now())}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPersonnelPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final eventReport = _eventReport;
    final selectedEvent = _findEventById(_selectedEventId);
    final filteredPersonnelUsers = _filteredPersonnelUsers;

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
                      'Exportacion de personal',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Genera un PDF con item, CI, nombre, tipo, cargo, unidad, comision y estado. Incluye todos los roles excepto almuerzo.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _personnelSearchController,
                      onTap: _ensurePersonnelReferences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Buscar',
                        hintText: 'CI, nombre, item, cargo u oficina',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon:
                            _personnelSearchController.text.trim().isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  setState(_personnelSearchController.clear);
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<_PersonnelStatusFilter>(
                          value: _personnelStatus,
                          borderRadius: BorderRadius.circular(16),
                          underline: const SizedBox.shrink(),
                          items: _PersonnelStatusFilter.values
                              .map(
                                (status) => DropdownMenuItem(
                                  value: status,
                                  child: Text(status.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }

                            setState(() {
                              _personnelStatus = value;
                            });
                          },
                        ),
                        for (final tipo in _personnelTipoOptions)
                          FilterChip(
                            selected: _personnelTipos.contains(tipo),
                            label: Text(_tipoVinculoLabel(tipo)),
                            onSelected: (_) => _togglePersonnelTipo(tipo),
                          ),
                        OutlinedButton.icon(
                          onPressed: _isLoadingPersonnel
                              ? null
                              : _pickPersonnelOffices,
                          icon: const Icon(Icons.apartment_rounded),
                          label: Text(
                            _personnelOfficeIds.isEmpty
                                ? 'Oficinas'
                                : '${_personnelOfficeIds.length} oficinas',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isLoadingPersonnel
                              ? null
                              : _pickPersonnelCargos,
                          icon: const Icon(Icons.work_outline_rounded),
                          label: Text(
                            _personnelCargoCodes.isEmpty
                                ? 'Cargos'
                                : '${_personnelCargoCodes.length} cargos',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _clearPersonnelFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Limpiar'),
                        ),
                      ],
                    ),
                    if (_isLoadingPersonnel) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ReportChip(
                          icon: Icons.people_alt_outlined,
                          label: _personnelUsers.isEmpty
                              ? 'Sin cargar'
                              : '${filteredPersonnelUsers.length} usuarios',
                        ),
                        OutlinedButton.icon(
                          onPressed: _isLoadingPersonnel
                              ? null
                              : _refreshPersonnelReferences,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Actualizar'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _isLoadingPersonnel || _isExportingPersonnelExcel
                              ? null
                              : _selectPersonnelExcelExportMode,
                          icon: _isExportingPersonnelExcel
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_download_outlined),
                          label: Text(
                            _isExportingPersonnelExcel
                                ? 'Exportando...'
                                : 'Exportar Excel',
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed:
                              _isLoadingPersonnel || _isExportingPersonnelPdf
                              ? null
                              : _exportPersonnelPdf,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                          icon: _isExportingPersonnelPdf
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Exportar PDF'),
                        ),
                      ],
                    ),
                    if (_personnelErrorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _personnelErrorMessage!,
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
                      'Selecciona un evento y veras tablas separadas con las personas asistidas, retrasadas, observadas y faltantes.',
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_EventReportSortOrder>(
                      initialValue: _eventReportSortOrder,
                      decoration: const InputDecoration(
                        labelText: 'Orden del reporte',
                        prefixIcon: Icon(Icons.sort_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _EventReportSortOrder.typeName,
                          child: Text('Tipo y nombre'),
                        ),
                        DropdownMenuItem(
                          value: _EventReportSortOrder.item,
                          child: Text('Item'),
                        ),
                        DropdownMenuItem(
                          value: _EventReportSortOrder.office,
                          child: Text('Oficina'),
                        ),
                        DropdownMenuItem(
                          value: _EventReportSortOrder.time,
                          child: Text('Hora'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _eventReportSortOrder = value;
                        });
                      },
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
                                  _isExportingEventExcel ||
                                  _isExportingNonRequiredEventPdf ||
                                  _isExportingNonRequiredEventExcel ||
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
                        OutlinedButton.icon(
                          onPressed:
                              eventReport == null ||
                                  _isExportingEventPdf ||
                                  _isExportingEventExcel ||
                                  _isExportingNonRequiredEventPdf ||
                                  _isExportingNonRequiredEventExcel ||
                                  _isLoadingEventReport
                              ? null
                              : _exportNonRequiredEventPdf,
                          icon: _isExportingNonRequiredEventPdf
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.groups_2_outlined),
                          label: Text(
                            _isExportingNonRequiredEventPdf
                                ? 'Generando no obligados...'
                                : 'Descargar no obligados PDF',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              eventReport == null ||
                                  _isExportingEventPdf ||
                                  _isExportingEventExcel ||
                                  _isExportingNonRequiredEventPdf ||
                                  _isExportingNonRequiredEventExcel ||
                                  _isLoadingEventReport
                              ? null
                              : _exportNonRequiredEventExcel,
                          icon: _isExportingNonRequiredEventExcel
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_download_outlined),
                          label: Text(
                            _isExportingNonRequiredEventExcel
                                ? 'Exportando no obligados...'
                                : 'Descargar no obligados Excel',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              eventReport == null ||
                                  _isExportingEventPdf ||
                                  _isExportingEventExcel ||
                                  _isExportingNonRequiredEventPdf ||
                                  _isExportingNonRequiredEventExcel ||
                                  _isLoadingEventReport
                              ? null
                              : _exportEventExcel,
                          icon: _isExportingEventExcel
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_download_outlined),
                          label: Text(
                            _isExportingEventExcel
                                ? 'Exportando...'
                                : 'Descargar Excel',
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
              _EventReportCard(
                event: eventReport,
                sortOrder: _eventReportSortOrder,
              ),
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
              'Cuando elijas un evento veras tablas separadas para asistidos, observados y faltantes.',
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
  const _EventReportCard({required this.event, required this.sortOrder});

  final EventRecord event;
  final _EventReportSortOrder sortOrder;

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
                  icon: Icons.schedule_rounded,
                  label: '${event.late.length} retrasados',
                ),
                _ReportChip(
                  icon: Icons.visibility_outlined,
                  label: '${event.observed.length} observados',
                ),
                _ReportChip(
                  icon: Icons.person_off_outlined,
                  label: '${event.absentees.length} faltaron',
                ),
                _ReportChip(
                  icon: Icons.groups_2_outlined,
                  label: '${event.nonRequired.length} no obligados',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _EventRosterTableSection(
              title: 'Asistidos',
              entries: _sortEventRosterEntries(event.attended, sortOrder),
              emptyMessage:
                  'Todavia no hay personas registradas como asistidas.',
            ),
            const SizedBox(height: 18),
            _EventRosterTableSection(
              title: 'Retrasados',
              entries: _sortEventRosterEntries(event.late, sortOrder),
              emptyMessage: 'No hay personas registradas fuera de horario.',
              accentBackground: const Color(0xFFFFE6CC),
              useLateRegisteredAt: true,
            ),
            const SizedBox(height: 18),
            _EventRosterTableSection(
              title: 'Observados',
              entries: _sortEventRosterEntries(event.observed, sortOrder),
              emptyMessage:
                  'Todavia no hay personas registradas como observadas.',
              accentBackground: AppPalette.surfaceSoft,
            ),
            const SizedBox(height: 18),
            _EventAbsenteeTableSection(
              title: 'Faltantes',
              entries: _sortEventAbsenteeEntries(event.absentees, sortOrder),
              emptyMessage:
                  'No hay funcionarios elegidos pendientes de asistencia.',
              accentBackground: const Color(0xFFFFF3E0),
            ),
            const SizedBox(height: 18),
            _EventRosterTableSection(
              title: 'No obligados',
              entries: _sortEventRosterEntries(event.nonRequired, sortOrder),
              emptyMessage:
                  'No hay personas registradas fuera de la asignacion del evento.',
              accentBackground: const Color(0xFFDDEBFF),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventRosterTableSection extends StatefulWidget {
  const _EventRosterTableSection({
    required this.title,
    required this.entries,
    required this.emptyMessage,
    this.accentBackground = AppPalette.orangeSoft,
    this.useLateRegisteredAt = false,
  });

  final String title;
  final List<EventRosterEntry> entries;
  final String emptyMessage;
  final Color accentBackground;
  final bool useLateRegisteredAt;

  @override
  State<_EventRosterTableSection> createState() =>
      _EventRosterTableSectionState();
}

class _EventRosterTableSectionState extends State<_EventRosterTableSection> {
  int _page = 0;

  int get _totalPages => widget.entries.isEmpty
      ? 1
      : ((widget.entries.length - 1) ~/ _eventReportRowsPerPage) + 1;

  int get _safePage => _page.clamp(0, _totalPages - 1);

  @override
  void didUpdateWidget(covariant _EventRosterTableSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.entries != widget.entries && _page != _safePage) {
      _page = _safePage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startIndex = _safePage * _eventReportRowsPerPage;
    final endIndex = (startIndex + _eventReportRowsPerPage).clamp(
      0,
      widget.entries.length,
    );
    final visibleEntries = widget.entries.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (widget.entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppPalette.line),
            ),
            child: Text(widget.emptyMessage),
          )
        else ...[
          _EventSectionPaginationBar(
            page: _safePage,
            totalPages: _totalPages,
            totalRows: widget.entries.length,
            startIndex: startIndex,
            endIndex: endIndex,
            onPrevious: _safePage == 0
                ? null
                : () => setState(() {
                    _page = _safePage - 1;
                  }),
            onNext: _safePage >= _totalPages - 1
                ? null
                : () => setState(() {
                    _page = _safePage + 1;
                  }),
          ),
          const SizedBox(height: 10),
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
                  decoration: BoxDecoration(color: widget.accentBackground),
                  children: const [
                    _EventTableHeaderCell(label: 'CI'),
                    _EventTableHeaderCell(label: 'Nombre'),
                    _EventTableHeaderCell(label: 'Oficina'),
                    _EventTableHeaderCell(label: 'Escaneado'),
                    _EventTableHeaderCell(label: 'Tipo'),
                  ],
                ),
                for (final entry in visibleEntries)
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
                        dateTime:
                            widget.useLateRegisteredAt &&
                                entry.lateRegisteredAt != null
                            ? entry.lateRegisteredAt!
                            : entry.registeredAt,
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
      ],
    );
  }
}

class _EventAbsenteeTableSection extends StatefulWidget {
  const _EventAbsenteeTableSection({
    required this.title,
    required this.entries,
    required this.emptyMessage,
    this.accentBackground = AppPalette.orangeSoft,
  });

  final String title;
  final List<EventAbsenteeEntry> entries;
  final String emptyMessage;
  final Color accentBackground;

  @override
  State<_EventAbsenteeTableSection> createState() =>
      _EventAbsenteeTableSectionState();
}

class _EventAbsenteeTableSectionState
    extends State<_EventAbsenteeTableSection> {
  int _page = 0;

  int get _totalPages => widget.entries.isEmpty
      ? 1
      : ((widget.entries.length - 1) ~/ _eventReportRowsPerPage) + 1;

  int get _safePage => _page.clamp(0, _totalPages - 1);

  @override
  void didUpdateWidget(covariant _EventAbsenteeTableSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.entries != widget.entries && _page != _safePage) {
      _page = _safePage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startIndex = _safePage * _eventReportRowsPerPage;
    final endIndex = (startIndex + _eventReportRowsPerPage).clamp(
      0,
      widget.entries.length,
    );
    final visibleEntries = widget.entries.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (widget.entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppPalette.line),
            ),
            child: Text(widget.emptyMessage),
          )
        else ...[
          _EventSectionPaginationBar(
            page: _safePage,
            totalPages: _totalPages,
            totalRows: widget.entries.length,
            startIndex: startIndex,
            endIndex: endIndex,
            onPrevious: _safePage == 0
                ? null
                : () => setState(() {
                    _page = _safePage - 1;
                  }),
            onNext: _safePage >= _totalPages - 1
                ? null
                : () => setState(() {
                    _page = _safePage + 1;
                  }),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(110),
                1: FixedColumnWidth(240),
                2: FixedColumnWidth(220),
                3: FixedColumnWidth(150),
                4: FixedColumnWidth(150),
                5: FixedColumnWidth(110),
              },
              border: TableBorder.all(color: AppPalette.line),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: widget.accentBackground),
                  children: const [
                    _EventTableHeaderCell(label: 'CI'),
                    _EventTableHeaderCell(label: 'Nombre'),
                    _EventTableHeaderCell(label: 'Oficina'),
                    _EventTableHeaderCell(label: 'Debia ir por'),
                    _EventTableHeaderCell(label: 'Estado'),
                    _EventTableHeaderCell(label: 'Tipo'),
                  ],
                ),
                for (final entry in visibleEntries)
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
                      _EventTableValueCell(
                        value:
                            entry.requirementReason?.trim().isNotEmpty == true
                            ? entry.requirementReason!.trim()
                            : 'Regla del evento',
                      ),
                      const _EventTableValueCell(value: 'No asistio'),
                      _EventTableValueCell(
                        value: _eventRosterTipoLabel(entry.tipoVinculo),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EventSectionPaginationBar extends StatelessWidget {
  const _EventSectionPaginationBar({
    required this.page,
    required this.totalPages,
    required this.totalRows,
    required this.startIndex,
    required this.endIndex,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int totalRows;
  final int startIndex;
  final int endIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final label = totalRows == 0
        ? 'Sin registros'
        : '${startIndex + 1}-$endIndex de $totalRows';

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$label | Pagina ${page + 1} de $totalPages',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IconButton.outlined(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Pagina anterior',
        ),
        IconButton.outlined(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Pagina siguiente',
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

class _SelectionSheet<T, V> extends StatefulWidget {
  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.selectedValues,
    required this.valueOf,
    required this.titleOf,
    required this.subtitleOf,
  });

  final String title;
  final List<T> items;
  final Set<V> selectedValues;
  final V Function(T item) valueOf;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;

  @override
  State<_SelectionSheet<T, V>> createState() => _SelectionSheetState<T, V>();
}

class _SelectionSheetState<T, V> extends State<_SelectionSheet<T, V>> {
  final TextEditingController _searchController = TextEditingController();
  late Set<V> _draftSelected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _draftSelected = {...widget.selectedValues};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<T> get _filteredItems {
    final normalizedQuery = _normalizeSearch(_query);

    if (normalizedQuery.isEmpty) {
      return widget.items;
    }

    return widget.items
        .where((item) {
          final searchable = _normalizeSearch(
            '${widget.titleOf(item)} ${widget.subtitleOf(item)}',
          );
          return searchable.contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  void _toggle(T item) {
    final value = widget.valueOf(item);

    setState(() {
      if (_draftSelected.contains(value)) {
        _draftSelected.remove(value);
      } else {
        _draftSelected.add(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final filteredItems = _filteredItems;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 18, 12, 12 + bottomInset),
        child: Material(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(28),
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      labelText: 'Buscar',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${_draftSelected.length} seleccionados'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredItems.isEmpty
                        ? const Center(child: Text('No hay resultados.'))
                        : ListView.separated(
                            itemCount: filteredItems.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              final value = widget.valueOf(item);
                              final selected = _draftSelected.contains(value);

                              return CheckboxListTile(
                                value: selected,
                                onChanged: (_) => _toggle(item),
                                title: Text(widget.titleOf(item)),
                                subtitle: Text(widget.subtitleOf(item)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                tileColor: selected
                                    ? AppPalette.orangeSoft
                                    : Colors.white,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(_draftSelected.clear),
                        child: const Text('Limpiar'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_draftSelected),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                ],
              ),
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

enum _PersonnelStatusFilter {
  all('Todos'),
  active('Activos'),
  inactive('Inactivos');

  const _PersonnelStatusFilter(this.label);

  final String label;
}

String _formatDateTime(DateTime dateTime) {
  return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
}

String _formatDateOnly(DateTime dateTime) {
  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');

  return '$day/$month/${dateTime.year}';
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

List<String> _buildEventPdfHeaders(
  EventRecord event, {
  bool includeRequirementReason = false,
}) {
  return [
    'Item',
    'CI',
    'Nombre',
    'Tipo',
    'Oficina',
    if (includeRequirementReason) 'Debia ir por',
    for (final control in _sortedEventControls(event.controls)) control.name,
  ];
}

Map<int, pw.TableColumnWidth> _buildEventPdfColumnWidths(
  int headerCount, {
  bool includeRequirementReason = false,
}) {
  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(38),
    1: const pw.FixedColumnWidth(52),
    2: const pw.FixedColumnWidth(105),
    3: const pw.FixedColumnWidth(42),
    4: const pw.FixedColumnWidth(118),
  };
  var controlStartIndex = 5;

  if (includeRequirementReason) {
    widths[5] = const pw.FixedColumnWidth(66);
    controlStartIndex = 6;
  }

  for (var index = controlStartIndex; index < headerCount; index++) {
    widths[index] = const pw.FixedColumnWidth(46);
  }

  return widths;
}

List<List<String>> _buildEventPdfRows(
  EventRecord event,
  List<EventRosterEntry> entries,
) {
  final controls = _sortedEventControls(event.controls);

  return entries
      .map((entry) {
        final controlsById = _resolveEventExcelControlsById(
          entry: entry,
          controls: controls,
        );

        return [
          entry.numeroItem?.trim() ?? '',
          entry.ci?.trim().isNotEmpty == true ? entry.ci!.trim() : 'Sin CI',
          entry.fullName,
          _eventRosterTipoLabel(entry.tipoVinculo),
          entry.officeName ?? 'Sin oficina',
          for (final control in controls)
            _formatEventControlReportCell(controlsById[control.id]),
        ];
      })
      .toList(growable: false);
}

List<List<String>> _buildLateEventPdfRows(
  EventRecord event,
  List<EventRosterEntry> entries,
) {
  return _buildEventPdfRows(event, entries);
}

List<List<String>> _buildEventAbsenteePdfRows(
  EventRecord event,
  List<EventAbsenteeEntry> entries,
) {
  final controls = _sortedEventControls(event.controls);

  return entries
      .map(
        (entry) => [
          entry.numeroItem?.trim() ?? '',
          entry.ci?.trim().isNotEmpty == true ? entry.ci!.trim() : 'Sin CI',
          entry.fullName,
          _eventRosterTipoLabel(entry.tipoVinculo),
          entry.officeName ?? 'Sin oficina',
          entry.requirementReason?.trim().isNotEmpty == true
              ? entry.requirementReason!.trim()
              : 'Regla del evento',
          for (final _ in controls) 'F',
        ],
      )
      .toList(growable: false);
}

List<String> _buildEventExcelHeaders(EventRecord event) {
  return [
    'Fecha',
    'Item',
    'CI',
    'Nombre completo',
    'Tipo',
    'Oficina',
    'Cargo',
    for (final control in _sortedEventControls(event.controls)) control.name,
  ];
}

List<List<Object?>> _buildEventExcelRows(
  EventRecord event,
  _EventReportSortOrder sortOrder,
) {
  return [
    ..._buildEventExcelRowsForEntries(event, [
      ...event.attended,
      ...event.observed,
    ], sortOrder),
    ..._buildEventAbsenteeExcelRows(event, event.absentees, sortOrder),
  ];
}

List<List<Object?>> _buildEventAbsenteeExcelRows(
  EventRecord event,
  List<EventAbsenteeEntry> entries,
  _EventReportSortOrder sortOrder,
) {
  final controls = _sortedEventControls(event.controls);
  final sortedEntries = _sortEventAbsenteeEntries(entries, sortOrder);

  return sortedEntries
      .map(
        (entry) => [
          _formatDateOnly(event.date),
          entry.numeroItem?.trim() ?? '',
          entry.ci?.trim().isNotEmpty == true ? entry.ci!.trim() : '',
          entry.fullName,
          _eventRosterTipoLabel(entry.tipoVinculo),
          entry.officeName ?? '',
          entry.jobTitle ?? '',
          for (final _ in controls) 'F',
        ],
      )
      .toList(growable: false);
}

List<List<Object?>> _buildEventExcelRowsForEntries(
  EventRecord event,
  List<EventRosterEntry> entries,
  _EventReportSortOrder sortOrder,
) {
  final controls = _sortedEventControls(event.controls);
  final rows = <List<Object?>>[];
  final sortedEntries = _sortEventRosterEntries(entries, sortOrder);

  for (final entry in sortedEntries) {
    rows.add(
      _buildEventAttendanceExcelRow(
        event: event,
        entry: entry,
        controls: controls,
      ),
    );
  }

  return rows;
}

List<Object?> _buildEventAttendanceExcelRow({
  required EventRecord event,
  required EventRosterEntry entry,
  required List<EventControl> controls,
}) {
  final controlsById = _resolveEventExcelControlsById(
    entry: entry,
    controls: controls,
  );

  return [
    _formatDateOnly(event.date),
    entry.numeroItem?.trim() ?? '',
    entry.ci?.trim().isNotEmpty == true ? entry.ci!.trim() : '',
    entry.fullName,
    _eventRosterTipoLabel(entry.tipoVinculo),
    entry.officeName ?? '',
    entry.jobTitle ?? '',
    for (final control in controls)
      controlsById[control.id] == null
          ? 'F'
          : _formatEventControlReportCell(controlsById[control.id]),
  ];
}

String _formatEventControlReportCell(EventAttendanceControl? control) {
  if (control == null) {
    return 'F';
  }

  final marker = control.isLate
      ? 'R'
      : control.isAttended
      ? 'P'
      : 'O';

  return '${_formatTime(control.registeredAt)} $marker';
}

Map<int, EventAttendanceControl> _resolveEventExcelControlsById({
  required EventRosterEntry entry,
  required List<EventControl> controls,
}) {
  final controlsById = {
    for (final control in entry.controls) control.controlId: control,
  };

  if (entry.controls.length != 1 || controls.length < 2) {
    return controlsById;
  }

  final onlyControl = entry.controls.single;
  final firstControl = controls.first;
  final secondControl = controls[1];

  if (onlyControl.controlId != firstControl.id ||
      !_isSecondEventControlTime(onlyControl.registeredAt)) {
    return controlsById;
  }

  return {secondControl.id: onlyControl};
}

bool _isSecondEventControlTime(DateTime registeredAt) {
  return registeredAt.hour > 10 ||
      (registeredAt.hour == 10 && registeredAt.minute >= 30);
}

List<EventControl> _sortedEventControls(List<EventControl> controls) {
  final sortedControls = [...controls];
  sortedControls.sort((left, right) {
    final orderComparison = left.order.compareTo(right.order);

    if (orderComparison != 0) {
      return orderComparison;
    }

    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });

  return sortedControls;
}

List<List<String>> _buildPersonnelPdfRows(List<AppUser> users) {
  return users
      .map(
        (user) => [
          _cleanPdfValue(user.numeroItem, fallback: '-'),
          _cleanPdfValue(user.ci, fallback: 'Sin CI'),
          _cleanPdfValue(user.fullName, fallback: 'Sin nombre'),
          _tipoVinculoLabel(user.tipoVinculo),
          _cleanPdfValue(user.effectiveCargo, fallback: 'Sin cargo'),
          _cleanPdfValue(
            user.primaryOfficeName ?? user.officeName ?? user.unidad,
            fallback: 'Sin unidad',
          ),
          _cleanPdfValue(
            user.commissionOfficeName,
            fallback: user.hasCommission ? 'Sin dato' : '-',
          ),
          user.estadoLabel,
        ],
      )
      .toList(growable: false);
}

List<pw.Widget> _buildPersonnelPdfSection({
  required String title,
  required List<AppUser> users,
}) {
  return [
    pw.Text(
      '$title (${users.length})',
      style: pw.TextStyle(
        fontSize: _reportPdfFontSize + 1,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
    pw.SizedBox(height: 6),
    if (users.isEmpty)
      pw.Text(
        'Sin personal para mostrar.',
        style: const pw.TextStyle(fontSize: _reportPdfFontSize),
      )
    else
      pw.TableHelper.fromTextArray(
        headers: const [
          'Item',
          'CI',
          'Nombre',
          'Tipo',
          'Cargo',
          'Unidad',
          'Comision',
          'Estado',
        ],
        columnWidths: _personnelPdfColumnWidths,
        data: _buildPersonnelPdfRows(users),
        headerStyle: pw.TextStyle(
          fontSize: _reportPdfFontSize,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: _reportPdfFontSize - 1),
        cellAlignment: pw.Alignment.centerLeft,
        headerDecoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFE7DFF6),
        ),
      ),
  ];
}

Map<int, int> _buildOfficeLevelsById(List<OfficeOption> offices) {
  return {for (final office in offices) office.id: office.level};
}

bool _isHealthPersonnelUser(AppUser user, Map<int, int> officeLevelsById) {
  final officeIds = <int?>{
    user.officeId,
    user.primaryOfficeId,
    user.commissionOfficeId,
  };

  return officeIds.any(
    (officeId) =>
        officeId != null && officeLevelsById[officeId] == _healthOfficeLevel,
  );
}

List<String> _personnelExcelHeaders(_PersonnelExcelExportMode mode) {
  if (mode == _PersonnelExcelExportMode.byItem) {
    return const [
      'Item',
      'CI',
      'Nombre completo',
      'Unidad',
      'Cargo',
      'Comision',
    ];
  }

  return const [
    'Nro',
    'Item',
    'CI',
    'Nombre completo',
    'Celular',
    'Usuario',
    'Rol',
    'Tipo',
    'Cargo',
    'Subcargo',
    'Unidad',
    'Comision',
    'Lugar',
    'Estado',
  ];
}

List<List<Object?>> _buildPersonnelExcelRows(
  List<AppUser> users,
  _PersonnelExcelExportMode mode,
) {
  if (mode == _PersonnelExcelExportMode.byItem) {
    return [
      for (final user in users)
        [
          user.numeroItem,
          user.ci,
          user.fullName,
          user.primaryOfficeName ?? user.officeName ?? user.unidad,
          user.effectiveCargo,
          user.commissionOfficeName ?? '',
        ],
    ];
  }

  return [
    for (var index = 0; index < users.length; index++)
      [
        index + 1,
        users[index].numeroItem,
        users[index].ci,
        users[index].fullName,
        users[index].celular,
        users[index].email,
        users[index].roleLabel,
        _tipoVinculoLabel(users[index].tipoVinculo),
        users[index].effectiveCargo,
        users[index].subcargo,
        users[index].primaryOfficeName ??
            users[index].officeName ??
            users[index].unidad,
        users[index].commissionOfficeName ?? '',
        users[index].lugar,
        users[index].estadoLabel,
      ],
  ];
}

List<AppUser> _sortPersonnelUsers(List<AppUser> users) {
  final sortedUsers = [...users];

  sortedUsers.sort((left, right) {
    final typeComparison = _eventRosterTypeOrder(
      left.tipoVinculo,
    ).compareTo(_eventRosterTypeOrder(right.tipoVinculo));

    if (typeComparison != 0) {
      return typeComparison;
    }

    final leftItem = int.tryParse(left.numeroItem.trim());
    final rightItem = int.tryParse(right.numeroItem.trim());

    if (leftItem != null && rightItem != null && leftItem != rightItem) {
      return leftItem.compareTo(rightItem);
    }

    if (leftItem != null && rightItem == null) {
      return -1;
    }

    if (leftItem == null && rightItem != null) {
      return 1;
    }

    return left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase());
  });

  return sortedUsers;
}

List<AppUser> _sortPersonnelUsersByItem(List<AppUser> users) {
  final sortedUsers = [...users];

  sortedUsers.sort((left, right) {
    final leftItem = _personnelItemSortValue(left.numeroItem);
    final rightItem = _personnelItemSortValue(right.numeroItem);
    final itemComparison = leftItem.compareTo(rightItem);

    if (itemComparison != 0) {
      return itemComparison;
    }

    return left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase());
  });

  return sortedUsers;
}

String _personnelItemSortValue(String value) {
  final normalized = value.trim();

  if (normalized.isEmpty) {
    return '1|';
  }

  final numberMatch = RegExp(r'\d+').firstMatch(normalized);
  final number = numberMatch == null
      ? null
      : int.tryParse(numberMatch.group(0)!);

  if (number == null) {
    return '1|${normalized.toLowerCase()}';
  }

  return '0|${number.toString().padLeft(12, '0')}|${normalized.toLowerCase()}';
}

bool _userMatchesAnyOffice(AppUser user, Set<int> officeIds) {
  final userOfficeIds = <int?>{
    user.officeId,
    user.primaryOfficeId,
    user.commissionOfficeId,
  };

  return userOfficeIds.any((id) => id != null && officeIds.contains(id));
}

bool _userMatchesAnyCargo(AppUser user, Set<String> cargoCodes) {
  final userCargoCodes = <String?>{
    user.effectiveCargoCode,
    user.subcargoCodigo,
    user.cargoCodigo,
  };

  return userCargoCodes.any((code) {
    final normalizedCode = code?.trim();
    return normalizedCode != null &&
        normalizedCode.isNotEmpty &&
        cargoCodes.contains(normalizedCode);
  });
}

String _cleanPdfValue(String? value, {required String fallback}) {
  final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (cleaned == null || cleaned.isEmpty) {
    return fallback;
  }

  return cleaned;
}

String _normalizeSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .trim();
}

List<EventRosterEntry> _sortEventRosterEntries(
  List<EventRosterEntry> entries,
  _EventReportSortOrder sortOrder,
) {
  final sortedEntries = [...entries];

  sortedEntries.sort((left, right) {
    final orderComparison = switch (sortOrder) {
      _EventReportSortOrder.item => _compareEventItems(
        left.numeroItem,
        right.numeroItem,
      ),
      _EventReportSortOrder.office => _compareNullableText(
        left.officeName,
        right.officeName,
      ),
      _EventReportSortOrder.time => left.registeredAt.compareTo(
        right.registeredAt,
      ),
      _EventReportSortOrder.typeName => _compareEventRosterTypeName(
        left.tipoVinculo,
        left.fullName,
        right.tipoVinculo,
        right.fullName,
      ),
    };

    if (orderComparison != 0) {
      return orderComparison;
    }

    return _compareEventRosterTypeName(
      left.tipoVinculo,
      left.fullName,
      right.tipoVinculo,
      right.fullName,
    );
  });

  return sortedEntries;
}

List<EventAbsenteeEntry> _sortEventAbsenteeEntries(
  List<EventAbsenteeEntry> entries,
  _EventReportSortOrder sortOrder,
) {
  final sortedEntries = [...entries];

  sortedEntries.sort((left, right) {
    final orderComparison = switch (sortOrder) {
      _EventReportSortOrder.item => _compareEventItems(
        left.numeroItem,
        right.numeroItem,
      ),
      _EventReportSortOrder.office => _compareNullableText(
        left.officeName,
        right.officeName,
      ),
      _EventReportSortOrder.time ||
      _EventReportSortOrder.typeName => _compareEventRosterTypeName(
        left.tipoVinculo,
        left.fullName,
        right.tipoVinculo,
        right.fullName,
      ),
    };

    if (orderComparison != 0) {
      return orderComparison;
    }

    return _compareEventRosterTypeName(
      left.tipoVinculo,
      left.fullName,
      right.tipoVinculo,
      right.fullName,
    );
  });

  return sortedEntries;
}

int _compareEventRosterTypeName(
  String? leftTipoVinculo,
  String leftFullName,
  String? rightTipoVinculo,
  String rightFullName,
) {
  final typeOrderComparison = _eventRosterTypeOrder(
    leftTipoVinculo,
  ).compareTo(_eventRosterTypeOrder(rightTipoVinculo));

  if (typeOrderComparison != 0) {
    return typeOrderComparison;
  }

  return leftFullName.toLowerCase().compareTo(rightFullName.toLowerCase());
}

int _compareEventItems(String? leftItem, String? rightItem) {
  return _personnelItemSortValue(
    leftItem ?? '',
  ).compareTo(_personnelItemSortValue(rightItem ?? ''));
}

int _compareNullableText(String? left, String? right) {
  final leftValue = left?.trim().toLowerCase() ?? '';
  final rightValue = right?.trim().toLowerCase() ?? '';

  if (leftValue.isEmpty && rightValue.isNotEmpty) {
    return 1;
  }

  if (leftValue.isNotEmpty && rightValue.isEmpty) {
    return -1;
  }

  return leftValue.compareTo(rightValue);
}

int _eventRosterTypeOrder(String? tipoVinculo) {
  switch ((tipoVinculo ?? '').trim().toUpperCase()) {
    case 'ITEM':
      return 0;
    case 'EVENTUAL':
      return 1;
    case 'CONSULTOR':
      return 2;
    case 'SERVICIOS':
      return 3;
    default:
      return 4;
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

String _buildNonRequiredEventReportFilename(EventRecord event) {
  final safeName = _eventSafeFilenameName(event);
  return 'no-obligados-evento-${event.id}-$safeName.pdf';
}

String _buildNonRequiredEventExcelFilename(EventRecord event) {
  final safeName = _eventSafeFilenameName(event);
  return 'no-obligados-evento-${event.id}-$safeName.xlsx';
}

String _eventSafeFilenameName(EventRecord event) {
  final normalizedName = event.name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  return normalizedName.isEmpty ? 'evento' : normalizedName;
}

String _buildEventExcelFilename(EventRecord event) {
  final normalizedName = event.name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  final safeName = normalizedName.isEmpty ? 'evento' : normalizedName;
  return 'reporte-evento-${event.id}-$safeName.xlsx';
}

String _formatFilenameDate(DateTime value) {
  final year = value.year.toString();
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');

  return '$year$month$day-$hour$minute';
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
    case 'SERVICIOS':
      return 'Servicios';
    default:
      return value;
  }
}
