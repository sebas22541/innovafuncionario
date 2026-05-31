import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../reports/domain/entities/attendance_report.dart';
import '../../domain/entities/event_record.dart';

enum UserEventsViewMode { attended, available }

class UserEventsScreen extends StatefulWidget {
  const UserEventsScreen({
    super.key,
    required this.currentUser,
    this.viewMode = UserEventsViewMode.attended,
  });

  final AppUser currentUser;
  final UserEventsViewMode viewMode;

  @override
  State<UserEventsScreen> createState() => _UserEventsScreenState();
}

class _UserEventsScreenState extends State<UserEventsScreen> {
  AttendanceReport? _attendedReport;
  List<EventRecord> _availableEvents = const [];
  bool _isLoading = true;
  String? _errorMessage;

  bool get _isAttendedView => widget.viewMode == UserEventsViewMode.attended;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant UserEventsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final userChanged =
        oldWidget.currentUser.id != widget.currentUser.id ||
        oldWidget.currentUser.email != widget.currentUser.email;

    if (userChanged || oldWidget.viewMode != widget.viewMode) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (_isAttendedView) {
      await _loadAttendedEvents();
      return;
    }

    await _loadOfficeEvents();
  }

  Future<void> _loadAttendedEvents() async {
    final ci = widget.currentUser.ci.trim();

    if (ci.length < 3) {
      setState(() {
        _attendedReport = null;
        _availableEvents = const [];
        _isLoading = false;
        _errorMessage =
            'Tu usuario no tiene un CI valido para consultar tus eventos.';
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
        filter: AttendanceReportFilter.attended,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _attendedReport = report;
        _availableEvents = const [];
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _attendedReport = null;
        _availableEvents = const [];
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _attendedReport = null;
        _availableEvents = const [];
        _errorMessage = 'No fue posible cargar tus eventos asistidos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOfficeEvents() async {
    if (!_hasEventReference(widget.currentUser)) {
      setState(() {
        _attendedReport = null;
        _availableEvents = const [];
        _isLoading = false;
        _errorMessage =
            'Tu usuario no tiene oficina ni cargo asociado para consultar eventos.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final events = await dependencies.eventsApiService.fetchEvents();

      if (!mounted) {
        return;
      }

      setState(() {
        _attendedReport = null;
        _availableEvents = _sortOfficeEvents(
          _filterEventsForCurrentUser(events, widget.currentUser),
        );
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _attendedReport = null;
        _availableEvents = const [];
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _attendedReport = null;
        _availableEvents = const [];
        _errorMessage = 'No fue posible cargar los eventos de tu oficina.';
      });
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final records =
        _attendedReport?.records ?? const <AttendanceReportRecord>[];
    final eventCount = _isAttendedView
        ? records.length
        : _availableEvents.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 20.0;
        final availableWidth = constraints.maxWidth - (horizontalPadding * 2);
        final contentWidth = availableWidth >= 980
            ? 760.0
            : availableWidth.clamp(0.0, 760.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            24,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: contentWidth,
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
                            _isAttendedView
                                ? 'Mis eventos asistidos'
                                : 'Eventos',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isAttendedView
                                ? 'Aqui ves todos los eventos en los que tu asistencia ya fue registrada.'
                                : 'Aqui ves todos los eventos asignados a tu oficina o cargo, con sus datos y ubicacion.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _MiniStatCard(
                                label: _isAttendedView
                                    ? 'Asistencias'
                                    : 'Eventos',
                                value: '$eventCount',
                                icon: _isAttendedView
                                    ? Icons.event_available_rounded
                                    : Icons.event_note_rounded,
                                width: 210,
                              ),
                              _MiniStatCard(
                                label: 'Oficina',
                                value: _resolvedOfficeName(widget.currentUser),
                                icon: Icons.apartment_rounded,
                                width: 390,
                              ),
                              if (!_isAttendedView)
                                _MiniStatCard(
                                  label: 'Cargo',
                                  value: widget.currentUser.cargo.trim().isEmpty
                                      ? 'Sin cargo'
                                      : widget.currentUser.cargo,
                                  icon: Icons.badge_rounded,
                                  width: 390,
                                ),
                            ],
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFFD94841)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_isAttendedView)
                    _buildAttendedContent(records)
                  else
                    _buildAvailableContent(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttendedContent(List<AttendanceReportRecord> records) {
    if (records.isEmpty) {
      return const _EmptyUserEventsState(
        icon: Icons.event_busy_rounded,
        title: 'Todavia no tienes asistencias registradas',
        description:
            'Cuando te registren en un evento como asistido, aparecera aqui.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final record in records) ...[
          _UserAttendedEventCard(record: record),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildAvailableContent() {
    if (_availableEvents.isEmpty) {
      return const _EmptyUserEventsState(
        icon: Icons.event_note_rounded,
        title: 'No hay eventos asociados a tu oficina o cargo',
        description:
            'Cuando creen eventos para tu oficina o cargo, apareceran aqui con su informacion y minimapa.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in _availableEvents) ...[
          _UserOfficeEventCard(event: event),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.width = 240,
  });

  final String label;
  final String value;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppPalette.orangeSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppPalette.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAttendedEventCard extends StatelessWidget {
  const _UserAttendedEventCard({required this.record});

  final AttendanceReportRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.eventName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(
                  icon: Icons.calendar_month_rounded,
                  label: _formatDate(record.eventDate),
                ),
                _InfoPill(
                  icon: Icons.schedule_rounded,
                  label: _formatTime(record.eventDate),
                ),
                const _InfoPill(icon: Icons.verified_rounded, label: 'Asistio'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              record.eventAddress?.trim().isNotEmpty == true
                  ? record.eventAddress!
                  : 'Sin direccion registrada.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(
                  icon: Icons.event_available_rounded,
                  label: 'Escaneo ${_formatDate(record.registeredAt)}',
                ),
                _InfoPill(
                  icon: Icons.access_time_rounded,
                  label: 'Hora ${_formatTime(record.registeredAt)}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Registrado: ${_formatDateTime(record.registeredAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserOfficeEventCard extends StatelessWidget {
  const _UserOfficeEventCard({required this.event});

  final EventRecord event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(
                  icon: Icons.calendar_month_rounded,
                  label: _formatDate(event.date),
                ),
                _InfoPill(
                  icon: Icons.schedule_rounded,
                  label: _formatTime(event.date),
                ),
                _InfoPill(
                  icon: Icons.apartment_rounded,
                  label: event.officeCountLabel,
                ),
                _InfoPill(
                  icon: Icons.fact_check_outlined,
                  label: event.controlsLabel,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              event.address?.trim().isNotEmpty == true
                  ? event.address!
                  : 'Sin direccion registrada.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            if (event.hasLocation)
              _EventMiniMap(event: event)
            else
              const _MapPlaceholder(),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EventMiniMap extends StatelessWidget {
  const _EventMiniMap({required this.event});

  final EventRecord event;

  Future<void> _openExpandedMap(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ExpandedEventMapSheet(event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(event.latitude!, event.longitude!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.line),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                options: MapOptions(initialCenter: point, initialZoom: 15),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'qr',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppPalette.orange,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xD154407E),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Minimapa',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: FilledButton.tonalIcon(
                onPressed: () => _openExpandedMap(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xD1FFFFFF),
                  foregroundColor: AppPalette.night,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('Ampliar'),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xD154407E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Ubicacion: ${event.latitude!.toStringAsFixed(6)}, ${event.longitude!.toStringAsFixed(6)}',
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
    );
  }
}

class _ExpandedEventMapSheet extends StatelessWidget {
  const _ExpandedEventMapSheet({required this.event});

  final EventRecord event;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(event.latitude!, event.longitude!);

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
                            event.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mapa interactivo del evento',
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
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 16,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'qr',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 44,
                              height: 44,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: AppPalette.orange,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppPalette.surfaceSoft,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppPalette.line),
                  ),
                  child: Text(
                    'Ubicacion: ${event.latitude!.toStringAsFixed(6)}, ${event.longitude!.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodyMedium,
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

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.line),
      ),
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
              Icons.location_off_rounded,
              color: AppPalette.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sin minimapa disponible',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Este evento no tiene una ubicacion registrada en el mapa.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyUserEventsState extends StatelessWidget {
  const _EmptyUserEventsState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: AppPalette.orange),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

bool _hasEventReference(AppUser currentUser) {
  return _hasOfficeReference(currentUser) ||
      (currentUser.cargoCodigo ?? '').trim().isNotEmpty ||
      currentUser.cargo.trim().isNotEmpty;
}

bool _hasOfficeReference(AppUser currentUser) {
  if (currentUser.hasCommission) {
    return currentUser.commissionOfficeId != null ||
        currentUser.commissionOfficeName?.trim().isNotEmpty == true;
  }

  if (currentUser.officeId != null) {
    return true;
  }

  if ((currentUser.officeCode ?? '').trim().isNotEmpty) {
    return true;
  }

  return currentUser.officeName?.trim().isNotEmpty == true ||
      currentUser.unidad.trim().isNotEmpty;
}

List<EventRecord> _filterEventsForCurrentUser(
  List<EventRecord> events,
  AppUser currentUser,
) {
  final officeId = currentUser.hasCommission
      ? currentUser.commissionOfficeId
      : currentUser.officeId;
  final officeCode = currentUser.hasCommission
      ? ''
      : _normalizeOfficeSearchText(currentUser.officeCode ?? '');
  final officeName = _normalizeOfficeSearchText(
    currentUser.hasCommission
        ? currentUser.commissionOfficeName ?? ''
        : _resolvedOfficeName(currentUser),
  );
  final cargoCodigo = (currentUser.cargoCodigo ?? '').trim().toUpperCase();
  final cargoName = _normalizeOfficeSearchText(currentUser.cargo);

  return events
      .where((event) {
        final selectedJobTitleCodes = event.selectedJobTitleCodes
            .map((code) => code.trim().toUpperCase())
            .where((code) => code.isNotEmpty)
            .toSet();
        final matchesSelectedJobTitleCode =
            cargoCodigo.isNotEmpty &&
            selectedJobTitleCodes.contains(cargoCodigo);
        final matchesJobTitle =
            matchesSelectedJobTitleCode ||
            event.jobTitles.any((jobTitle) {
              final eventJobTitleCode = jobTitle.code.trim().toUpperCase();

              if (cargoCodigo.isNotEmpty && eventJobTitleCode == cargoCodigo) {
                return true;
              }

              if (cargoName.isEmpty) {
                return false;
              }

              final eventJobTitleName = _normalizeOfficeSearchText(
                jobTitle.name,
              );

              return eventJobTitleName == cargoName ||
                  eventJobTitleName.contains(cargoName) ||
                  cargoName.contains(eventJobTitleName);
            });

        if (matchesJobTitle) {
          return true;
        }

        final matchingOffice = event.offices.cast<EventOffice?>().firstWhere((
          office,
        ) {
          if (office == null) {
            return false;
          }

          if (officeId != null && office.id == officeId) {
            return true;
          }

          return _eventOfficeMatchesUserOffice(
            office,
            userOfficeName: officeName,
            userOfficeCode: officeCode,
          );
        }, orElse: () => null);
        final hasOfficeJobTitleRules =
            event.officeJobTitleSelections.isNotEmpty;

        if (hasOfficeJobTitleRules) {
          if (matchingOffice == null) {
            return false;
          }

          final officeSelection = event.officeJobTitleSelections
              .cast<EventOfficeJobTitleSelection?>()
              .firstWhere(
                (selection) => selection?.officeId == matchingOffice.id,
                orElse: () => null,
              );

          if (officeSelection == null || officeSelection.allowsAllJobTitles) {
            return true;
          }

          return officeSelection.jobTitleCodes.any(
            (code) =>
                cargoCodigo.isNotEmpty &&
                code.trim().toUpperCase() == cargoCodigo,
          );
        }

        if (officeId != null && event.selectedOfficeIds.contains(officeId)) {
          return true;
        }

        return event.offices.any((office) {
          if (officeId != null && office.id == officeId) {
            return true;
          }

          final eventOfficeCode = _normalizeOfficeSearchText(office.code);

          if (officeCode.isNotEmpty && eventOfficeCode.isNotEmpty) {
            if (eventOfficeCode == officeCode ||
                eventOfficeCode.startsWith('$officeCode.') ||
                officeCode.startsWith('$eventOfficeCode.')) {
              return true;
            }
          }

          if (_eventOfficeMatchesUserOffice(
            office,
            userOfficeName: officeName,
            userOfficeCode: officeCode,
          )) {
            return true;
          }

          return false;
        });
      })
      .toList(growable: false);
}

bool _eventOfficeMatchesUserOffice(
  EventOffice eventOffice, {
  required String userOfficeName,
  required String userOfficeCode,
}) {
  final eventOfficeName = _normalizeOfficeSearchText(eventOffice.name);
  final eventOfficeCode = _normalizeOfficeSearchText(eventOffice.code);

  if (userOfficeCode.isNotEmpty &&
      eventOfficeCode.isNotEmpty &&
      (eventOfficeCode == userOfficeCode ||
          eventOfficeCode.startsWith('$userOfficeCode.') ||
          userOfficeCode.startsWith('$eventOfficeCode.'))) {
    return true;
  }

  if (userOfficeName.isEmpty || eventOfficeName.isEmpty) {
    return false;
  }

  if (eventOfficeName == userOfficeName ||
      eventOfficeName.contains(userOfficeName) ||
      userOfficeName.contains(eventOfficeName)) {
    return true;
  }

  final userTokens = _officeSearchTokens(userOfficeName);
  final eventTokens = _officeSearchTokens(eventOfficeName);

  if (userTokens.isEmpty || eventTokens.isEmpty) {
    return false;
  }

  final shorterTokens = userTokens.length <= eventTokens.length
      ? userTokens
      : eventTokens;
  final longerTokens = userTokens.length <= eventTokens.length
      ? eventTokens
      : userTokens;
  final matches = shorterTokens
      .where((token) => longerTokens.any((longerToken) => longerToken == token))
      .length;
  final requiredMatches = shorterTokens.length <= 2 ? shorterTokens.length : 2;

  return matches >= requiredMatches;
}

List<EventRecord> _sortOfficeEvents(List<EventRecord> events) {
  final sortedEvents = [...events];
  final now = DateTime.now();

  sortedEvents.sort((left, right) {
    final leftIsPast = left.date.isBefore(now);
    final rightIsPast = right.date.isBefore(now);

    if (leftIsPast != rightIsPast) {
      return leftIsPast ? 1 : -1;
    }

    final dateComparison = left.date.compareTo(right.date);

    if (dateComparison != 0) {
      return dateComparison;
    }

    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });

  return sortedEvents;
}

String _normalizeOfficeSearchText(String value) {
  return _stripTextAccents(value.trim().toLowerCase())
      .replaceAll(RegExp(r'\bcomision\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9.]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripTextAccents(String value) {
  return value
      .replaceAll(RegExp(r'[áàäâã]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöôõ]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll('ñ', 'n');
}

Set<String> _officeSearchTokens(String value) {
  const ignoredTokens = {
    'oficina',
    'unidad',
    'direccion',
    'direcciones',
    'departamento',
    'secretaria',
    'municipal',
    'gobierno',
    'autonomo',
    'de',
    'del',
    'la',
    'las',
    'los',
    'el',
    'y',
  };

  return value
      .split(' ')
      .where(
        (token) =>
            token.isNotEmpty &&
            !ignoredTokens.contains(token) &&
            (token.length >= 3 || RegExp(r'\d').hasMatch(token)),
      )
      .toSet();
}

String _resolvedOfficeName(AppUser currentUser) {
  final officeName = currentUser.officeName?.trim();

  if (officeName != null && officeName.isNotEmpty) {
    return officeName;
  }

  final unidad = currentUser.unidad.trim();
  return unidad.isNotEmpty ? unidad : 'Sin oficina';
}

String _formatDate(DateTime date) {
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

  return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '$hour:$minute';
}

String _formatDateTime(DateTime date) {
  return '${_formatDate(date)} ${_formatTime(date)}';
}
