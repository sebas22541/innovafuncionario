import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../events/domain/entities/event_record.dart';
import '../../domain/entities/qr_generation_map_record.dart';

const _defaultQrMapCenter = LatLng(-16.489689, -68.119293);
const _qrMapMaxZoom = 15.4;
const _qrMapMaxNativeZoom = 18;
const _qrMapSelectedRecordZoom = 15.2;

class QrGenerationMapScreen extends StatefulWidget {
  const QrGenerationMapScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<QrGenerationMapScreen> createState() => _QrGenerationMapScreenState();
}

class _QrGenerationMapScreenState extends State<QrGenerationMapScreen> {
  final TextEditingController _ciController = TextEditingController();
  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _mapSectionKey = GlobalKey();

  List<EventRecord> _events = const [];
  List<QrGenerationMapRecord> _records = const [];
  QrGenerationMapSource _selectedSource = QrGenerationMapSource.qrGenerations;
  int? _selectedEventId;
  int? _selectedControlId;
  String? _selectedRecordId;
  _MapSearchMode _searchMode = _MapSearchMode.ci;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  bool _isLoading = false;
  bool _isLoadingEvents = false;
  bool _isMapReady = false;
  bool _hasSearched = false;
  String? _errorMessage;
  LatLng? _pendingCenter;
  CameraFit? _pendingCameraFit;

  @override
  void initState() {
    super.initState();
    _rangeStart = _buildDefaultRangeStart();
    _rangeEnd = _buildDefaultRangeEnd();
    _ciController.addListener(_handleSearchChanged);
    _loadEventOptions();
  }

  @override
  void dispose() {
    _ciController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  DateTime _buildDefaultRangeStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  DateTime _buildDefaultRangeEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _loadRecords() async {
    final isEventSource = _selectedSource == QrGenerationMapSource.eventScans;
    final query = !isEventSource || _searchMode == _MapSearchMode.ci
        ? _ciController.text.trim()
        : '';
    final selectedEventId = isEventSource && _searchMode == _MapSearchMode.event
        ? _selectedEventId
        : null;
    final selectedControlId =
        isEventSource && _searchMode == _MapSearchMode.event
        ? _selectedControlId
        : null;
    final errorLoadingMessage = isEventSource
        ? 'No fue posible cargar el mapa de registros del evento.'
        : 'No fue posible cargar el mapa de QR generados.';

    if ((!isEventSource || _searchMode == _MapSearchMode.ci) && query.isEmpty) {
      const message = 'Ingresa un CI para buscar.';
      AppAlert.showWarning(context, message);
      setState(() {
        _records = const [];
        _selectedRecordId = null;
        _isLoading = false;
        _hasSearched = true;
        _errorMessage = message;
      });
      return;
    }

    if (isEventSource &&
        _searchMode == _MapSearchMode.event &&
        selectedEventId == null) {
      const message = 'Selecciona un evento para buscar.';
      AppAlert.showWarning(context, message);
      setState(() {
        _records = const [];
        _selectedRecordId = null;
        _isLoading = false;
        _hasSearched = true;
        _errorMessage = message;
      });
      return;
    }

    if ((!isEventSource || _searchMode == _MapSearchMode.ci) &&
        query.length < 3) {
      AppAlert.showWarning(context, 'Ingresa un CI valido para buscar.');
      setState(() {
        _records = const [];
        _selectedRecordId = null;
        _hasSearched = true;
        _errorMessage = 'Ingresa un CI valido para buscar.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
    });

    try {
      if (!isEventSource || _searchMode == _MapSearchMode.ci) {
        final person = await dependencies.qrDetailsDataSource.getByCi(query);

        if (!mounted) {
          return;
        }

        if (person == null) {
          const message = 'No se encontro ningun usuario con ese CI.';
          setState(() {
            _records = const [];
            _selectedRecordId = null;
            _errorMessage = message;
          });
          AppAlert.showWarning(context, message);
          return;
        }
      }

      final records = await dependencies.reportsApiService
          .fetchQrGenerationRecords(
            requesterEmail: widget.currentUser.email,
            filterBy: !isEventSource || _searchMode == _MapSearchMode.ci
                ? QrGenerationMapFilter.ci
                : QrGenerationMapFilter.user,
            source: _selectedSource,
            generatedFrom: _rangeStart,
            generatedTo: _rangeEnd,
            eventId: selectedEventId,
            controlId: selectedControlId,
            query: query,
          );

      if (!mounted) {
        return;
      }

      if ((!isEventSource || _searchMode == _MapSearchMode.ci) &&
          records.isEmpty) {
        final message = isEventSource
            ? 'Este usuario no asistio a ningun evento en ese rango de fechas.'
            : 'Este usuario no genero ningun QR en ese rango de fechas.';
        setState(() {
          _records = const [];
          _selectedRecordId = null;
          _errorMessage = message;
        });
        AppAlert.showInfo(context, message);
        return;
      }

      setState(() {
        _records = records;
        _selectedRecordId = records.isEmpty ? null : records.first.id;
        _errorMessage = null;
      });

      _showAllRecordsOnMap(records);
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _records = const [];
        _selectedRecordId = null;
        _errorMessage = error.message;
      });
      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _records = const [];
        _selectedRecordId = null;
        _errorMessage = errorLoadingMessage;
      });
      AppAlert.showError(context, errorLoadingMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _moveMapTo(LatLng point, {double zoom = 15}) {
    if (_isMapReady) {
      _mapController.move(point, zoom);
      return;
    }

    _pendingCameraFit = null;
    _pendingCenter = point;
  }

  void _fitMapToRecords(List<QrGenerationMapRecord> records) {
    if (records.isEmpty) {
      return;
    }

    if (records.length == 1) {
      _moveMapTo(
        LatLng(records.first.latitude, records.first.longitude),
        zoom: 13.8,
      );
      return;
    }

    final points = records
        .map((record) => LatLng(record.latitude, record.longitude))
        .toList(growable: false);
    final fit = CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(48),
      maxZoom: 13.9,
    );

    if (_isMapReady) {
      _mapController.fitCamera(fit);
      return;
    }

    _pendingCenter = null;
    _pendingCameraFit = fit;
  }

  void _showAllRecordsOnMap(List<QrGenerationMapRecord> records) {
    if (records.isEmpty) {
      _pendingCenter = null;
      _pendingCameraFit = null;
      return;
    }

    _fitMapToRecords(records);
  }

  void _handleMapReady() {
    _isMapReady = true;
    final pendingCameraFit = _pendingCameraFit;
    final pendingCenter = _pendingCenter;

    if (pendingCameraFit != null) {
      _mapController.fitCamera(pendingCameraFit);
      _pendingCameraFit = null;
      _pendingCenter = null;
      return;
    }

    if (pendingCenter == null) {
      return;
    }

    _mapController.move(pendingCenter, 13.8);
    _pendingCenter = null;
  }

  Future<void> _pickRangeDate({required bool isStart}) async {
    final now = DateTime.now();
    final initialDate = isStart ? _rangeStart : _rangeEnd;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (pickedDate == null) {
      return;
    }

    final normalizedDate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
    );

    setState(() {
      if (isStart) {
        _rangeStart = normalizedDate;
        if (_rangeEnd.isBefore(normalizedDate)) {
          _rangeEnd = normalizedDate;
        }
      } else {
        _rangeEnd = normalizedDate;
        if (normalizedDate.isBefore(_rangeStart)) {
          _rangeStart = normalizedDate;
        }
      }

      _records = const [];
      _selectedRecordId = null;
      _errorMessage = null;
      _hasSearched = false;
    });
  }

  void _clearFilters() {
    setState(() {
      _ciController.clear();
      _selectedEventId = null;
      _selectedControlId = null;
      _rangeStart = _buildDefaultRangeStart();
      _rangeEnd = _buildDefaultRangeEnd();
      _records = const [];
      _selectedRecordId = null;
      _hasSearched = false;
      _errorMessage = null;
    });
  }

  void _setSearchMode(_MapSearchMode mode) {
    if (_searchMode == mode) {
      return;
    }

    setState(() {
      _searchMode = mode;
      _records = const [];
      _selectedRecordId = null;
      _hasSearched = false;
      _errorMessage = null;

      if (mode == _MapSearchMode.ci) {
        _selectedEventId = null;
        _selectedControlId = null;
      } else {
        _ciController.clear();
      }
    });
  }

  void _setSource(QrGenerationMapSource source) {
    if (_selectedSource == source) {
      return;
    }

    setState(() {
      _selectedSource = source;
      _searchMode = source == QrGenerationMapSource.eventScans
          ? _MapSearchMode.event
          : _MapSearchMode.ci;
      _ciController.clear();
      _selectedEventId = null;
      _selectedControlId = null;
      _records = const [];
      _selectedRecordId = null;
      _hasSearched = false;
      _errorMessage = null;
    });
  }

  void _selectRecord(
    QrGenerationMapRecord record, {
    bool openDetails = false,
    bool revealMap = false,
  }) {
    setState(() {
      _selectedRecordId = record.id;
    });

    _moveMapTo(
      LatLng(record.latitude, record.longitude),
      zoom: _qrMapSelectedRecordZoom,
    );

    if (revealMap) {
      _scrollMapIntoView();
    }

    if (openDetails) {
      _openPointSheet(record);
    }
  }

  Future<void> _scrollMapIntoView() async {
    final mapContext = _mapSectionKey.currentContext;

    if (mapContext == null) {
      return;
    }

    await Scrollable.ensureVisible(
      mapContext,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      alignment: 0.16,
    );
  }

  Future<void> _openPointSheet(QrGenerationMapRecord record) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _QrGenerationPointSheet(record: record),
    );
  }

  String _latestMetricLabel(QrGenerationMapRecord record) {
    final prefix = record.source == QrGenerationMapSource.eventScans
        ? 'Ultimo registro'
        : 'Ultimo QR';
    return '$prefix: ${_formatDate(record.generatedAt)} ${_formatTime(record.generatedAt)}';
  }

  Color _resolveMarkerColor(QrGenerationMapRecord record) {
    if (_selectedRecordId == record.id) {
      return const Color(0xFFD94841);
    }

    return AppPalette.orange;
  }

  Future<void> _loadEventOptions() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingEvents = true;
    });

    try {
      final events = await dependencies.eventsApiService.fetchEvents();

      if (!mounted) {
        return;
      }

      setState(() {
        _events = events;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage ??= 'No fue posible cargar la lista de eventos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
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

  EventControl? _findControlById(EventRecord? event, int? controlId) {
    if (event == null || controlId == null) {
      return null;
    }

    for (final control in event.controls) {
      if (control.id == controlId) {
        return control;
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MapEventPickerSheet(
        events: _events,
        selectedEventId: _selectedEventId,
      ),
    );

    if (!mounted || selectedEventId == _selectedEventId) {
      return;
    }

    setState(() {
      _selectedEventId = selectedEventId;
      _selectedControlId = null;
      _records = const [];
      _selectedRecordId = null;
      _hasSearched = false;
      _errorMessage = null;
    });
  }

  Future<void> _openControlPicker(EventRecord selectedEvent) async {
    final selectedControlId = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MapControlPickerSheet(
        controls: selectedEvent.controls,
        selectedControlId: _selectedControlId,
      ),
    );

    if (!mounted || selectedControlId == _selectedControlId) {
      return;
    }

    setState(() {
      _selectedControlId = selectedControlId;
      _records = const [];
      _selectedRecordId = null;
      _hasSearched = false;
      _errorMessage = null;
    });
  }

  String _formatDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();

    return '$day/$month/$year';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isEventSource = _selectedSource == QrGenerationMapSource.eventScans;
    final selectedEvent = _findEventById(_selectedEventId);
    final selectedControl = _findControlById(selectedEvent, _selectedControlId);
    final latestRecord = _records.isEmpty ? null : _records.first;
    final uniqueUsers = _records
        .map((record) => '${record.personaId}:${record.fullName}')
        .toSet()
        .length;
    final initialCenter = _records.isNotEmpty
        ? LatLng(_records.first.latitude, _records.first.longitude)
        : _defaultQrMapCenter;
    final emptyStateTitle = _errorMessage != null && _hasSearched
        ? _errorMessage!
        : _hasSearched
        ? isEventSource
              ? 'No hay registros para los filtros aplicados.'
              : 'No se encontraron QR generados en el rango seleccionado.'
        : isEventSource
        ? _searchMode == _MapSearchMode.ci
              ? 'Usa un CI y un rango de fechas para mostrar puntos en el mapa.'
              : 'Selecciona un evento, un rango de fechas y opcionalmente un control.'
        : 'Usa un CI y un rango de fechas para mostrar los QR generados.';
    final emptyStateDescription = _errorMessage != null && _hasSearched
        ? isEventSource
              ? _searchMode == _MapSearchMode.ci
                    ? 'Verifica el CI ingresado o ajusta las fechas.'
                    : 'Prueba con otro evento, control o ajusta el rango.'
              : 'Prueba con otro rango de fechas para revisar otras generaciones.'
        : _hasSearched
        ? isEventSource
              ? 'No hubo registros con ubicacion para esos filtros.'
              : 'No hubo generaciones con ubicacion dentro del rango seleccionado.'
        : isEventSource
        ? 'El mapa se mantiene vacio hasta que apliques una busqueda.'
        : 'El mapa mostrara todos los lugares donde ese CI genero QR dentro del rango.';
    final metricsPrimaryLabel = isEventSource
        ? '${_records.length} registros'
        : '${_records.length} QR generados';
    final mapTitle = isEventSource
        ? 'Mapa de registros por evento'
        : 'Mapa de QR generados';
    final listTitle = isEventSource
        ? 'Lista de registros'
        : 'Lista de QR generados';

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
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
                      mapTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 18),
                    _QrMapSourceSelector(
                      currentSource: _selectedSource,
                      onChanged: _setSource,
                    ),
                    const SizedBox(height: 14),
                    if (isEventSource) ...[
                      _MapSearchModeSelector(
                        currentMode: _searchMode,
                        onChanged: _setSearchMode,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (!isEventSource || _searchMode == _MapSearchMode.ci)
                      TextField(
                        controller: _ciController,
                        decoration: InputDecoration(
                          labelText: 'CI',
                          hintText: 'Ingresa el CI',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _ciController.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _ciController.clear();
                                    setState(() {
                                      _records = const [];
                                      _selectedRecordId = null;
                                      _hasSearched = false;
                                      _errorMessage = null;
                                    });
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                        onSubmitted: (_) => _loadRecords(),
                      )
                    else if (isEventSource)
                      Column(
                        children: [
                          _MapEventSelectorField(
                            value: selectedEvent == null
                                ? 'Seleccionar evento'
                                : _eventSearchLabel(selectedEvent),
                            isLoading: _isLoadingEvents,
                            onTap: _openEventPicker,
                            onClear: selectedEvent == null
                                ? null
                                : () {
                                    setState(() {
                                      _selectedEventId = null;
                                      _selectedControlId = null;
                                      _records = const [];
                                      _selectedRecordId = null;
                                      _hasSearched = false;
                                      _errorMessage = null;
                                    });
                                  },
                          ),
                          if (selectedEvent != null) ...[
                            const SizedBox(height: 12),
                            _MapControlSelectorField(
                              value: selectedControl == null
                                  ? 'Todos los controles'
                                  : '${selectedControl.order}. ${selectedControl.name}',
                              onTap: () => _openControlPicker(selectedEvent),
                              onClear: selectedControl == null
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedControlId = null;
                                        _records = const [];
                                        _selectedRecordId = null;
                                        _hasSearched = false;
                                        _errorMessage = null;
                                      });
                                    },
                            ),
                          ],
                        ],
                      ),
                    if (!isEventSource)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppPalette.surfaceSoft,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppPalette.line),
                        ),
                        child: Text(
                          'Se mostraran todos los QR generados por ese CI en el rango de fechas seleccionado.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _MapDateField(
                            label: 'Fecha desde',
                            value: _formatDate(_rangeStart),
                            icon: Icons.calendar_month_rounded,
                            onTap: () => _pickRangeDate(isStart: true),
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: _MapDateField(
                            label: 'Fecha hasta',
                            value: _formatDate(_rangeEnd),
                            icon: Icons.event_available_rounded,
                            onTap: () => _pickRangeDate(isStart: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _loadRecords,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
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
                          onPressed: _isLoading ? null : _clearFilters,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Limpiar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MapMetricChip(
                          icon: Icons.place_outlined,
                          label: metricsPrimaryLabel,
                        ),
                        if (_records.isNotEmpty)
                          _MapMetricChip(
                            icon: Icons.badge_outlined,
                            label: uniqueUsers == 1
                                ? '1 usuario'
                                : '$uniqueUsers usuarios',
                          ),
                        if (latestRecord != null)
                          _MapMetricChip(
                            icon: Icons.schedule_rounded,
                            label: _latestMetricLabel(latestRecord),
                          ),
                        _MapMetricChip(
                          icon: Icons.date_range_rounded,
                          label:
                              '${_formatDate(_rangeStart)} a ${_formatDate(_rangeEnd)}',
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
            Card(
              key: _mapSectionKey,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final title = isEventSource
                            ? 'Puntos de registro'
                            : 'Puntos de QR generados';
                        const helperText =
                            'Toca un punto o un registro de la lista para resaltarlo en rojo';
                        final shouldStackHeader = constraints.maxWidth < 620;

                        if (shouldStackHeader) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (_records.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  helperText,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (_records.isNotEmpty) ...[
                              const SizedBox(width: 16),
                              Flexible(
                                child: Text(
                                  helperText,
                                  textAlign: TextAlign.end,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_records.isEmpty && !_isLoading)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppPalette.surfaceSoft,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppPalette.line),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.map_outlined,
                              size: 36,
                              color: AppPalette.orange,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              emptyStateTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              emptyStateDescription,
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 460,
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: initialCenter,
                              initialZoom: _records.isEmpty ? 12 : 14.4,
                              minZoom: 3,
                              maxZoom: _qrMapMaxZoom,
                              onMapReady: _handleMapReady,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'qr',
                                maxZoom: _qrMapMaxZoom,
                                maxNativeZoom: _qrMapMaxNativeZoom,
                              ),
                              MarkerLayer(
                                markers: [
                                  for (final record in _records)
                                    Marker(
                                      point: LatLng(
                                        record.latitude,
                                        record.longitude,
                                      ),
                                      width: _selectedRecordId == record.id
                                          ? 58
                                          : 52,
                                      height: _selectedRecordId == record.id
                                          ? 58
                                          : 52,
                                      child: GestureDetector(
                                        onTap: () => _selectRecord(
                                          record,
                                          openDetails: true,
                                        ),
                                        child: Icon(
                                          Icons.location_on_rounded,
                                          color: _resolveMarkerColor(record),
                                          size: _selectedRecordId == record.id
                                              ? 46
                                              : 40,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_records.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final record = _records[index];

                          return _QrGenerationRecordCard(
                            record: record,
                            isSelected: _selectedRecordId == record.id,
                            onTap: () => _selectRecord(record, revealMap: true),
                            onOpenDetails: () =>
                                _selectRecord(record, openDetails: true),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _eventSearchLabel(EventRecord event) {
  return '${event.name} | ${_formatEventDateTime(event.date)}';
}

String _formatEventDateTime(DateTime dateTime) {
  return '${_formatEventDate(dateTime)} ${_formatEventTime(dateTime)}';
}

String _formatEventDate(DateTime dateTime) {
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

String _formatEventTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

enum _MapSearchMode { ci, event }

class _QrMapSourceSelector extends StatelessWidget {
  const _QrMapSourceSelector({
    required this.currentSource,
    required this.onChanged,
  });

  final QrGenerationMapSource currentSource;
  final ValueChanged<QrGenerationMapSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _QrMapSourceOption(
              label: 'QR generados',
              isSelected: currentSource == QrGenerationMapSource.qrGenerations,
              onTap: () => onChanged(QrGenerationMapSource.qrGenerations),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QrMapSourceOption(
              label: 'QR escaneados',
              isSelected: currentSource == QrGenerationMapSource.eventScans,
              onTap: () => onChanged(QrGenerationMapSource.eventScans),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrMapSourceOption extends StatelessWidget {
  const _QrMapSourceOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppPalette.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isSelected ? Colors.white : AppPalette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapDateField extends StatelessWidget {
  const _MapDateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.expand_more_rounded),
        ),
        child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class _MapSearchModeSelector extends StatelessWidget {
  const _MapSearchModeSelector({
    required this.currentMode,
    required this.onChanged,
  });

  final _MapSearchMode currentMode;
  final ValueChanged<_MapSearchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MapSearchModeOption(
              label: 'CI',
              isSelected: currentMode == _MapSearchMode.ci,
              onTap: () => onChanged(_MapSearchMode.ci),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MapSearchModeOption(
              label: 'Evento',
              isSelected: currentMode == _MapSearchMode.event,
              onTap: () => onChanged(_MapSearchMode.event),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapSearchModeOption extends StatelessWidget {
  const _MapSearchModeOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppPalette.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isSelected ? Colors.white : AppPalette.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapEventSelectorField extends StatelessWidget {
  const _MapEventSelectorField({
    required this.value,
    required this.isLoading,
    required this.onTap,
    this.onClear,
  });

  final String value;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Evento',
          prefixIcon: const Icon(Icons.event_rounded),
          suffixIcon: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onClear != null)
                      IconButton(
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Limpiar evento',
                      ),
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.expand_more_rounded),
                    ),
                  ],
                ),
        ),
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _MapControlSelectorField extends StatelessWidget {
  const _MapControlSelectorField({
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Control',
          prefixIcon: const Icon(Icons.filter_alt_rounded),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Limpiar control',
                ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.expand_more_rounded),
              ),
            ],
          ),
        ),
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _MapEventPickerSheet extends StatefulWidget {
  const _MapEventPickerSheet({
    required this.events,
    required this.selectedEventId,
  });

  final List<EventRecord> events;
  final int? selectedEventId;

  @override
  State<_MapEventPickerSheet> createState() => _MapEventPickerSheetState();
}

class _MapEventPickerSheetState extends State<_MapEventPickerSheet> {
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
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          event.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _eventSearchLabel(event),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
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

class _MapControlPickerSheet extends StatelessWidget {
  const _MapControlPickerSheet({
    required this.controls,
    required this.selectedControlId,
  });

  final List<EventControl> controls;
  final int? selectedControlId;

  @override
  Widget build(BuildContext context) {
    final sortedControls = [...controls]
      ..sort((left, right) => left.order.compareTo(right.order));

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.6,
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
                  'Seleccionar control',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop<int?>(null),
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selectedControlId == null
                            ? AppPalette.orangeSoft
                            : AppPalette.surfaceSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selectedControlId == null
                              ? AppPalette.orange
                              : AppPalette.line,
                        ),
                      ),
                      child: Text(
                        'Todos los controles',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: sortedControls.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final control = sortedControls[index];
                      final isSelected = control.id == selectedControlId;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              Navigator.of(context).pop<int?>(control.id),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${control.order}. ${control.name}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Filtra solo los registros de este control',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

class _MapMetricChip extends StatelessWidget {
  const _MapMetricChip({required this.icon, required this.label});

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

class _QrGenerationRecordCard extends StatelessWidget {
  const _QrGenerationRecordCard({
    required this.record,
    required this.isSelected,
    required this.onTap,
    required this.onOpenDetails,
  });

  final QrGenerationMapRecord record;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onOpenDetails;

  String _formatDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isEventScan = record.source == QrGenerationMapSource.eventScans;
    final subtitleLabel = isEventScan ? 'Registrado' : 'Generado';
    final statusLabel = switch (record.status) {
      'ASISTIO' => 'Asistio',
      'OBSERVADO' => 'Observado',
      _ => null,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFCEDEC)
                : AppPalette.surfaceSoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFFD94841) : AppPalette.line,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFF8D8D5)
                      : AppPalette.orangeSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: isSelected
                      ? const Color(0xFFD94841)
                      : AppPalette.orange,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.fullName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (isEventScan &&
                        (record.eventName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        record.eventName!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (isEventScan &&
                        (record.controlName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Control: ${record.controlName!}'),
                    ],
                    const SizedBox(height: 4),
                    Text('CI: ${record.ci.isEmpty ? 'Sin CI' : record.ci}'),
                    if (isEventScan && statusLabel != null) ...[
                      const SizedBox(height: 4),
                      Text('Estado: $statusLabel'),
                    ],
                    const SizedBox(height: 4),
                    Text('$subtitleLabel: ${_formatDate(record.generatedAt)}'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onOpenDetails,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Detalle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrGenerationPointSheet extends StatelessWidget {
  const _QrGenerationPointSheet({required this.record});

  final QrGenerationMapRecord record;

  String _formatDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();

    return '$day/$month/$year';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isEventScan = record.source == QrGenerationMapSource.eventScans;
    final statusLabel = switch (record.status) {
      'ASISTIO' => 'Asistio',
      'OBSERVADO' => 'Observado',
      _ => 'Sin estado',
    };
    final title = isEventScan
        ? 'Detalle del punto de escaneo'
        : record.fullName;
    final detailSubtitle = isEventScan
        ? 'Registro realizado en el control del evento'
        : 'Detalle del punto donde genero el QR';
    final controlLabel = (record.controlName ?? '').trim().isEmpty
        ? 'Sin control'
        : record.controlName!;
    final officeLabel = (record.officeName ?? '').trim().isEmpty
        ? 'Sin oficina'
        : record.officeName!;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.64,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detailSubtitle,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PointDetailLine(
                  label: 'CI',
                  value: record.ci.isEmpty ? 'Sin CI' : record.ci,
                ),
                if (isEventScan) ...[
                  const SizedBox(height: 8),
                  _PointDetailLine(label: 'Control', value: controlLabel),
                  const SizedBox(height: 8),
                  _PointDetailLine(label: 'Estado', value: statusLabel),
                ],
                const SizedBox(height: 8),
                _PointDetailLine(
                  label: 'Fecha',
                  value: _formatDate(record.generatedAt),
                ),
                const SizedBox(height: 8),
                _PointDetailLine(
                  label: 'Hora',
                  value: _formatTime(record.generatedAt),
                ),
                if (isEventScan) ...[
                  const SizedBox(height: 8),
                  _PointDetailLine(label: 'Oficina', value: officeLabel),
                ],
                if (!isEventScan) ...[
                  const SizedBox(height: 8),
                  _PointDetailLine(
                    label: 'Ubicacion',
                    value:
                        '${record.latitude.toStringAsFixed(6)}, ${record.longitude.toStringAsFixed(6)}',
                  ),
                  if (record.accuracy != null) ...[
                    const SizedBox(height: 8),
                    _PointDetailLine(
                      label: 'Precision',
                      value: '${record.accuracy!.toStringAsFixed(1)} m',
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PointDetailLine extends StatelessWidget {
  const _PointDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
