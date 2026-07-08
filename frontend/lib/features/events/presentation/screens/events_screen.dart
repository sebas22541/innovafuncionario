import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/location_permission_settings.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../domain/entities/event_record.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.currentUser,
    required this.onOpenScanner,
  });

  final AppUser currentUser;
  final ValueChanged<EventRecord> onOpenScanner;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

enum _EventsPage { overview, detail, lists }

enum _EventCardAction { edit, delete }

class _EventsScreenState extends State<EventsScreen> {
  _EventsPage _page = _EventsPage.overview;
  EventRecord? _selectedEvent;
  EventListType _selectedListType = EventListType.attended;
  final TextEditingController _eventSearchController = TextEditingController();
  List<EventRecord> _events = const [];
  List<EventOffice> _offices = const [];
  List<EventJobTitle> _jobTitles = const [];
  bool _isLoading = true;
  bool _isReloading = false;
  bool _isLoadingSelectedEvent = false;
  bool _isCreating = false;
  bool _isUpdating = false;
  bool _isDeleting = false;
  String _eventSearchQuery = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialData();
      }
    });
  }

  Future<void> _loadInitialData({bool showRefreshState = false}) async {
    if (!mounted) {
      return;
    }

    setState(() {
      if (showRefreshState) {
        _isReloading = true;
      } else {
        _isLoading = true;
      }
      _errorMessage = null;
    });

    try {
      final events = await dependencies.eventsApiService.fetchEvents(
        forceRefresh: showRefreshState,
      );
      final selectedEventId = _selectedEvent?.id;
      EventRecord? refreshedSelectedEvent;

      if (selectedEventId != null) {
        for (final event in events) {
          if (event.id == selectedEventId) {
            refreshedSelectedEvent = event;
            break;
          }
        }
      }

      setState(() {
        _events = events;
        _selectedEvent = refreshedSelectedEvent;
        if (_selectedEvent == null && _page != _EventsPage.overview) {
          _page = _EventsPage.overview;
        }
      });
    } on BackendApiException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'No fue posible cargar los eventos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isReloading = false;
        });
      }
    }
  }

  Future<void> _showCreateEventDialog() async {
    if (!widget.currentUser.canManageEvents) {
      return;
    }

    final referencesLoaded = await _ensureEventReferencesLoaded();

    if (!mounted) {
      return;
    }

    if (!referencesLoaded) {
      AppAlert.showWarning(
        context,
        'No hay oficinas disponibles en la base de datos.',
      );
      return;
    }

    final draft = await showDialog<EventRecordDraft>(
      context: context,
      builder: (context) =>
          _CreateEventDialog(offices: _offices, jobTitles: _jobTitles),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final createdEvent = await dependencies.eventsApiService.createEvent(
        draft: draft,
        creatorEmail: widget.currentUser.email,
        creatorFullName: widget.currentUser.fullName,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _events = _upsertEvent(_events, createdEvent);
        _selectedEvent = createdEvent;
        _page = _EventsPage.detail;
      });

      AppAlert.showSuccess(context, 'Evento "${createdEvent.name}" guardado.');
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible guardar el evento.');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _showEditEventDialog(EventRecord event) async {
    if (!widget.currentUser.canManageEvents) {
      return;
    }

    final referencesLoaded = await _ensureEventReferencesLoaded();

    if (!mounted) {
      return;
    }

    if (!referencesLoaded) {
      AppAlert.showWarning(
        context,
        'No hay oficinas disponibles en la base de datos.',
      );
      return;
    }

    final detailedEvent = event.hasDetailedAttendanceData
        ? event
        : await _fetchEventDetailForEditing(event.id);

    if (detailedEvent == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final draft = await showDialog<EventRecordDraft>(
      context: context,
      builder: (context) => _CreateEventDialog(
        offices: _offices,
        jobTitles: _jobTitles,
        initialEvent: detailedEvent,
      ),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final updatedEvent = await dependencies.eventsApiService.updateEvent(
        eventId: event.id,
        draft: draft,
        requesterEmail: widget.currentUser.email,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _events = _upsertEvent(_events, updatedEvent);
        if (_selectedEvent?.id == updatedEvent.id) {
          _selectedEvent = updatedEvent;
        }
      });

      AppAlert.showSuccess(
        context,
        'Evento "${updatedEvent.name}" actualizado.',
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

      AppAlert.showError(context, 'No fue posible actualizar el evento.');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<bool> _ensureEventReferencesLoaded() async {
    if (_offices.isNotEmpty) {
      return true;
    }

    setState(() {
      _isReloading = true;
    });

    try {
      final results = await Future.wait([
        dependencies.eventsApiService.fetchOffices(),
        dependencies.eventsApiService.fetchJobTitles(),
      ]);

      if (!mounted) {
        return false;
      }

      final offices = results[0] as List<EventOffice>;
      final jobTitles = results[1] as List<EventJobTitle>;

      setState(() {
        _offices = offices;
        _jobTitles = jobTitles;
      });

      return offices.isNotEmpty;
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar oficinas y cargos.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReloading = false;
        });
      }
    }

    return false;
  }

  Future<void> _deleteEvent(EventRecord event) async {
    if (!widget.currentUser.canManageEvents) {
      return;
    }

    final shouldDelete = await AppAlert.confirm(
      context,
      title: 'Borrar evento',
      message:
          'Se eliminara "${event.name}" junto con sus listas registradas. Esta accion no se puede deshacer.',
      confirmLabel: 'Borrar',
      cancelLabel: 'Cancelar',
      type: AppAlertType.error,
    );

    if (!shouldDelete) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      await dependencies.eventsApiService.deleteEvent(
        eventId: event.id,
        requesterEmail: widget.currentUser.email,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _events = _events.where((item) => item.id != event.id).toList();
        if (_selectedEvent?.id == event.id) {
          _selectedEvent = null;
          _page = _EventsPage.overview;
        }
      });

      AppAlert.showSuccess(context, 'Evento "${event.name}" eliminado.');
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible borrar el evento.');
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  void _openEvent(EventRecord event) {
    setState(() {
      _selectedEvent = event;
      _page = _EventsPage.detail;
    });

    if (!event.hasDetailedAttendanceData) {
      _loadSelectedEventDetail(event.id);
    }
  }

  Future<EventRecord?> _fetchEventDetailForEditing(int eventId) async {
    setState(() {
      _isLoadingSelectedEvent = true;
    });

    try {
      final detailedEvent = await dependencies.eventsApiService.fetchEventById(
        eventId,
      );

      if (mounted) {
        setState(() {
          _events = _upsertEvent(_events, detailedEvent);
          if (_selectedEvent?.id == detailedEvent.id) {
            _selectedEvent = detailedEvent;
          }
        });
      }

      return detailedEvent;
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar el evento.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSelectedEvent = false;
        });
      }
    }

    return null;
  }

  Future<void> _openLists(EventRecord event) async {
    setState(() {
      _selectedEvent = event;
      _selectedListType = EventListType.attended;
      _page = _EventsPage.lists;
    });

    if (!event.hasDetailedAttendanceData) {
      await _loadSelectedEventDetail(event.id);
    }
  }

  Future<void> _loadSelectedEventDetail(int eventId) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingSelectedEvent = true;
    });

    try {
      final detailedEvent = await dependencies.eventsApiService.fetchEventById(
        eventId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedEvent = detailedEvent;
        _events = _upsertEvent(_events, detailedEvent);
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(
        context,
        'No fue posible cargar el detalle completo del evento.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSelectedEvent = false;
        });
      }
    }
  }

  Future<void> _showEventOffices(EventRecord event) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ExpandedEventOfficeSheet(
        offices: event.offices,
        directOfficeIds: event.selectedOfficeIds.toSet(),
      ),
    );
  }

  void _goBack() {
    if (_page == _EventsPage.lists) {
      setState(() {
        _page = _EventsPage.detail;
      });
      return;
    }

    setState(() {
      _selectedEvent = null;
      _page = _EventsPage.overview;
    });
  }

  List<EventRecord> _upsertEvent(List<EventRecord> events, EventRecord event) {
    final nextEvents = [
      event,
      ...events.where((existingEvent) => existingEvent.id != event.id),
    ];

    nextEvents.sort((left, right) {
      final dateComparison = right.date.compareTo(left.date);

      if (dateComparison != 0) {
        return dateComparison;
      }

      return right.id.compareTo(left.id);
    });

    return nextEvents;
  }

  List<EventRecord> get _filteredEvents {
    final normalizedQuery = _normalizeOfficeSearchText(_eventSearchQuery);

    if (normalizedQuery.isEmpty) {
      return _events;
    }

    return _events
        .where((event) {
          final searchValues = [
            event.name,
            event.address ?? '',
            event.createdBy,
            event.officeNames,
            event.jobTitles.map((jobTitle) => jobTitle.name).join(', '),
            _formatDate(event.date),
            _formatDateTime(event.date),
          ];

          return searchValues.any(
            (value) => _officeTextLooksSimilar(
              _normalizeOfficeSearchText(value),
              normalizedQuery,
            ),
          );
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    _eventSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _EventsLoadingState();
    }

    if (_errorMessage != null && _events.isEmpty) {
      return _EventsErrorState(
        message: _errorMessage!,
        onRetry: _loadInitialData,
      );
    }

    switch (_page) {
      case _EventsPage.overview:
        return _EventsOverview(
          events: _filteredEvents,
          totalEvents: _events.length,
          canManageEvents: widget.currentUser.canManageEvents,
          isCreating: _isCreating,
          isUpdating: _isUpdating,
          isDeleting: _isDeleting,
          isRefreshing: _isReloading,
          searchController: _eventSearchController,
          searchQuery: _eventSearchQuery,
          errorMessage: _errorMessage,
          onCreateEvent: _showCreateEventDialog,
          onOpenEvent: _openEvent,
          onEditEvent: _showEditEventDialog,
          onDeleteEvent: _deleteEvent,
          onSearchChanged: (value) {
            setState(() {
              _eventSearchQuery = value;
            });
          },
          onRefresh: () => _loadInitialData(showRefreshState: true),
        );
      case _EventsPage.detail:
        final event = _selectedEvent;
        if (event == null) {
          return _EventsOverview(
            events: _filteredEvents,
            totalEvents: _events.length,
            canManageEvents: widget.currentUser.canManageEvents,
            isCreating: _isCreating,
            isUpdating: _isUpdating,
            isDeleting: _isDeleting,
            isRefreshing: _isReloading,
            searchController: _eventSearchController,
            searchQuery: _eventSearchQuery,
            errorMessage: _errorMessage,
            onCreateEvent: _showCreateEventDialog,
            onOpenEvent: _openEvent,
            onEditEvent: _showEditEventDialog,
            onDeleteEvent: _deleteEvent,
            onSearchChanged: (value) {
              setState(() {
                _eventSearchQuery = value;
              });
            },
            onRefresh: () => _loadInitialData(showRefreshState: true),
          );
        }
        return _EventDetailView(
          event: event,
          canManageEvents: widget.currentUser.canManageEvents,
          canOpenScanner: widget.currentUser.canUseEventScanner,
          onBack: _goBack,
          onEdit: () => _showEditEventDialog(event),
          onDelete: () => _deleteEvent(event),
          onOpenLists: () => _openLists(event),
          onViewOffices: () => _showEventOffices(event),
          onOpenScanner: () => widget.onOpenScanner(event),
        );
      case _EventsPage.lists:
        final event = _selectedEvent;
        if (event == null) {
          return _EventsOverview(
            events: _filteredEvents,
            totalEvents: _events.length,
            canManageEvents: widget.currentUser.canManageEvents,
            isCreating: _isCreating,
            isUpdating: _isUpdating,
            isDeleting: _isDeleting,
            isRefreshing: _isReloading,
            searchController: _eventSearchController,
            searchQuery: _eventSearchQuery,
            errorMessage: _errorMessage,
            onCreateEvent: _showCreateEventDialog,
            onOpenEvent: _openEvent,
            onEditEvent: _showEditEventDialog,
            onDeleteEvent: _deleteEvent,
            onSearchChanged: (value) {
              setState(() {
                _eventSearchQuery = value;
              });
            },
            onRefresh: () => _loadInitialData(showRefreshState: true),
          );
        }
        return _EventListsView(
          event: event,
          selectedListType: _selectedListType,
          isLoadingEventDetails: _isLoadingSelectedEvent,
          canOpenScanner: widget.currentUser.canUseEventScanner,
          onBack: _goBack,
          onListTypeChanged: (type) {
            setState(() {
              _selectedListType = type;
            });
          },
          onOpenScanner: () => widget.onOpenScanner(event),
        );
    }
  }
}

class _EventsOverview extends StatelessWidget {
  const _EventsOverview({
    required this.events,
    required this.totalEvents,
    required this.canManageEvents,
    required this.isCreating,
    required this.isUpdating,
    required this.isDeleting,
    required this.isRefreshing,
    required this.searchController,
    required this.searchQuery,
    required this.errorMessage,
    required this.onCreateEvent,
    required this.onOpenEvent,
    required this.onEditEvent,
    required this.onDeleteEvent,
    required this.onSearchChanged,
    required this.onRefresh,
  });

  final List<EventRecord> events;
  final int totalEvents;
  final bool canManageEvents;
  final bool isCreating;
  final bool isUpdating;
  final bool isDeleting;
  final bool isRefreshing;
  final TextEditingController searchController;
  final String searchQuery;
  final String? errorMessage;
  final VoidCallback onCreateEvent;
  final ValueChanged<EventRecord> onOpenEvent;
  final ValueChanged<EventRecord> onEditEvent;
  final ValueChanged<EventRecord> onDeleteEvent;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasSearch = searchQuery.trim().isNotEmpty;

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
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AppPalette.orangeSoft,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.event_note_rounded,
                          color: AppPalette.orange,
                        ),
                      ),
                      const Spacer(),
                      if (isRefreshing)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      else
                        IconButton(
                          tooltip: 'Recargar',
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Gestion de eventos', style: textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Cada evento se crea y se lee desde la base de datos. Antes de guardarlo debes indicar a que oficinas pertenece, su direccion y el punto exacto en el mapa.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  if (canManageEvents)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: isCreating ? null : onCreateEvent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 0,
                          ),
                          icon: isCreating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add_circle_outline_rounded),
                          label: Text(
                            isCreating ? 'Guardando...' : 'Crear evento',
                          ),
                        ),
                      ],
                    ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      style: textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD94841),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      labelText: 'Buscar evento',
                      hintText: 'Nombre, direccion, oficina o creador',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: hasSearch
                          ? IconButton(
                              tooltip: 'Limpiar busqueda',
                              onPressed: () {
                                searchController.clear();
                                onSearchChanged('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Todos los eventos', style: textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? '${events.length} de $totalEvents eventos coinciden con la busqueda.'
                : '$totalEvents eventos registrados.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            _EmptyEventsState(
              title: hasSearch
                  ? 'No se encontraron eventos'
                  : 'Todavia no hay eventos guardados',
              message: hasSearch
                  ? 'Prueba con otro nombre, direccion, oficina o creador.'
                  : 'Crea tu primer evento y quedara persistido en la base de datos junto con sus oficinas.',
              icon: hasSearch
                  ? Icons.search_off_rounded
                  : Icons.event_busy_rounded,
            )
          else
            Column(
              children: [
                for (final event in events) ...[
                  _EventListCard(
                    event: event,
                    canManageEvents: canManageEvents,
                    isBusy: isUpdating || isDeleting,
                    onTap: () => onOpenEvent(event),
                    onEdit: () => onEditEvent(event),
                    onDelete: () => onDeleteEvent(event),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _EventDetailView extends StatelessWidget {
  const _EventDetailView({
    required this.event,
    required this.canManageEvents,
    required this.canOpenScanner,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenLists,
    required this.onViewOffices,
    required this.onOpenScanner,
  });

  final EventRecord event;
  final bool canManageEvents;
  final bool canOpenScanner;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onOpenLists;
  final VoidCallback onViewOffices;
  final VoidCallback onOpenScanner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Volver a eventos'),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          event.name,
                          style: textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (canManageEvents)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SmallEventActionButton(
                              label: 'Editar',
                              icon: Icons.edit_outlined,
                              onTap: onEdit,
                            ),
                            _SmallEventActionButton(
                              label: 'Borrar',
                              icon: Icons.delete_outline_rounded,
                              foregroundColor: const Color(0xFFD94841),
                              onTap: onDelete,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fecha: ${_formatDate(event.date)}',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hora de inicio: ${_formatTime(event.date)}',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.address?.trim().isNotEmpty == true
                        ? 'Direccion: ${event.address!}'
                        : 'Sin direccion registrada.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InfoChip(
                        icon: Icons.apartment_rounded,
                        label: event.officeLabel,
                        onTap: onViewOffices,
                      ),
                      _InfoChip(
                        icon: Icons.fact_check_outlined,
                        label: event.controlsLabel,
                      ),
                      _InfoChip(
                        icon: Icons.groups_rounded,
                        label: '${event.totalTrackedPeople} personas listadas',
                      ),
                      _InfoChip(
                        icon: Icons.person_outline_rounded,
                        label: 'Creado por ${event.createdBy}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Opciones del evento', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final cardWidth = isWide
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _ActionOptionCard(
                      title: 'Listas',
                      description:
                          'Lee directamente desde base de datos quienes asistieron y quienes quedaron observados.',
                      icon: Icons.list_alt_rounded,
                      buttonLabel: 'Abrir listas',
                      onTap: onOpenLists,
                    ),
                  ),
                  if (canOpenScanner)
                    SizedBox(
                      width: cardWidth,
                      child: _ActionOptionCard(
                        title: 'Escanear QR',
                        description:
                            'Abre el lector QR y registra el resultado sobre este evento en la base de datos.',
                        icon: Icons.qr_code_scanner_rounded,
                        buttonLabel: 'Ir al escaner',
                        accentColor: AppPalette.night,
                        onTap: onOpenScanner,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SmallEventActionButton extends StatelessWidget {
  const _SmallEventActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.foregroundColor = AppPalette.orange,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        side: BorderSide(color: foregroundColor.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _EventListsView extends StatelessWidget {
  const _EventListsView({
    required this.event,
    required this.selectedListType,
    required this.isLoadingEventDetails,
    required this.canOpenScanner,
    required this.onBack,
    required this.onListTypeChanged,
    required this.onOpenScanner,
  });

  final EventRecord event;
  final EventListType selectedListType;
  final bool isLoadingEventDetails;
  final bool canOpenScanner;
  final VoidCallback onBack;
  final ValueChanged<EventListType> onListTypeChanged;
  final VoidCallback onOpenScanner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentList = selectedListType == EventListType.attended
        ? event.attended
        : event.observed;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Volver al evento'),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Listas de ${event.name}',
                    style: textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Oficinas asociadas: ${event.officeCountLabel}',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cargos asociados: ${event.jobTitleCountLabel}',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Controles configurados: ${event.controlsLabel}',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecciona una de las dos opciones para revisar los registros almacenados en la base de datos.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cada QR que escanees dentro de este evento te mostrara todos los controles configurados para registrar si la persona asistio u observo en cada uno.',
                    style: textTheme.bodySmall,
                  ),
                  if (event.controls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final control in event.controls)
                          _InfoChip(
                            icon: Icons.fact_check_outlined,
                            label: control.name,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _ListOptionButton(
                        label: 'Asistieron',
                        isSelected: selectedListType == EventListType.attended,
                        icon: Icons.how_to_reg_rounded,
                        onTap: () => onListTypeChanged(EventListType.attended),
                      ),
                      _ListOptionButton(
                        label: 'Observados',
                        isSelected: selectedListType == EventListType.observed,
                        icon: Icons.visibility_outlined,
                        onTap: () => onListTypeChanged(EventListType.observed),
                      ),
                      if (canOpenScanner)
                        OutlinedButton.icon(
                          onPressed: onOpenScanner,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Escanear QR'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (isLoadingEventDetails && !event.hasDetailedAttendanceData)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Cargando listas completas del evento desde la base de datos...',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              selectedListType == EventListType.attended
                  ? 'Personas que asistieron'
                  : 'Personas observadas',
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (currentList.isEmpty)
              _EmptyListState(selectedListType: selectedListType)
            else
              _EventRosterTable(
                eventControls: event.controls,
                entries: currentList,
                selectedListType: selectedListType,
              ),
          ],
        ],
      ),
    );
  }
}

class _CreateEventDialog extends StatefulWidget {
  const _CreateEventDialog({
    required this.offices,
    required this.jobTitles,
    this.initialEvent,
  });

  final List<EventOffice> offices;
  final List<EventJobTitle> jobTitles;
  final EventRecord? initialEvent;

  @override
  State<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _EditableEventControl {
  _EditableEventControl({
    required this.controller,
    required this.startTime,
    required this.endTime,
    this.id,
  });

  final int? id;
  final TextEditingController controller;
  TimeOfDay startTime;
  TimeOfDay endTime;
}

class _EventOfficeSelectionResult {
  const _EventOfficeSelectionResult({
    required this.selectedOfficeIds,
    required this.excludedOfficeIds,
  });

  final List<int> selectedOfficeIds;
  final List<int> excludedOfficeIds;
}

class _EventJobTitleSelectionResult {
  const _EventJobTitleSelectionResult({required this.selectedJobTitleCodes});

  final List<String> selectedJobTitleCodes;
}

class _CreateEventDialogState extends State<_CreateEventDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final List<_EditableEventControl> _controls;
  final MapController _mapController = MapController();
  final ScrollController _dialogScrollController = ScrollController();
  final ScrollController _selectedOfficesScrollController = ScrollController();
  late DateTime _selectedDate;
  late TimeOfDay _selectedStartTime;
  LatLng? _selectedLocation;
  LatLng? _pendingMapLocation;
  bool _isMapReady = false;
  bool _isResolvingCurrentLocation = false;
  String? _locationErrorMessage;
  late final Set<int> _selectedOfficeIds;
  late final Set<int> _excludedOfficeIds;
  late final Set<String> _selectedJobTitleCodes;
  late final Map<int, Set<String>> _officeJobTitleCodes;
  bool _showValidation = false;

  Set<int> get _expandedOfficeIds => _expandOfficeSelection(
    _selectedOfficeIds,
    widget.offices,
    excludedOfficeIds: _excludedOfficeIds,
  );

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialEvent?.name ?? '',
    );
    _addressController = TextEditingController(
      text: widget.initialEvent?.address ?? '',
    );
    final initialDate = widget.initialEvent?.date ?? DateTime.now();
    _selectedDate = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );
    _selectedStartTime = TimeOfDay(
      hour: initialDate.hour,
      minute: initialDate.minute,
    );

    if (widget.initialEvent?.hasLocation == true) {
      _selectedLocation = LatLng(
        widget.initialEvent!.latitude!,
        widget.initialEvent!.longitude!,
      );
    }

    _selectedOfficeIds = {
      ...widget.initialEvent?.selectedOfficeIds ?? const [],
    };
    _excludedOfficeIds = {
      ...widget.initialEvent?.excludedOfficeIds ?? const [],
    };
    final normalizedExcludedOfficeIds = _normalizeExcludedOfficeSelection(
      _selectedOfficeIds,
      _excludedOfficeIds,
      widget.offices,
    );
    _excludedOfficeIds
      ..clear()
      ..addAll(normalizedExcludedOfficeIds);
    _selectedJobTitleCodes = {
      ...widget.initialEvent?.selectedJobTitleCodes ?? const [],
    };
    _officeJobTitleCodes = {
      for (final selection
          in widget.initialEvent?.officeJobTitleSelections ?? const [])
        selection.officeId: selection.jobTitleCodes.toSet(),
    };
    final initialControls = widget.initialEvent?.controls ?? const [];
    final defaultControlEndTime = _addMinutesToTime(_selectedStartTime, 15);
    _controls = initialControls.isEmpty
        ? [
            _EditableEventControl(
              controller: TextEditingController(text: 'Primer control'),
              startTime: _selectedStartTime,
              endTime: defaultControlEndTime,
            ),
          ]
        : initialControls
              .map((control) {
                final controlStartTime = _parseTimeOfDay(
                  control.startTime,
                  _selectedStartTime,
                );

                return _EditableEventControl(
                  id: control.id,
                  controller: TextEditingController(text: control.name),
                  startTime: controlStartTime,
                  endTime: _parseTimeOfDay(
                    control.endTime,
                    _addMinutesToTime(controlStartTime, 15),
                  ),
                );
              })
              .toList(growable: true);

    if (widget.initialEvent == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _useCurrentLocation(autoRequested: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    for (final control in _controls) {
      control.controller.dispose();
    }
    _dialogScrollController.dispose();
    _selectedOfficesScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
      );
    });
  }

  Future<void> _pickStartTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedStartTime,
    );

    if (pickedTime == null) {
      return;
    }

    setState(() {
      _selectedStartTime = pickedTime;
    });
  }

  Future<void> _pickOffices() async {
    final selectionResult =
        await showModalBottomSheet<_EventOfficeSelectionResult>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _EventOfficeSelectionSheet(
            offices: widget.offices,
            selectedOfficeIds: _selectedOfficeIds,
            excludedOfficeIds: _excludedOfficeIds,
          ),
        );

    if (!mounted || selectionResult == null) {
      return;
    }

    setState(() {
      _selectedOfficeIds
        ..clear()
        ..addAll(selectionResult.selectedOfficeIds);
      _excludedOfficeIds
        ..clear()
        ..addAll(selectionResult.excludedOfficeIds);
      _syncOfficeJobTitleSelections();
    });
  }

  Future<void> _showExpandedOfficesPreview() async {
    final expandedOffices = widget.offices
        .where((office) => _expandedOfficeIds.contains(office.id))
        .toList(growable: false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ExpandedEventOfficeSheet(
        offices: expandedOffices,
        directOfficeIds: _selectedOfficeIds,
      ),
    );
  }

  void _syncOfficeJobTitleSelections() {
    final expandedOfficeIds = _expandedOfficeIds;

    _officeJobTitleCodes.removeWhere(
      (officeId, _) => !expandedOfficeIds.contains(officeId),
    );
  }

  Future<void> _pickGlobalJobTitles() async {
    final selectionResult =
        await showModalBottomSheet<_EventJobTitleSelectionResult>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _EventJobTitleSelectionSheet(
            jobTitles: widget.jobTitles,
            selectedJobTitleCodes: _selectedJobTitleCodes,
            title: 'Cargos globales del evento',
            allowAllJobTitles: false,
            helperText:
                'Selecciona los cargos que asistiran sin importar la unidad.',
          ),
        );

    if (!mounted || selectionResult == null) {
      return;
    }

    setState(() {
      _selectedJobTitleCodes
        ..clear()
        ..addAll(selectionResult.selectedJobTitleCodes);
    });
  }

  Future<void> _pickOfficeJobTitles(EventOffice office) async {
    final selectedCodes = _officeJobTitleCodes[office.id] ?? const <String>{};
    final selectionResult =
        await showModalBottomSheet<_EventJobTitleSelectionResult>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _EventJobTitleSelectionSheet(
            jobTitles: widget.jobTitles,
            selectedJobTitleCodes: selectedCodes,
            title: 'Cargos para ${office.name}',
          ),
        );

    if (!mounted || selectionResult == null) {
      return;
    }

    setState(() {
      _officeJobTitleCodes[office.id] = {
        ...selectionResult.selectedJobTitleCodes,
      };
    });
  }

  void _removeSelectedOffice(int officeId) {
    setState(() {
      _selectedOfficeIds.remove(officeId);
      final normalizedExcludedOfficeIds = _normalizeExcludedOfficeSelection(
        _selectedOfficeIds,
        _excludedOfficeIds,
        widget.offices,
      );
      _excludedOfficeIds
        ..clear()
        ..addAll(normalizedExcludedOfficeIds);
      _syncOfficeJobTitleSelections();
    });
  }

  void _removeExcludedOffice(int officeId) {
    setState(() {
      _excludedOfficeIds.remove(officeId);
    });
  }

  void _addControl() {
    final suggestedStartTime = _controls.isEmpty
        ? _selectedStartTime
        : _controls.last.endTime;

    setState(() {
      _controls.add(
        _EditableEventControl(
          controller: TextEditingController(
            text: 'Control ${_controls.length + 1}',
          ),
          startTime: suggestedStartTime,
          endTime: _addMinutesToTime(suggestedStartTime, 15),
        ),
      );
    });
  }

  Future<void> _pickControlTime(int index, {required bool isStartTime}) async {
    final control = _controls[index];
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: isStartTime ? control.startTime : control.endTime,
    );

    if (pickedTime == null || !mounted) {
      return;
    }

    setState(() {
      if (isStartTime) {
        control.startTime = pickedTime;
      } else {
        control.endTime = pickedTime;
      }
    });
  }

  void _removeControlAt(int index) {
    if (_controls.length <= 1) {
      return;
    }

    final removedControl = _controls.removeAt(index);
    removedControl.controller.dispose();
    setState(() {});
  }

  void _submit() {
    final trimmedName = _nameController.text.trim();
    final trimmedAddress = _addressController.text.trim();
    final controls = _controls
        .map(
          (control) => EventControlDraft(
            id: control.id,
            name: control.controller.text.trim(),
            startTime: _formatTimeOfDay(control.startTime),
            endTime: _formatTimeOfDay(control.endTime),
          ),
        )
        .toList(growable: false);
    final scheduledDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedStartTime.hour,
      _selectedStartTime.minute,
    );
    final hasAudienceSelection =
        _selectedOfficeIds.isNotEmpty || _selectedJobTitleCodes.isNotEmpty;

    if (trimmedName.isEmpty ||
        trimmedAddress.isEmpty ||
        !hasAudienceSelection ||
        controls.any((control) => control.name.isEmpty) ||
        _controls.any(
          (control) =>
              _timeOfDayToMinutes(control.endTime) <=
              _timeOfDayToMinutes(control.startTime),
        ) ||
        _selectedLocation == null) {
      setState(() {
        _showValidation = true;
      });
      return;
    }

    Navigator.of(context).pop(
      EventRecordDraft(
        name: trimmedName,
        date: scheduledDateTime,
        address: trimmedAddress,
        latitude: _selectedLocation!.latitude,
        longitude: _selectedLocation!.longitude,
        officeIds: _selectedOfficeIds.toList(growable: false),
        finalOfficeIds: _expandedOfficeIds.toList(growable: false),
        jobTitleCodes: _selectedJobTitleCodes.toList(growable: false),
        officeJobTitleSelections: _expandedOfficeIds
            .map(
              (officeId) => EventOfficeJobTitleSelection(
                officeId: officeId,
                jobTitleCodes: (_officeJobTitleCodes[officeId] ?? const {})
                    .toList(growable: false),
              ),
            )
            .toList(growable: false),
        excludedOfficeIds: _excludedOfficeIds.toList(growable: false),
        controls: controls,
      ),
    );
  }

  Future<void> _useCurrentLocation({bool autoRequested = false}) async {
    if (_isResolvingCurrentLocation) {
      return;
    }

    setState(() {
      _isResolvingCurrentLocation = true;
      if (!autoRequested) {
        _locationErrorMessage = null;
      }
    });

    try {
      final isLocationEnabled = await LocationPermissionSettings.isEnabled();

      if (!isLocationEnabled) {
        throw StateError(
          'Habilita la ubicacion en Configuracion para usar tu ubicacion actual.',
        );
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw StateError(
          'Activa tu ubicacion para centrar el mapa del evento.',
        );
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'No se concedio el permiso de ubicacion. Habilitalo y vuelve a intentarlo.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final currentLocation = LatLng(position.latitude, position.longitude);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedLocation = currentLocation;
        _locationErrorMessage = null;
      });

      _moveMapTo(currentLocation, zoom: 16);
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _locationErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _locationErrorMessage = 'No fue posible obtener tu ubicacion actual.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingCurrentLocation = false;
        });
      }
    }
  }

  void _moveMapTo(LatLng point, {double zoom = 16}) {
    if (_isMapReady) {
      _mapController.move(point, zoom);
      return;
    }

    _pendingMapLocation = point;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialEvent != null;
    final expandedOfficeIds = _expandedOfficeIds;
    final viewportSize = MediaQuery.sizeOf(context);
    final rawDialogWidth = viewportSize.width > 652
        ? 620.0
        : viewportSize.width - 32;
    final dialogWidth = rawDialogWidth <= 320
        ? rawDialogWidth
        : rawDialogWidth.clamp(320.0, 620.0).toDouble();
    final rawDialogHeight = viewportSize.height - 32;
    final dialogHeight = rawDialogHeight <= 420
        ? rawDialogHeight
        : rawDialogHeight.clamp(420.0, 760.0).toDouble();
    final mapHeight = viewportSize.height < 820 ? 220.0 : 250.0;
    final shouldStackOfficeSummary = dialogWidth < 520;
    final directlySelectedOffices = widget.offices
        .where((office) => _selectedOfficeIds.contains(office.id))
        .toList(growable: false);
    final excludedBranchOffices = widget.offices
        .where((office) => _excludedOfficeIds.contains(office.id))
        .toList(growable: false);
    final expandedOffices = widget.offices
        .where((office) => expandedOfficeIds.contains(office.id))
        .toList(growable: false);
    final globalSelectedJobTitles = widget.jobTitles
        .where((jobTitle) => _selectedJobTitleCodes.contains(jobTitle.code))
        .toList(growable: false);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Editar evento' : 'Crear evento',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppPalette.line),
            Expanded(
              child: Scrollbar(
                controller: _dialogScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _dialogScrollController,
                  padding: const EdgeInsets.fromLTRB(24, 18, 22, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nombre del evento',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'Escribe el nombre del evento',
                          errorText:
                              _showValidation &&
                                  _nameController.text.trim().isEmpty
                              ? 'Ingresa un nombre'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Oficinas',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Selecciona una o mas oficinas base. Si marcas una oficina padre, el sistema incluira automaticamente toda su rama segun el codigo, pero podras deseleccionar subramas que no iran al evento.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                _showValidation &&
                                    _selectedOfficeIds.isEmpty &&
                                    _selectedJobTitleCodes.isEmpty
                                ? const Color(0xFFD94841)
                                : AppPalette.line,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (shouldStackOfficeSummary) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_selectedOfficeIds.length} oficinas base seleccionadas',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${expandedOfficeIds.length} oficinas finales quedaran asociadas al evento.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if (excludedBranchOffices.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${excludedBranchOffices.length} ramas quedaran fuera aunque pertenezcan a una oficina padre seleccionada.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _pickOffices,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppPalette.orange,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.apartment_rounded),
                                    label: Text(
                                      directlySelectedOffices.isEmpty
                                          ? 'Seleccionar'
                                          : 'Cambiar',
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_selectedOfficeIds.length} oficinas base seleccionadas',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${expandedOfficeIds.length} oficinas finales quedaran asociadas al evento.',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        if (excludedBranchOffices
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            '${excludedBranchOffices.length} ramas quedaran fuera aunque pertenezcan a una oficina padre seleccionada.',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    onPressed: _pickOffices,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppPalette.orange,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.apartment_rounded),
                                    label: Text(
                                      directlySelectedOffices.isEmpty
                                          ? 'Seleccionar'
                                          : 'Cambiar',
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 12),
                            if (directlySelectedOffices.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppPalette.surfaceSoft,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppPalette.line),
                                ),
                                child: Text(
                                  'Todavia no seleccionaste oficinas base.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            else ...[
                              Text(
                                'Oficinas base elegidas',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 170,
                                ),
                                child: Scrollbar(
                                  controller: _selectedOfficesScrollController,
                                  thumbVisibility:
                                      directlySelectedOffices.length > 2,
                                  child: ListView.separated(
                                    controller:
                                        _selectedOfficesScrollController,
                                    shrinkWrap: true,
                                    itemCount: directlySelectedOffices.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final office =
                                          directlySelectedOffices[index];
                                      final branchOffices =
                                          _collectOfficeBranchOffices(
                                                office,
                                                widget.offices,
                                              )
                                              .where(
                                                (branchOffice) =>
                                                    expandedOfficeIds.contains(
                                                      branchOffice.id,
                                                    ),
                                              )
                                              .toList(growable: false);
                                      final descendantsCount =
                                          branchOffices.length;

                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: AppPalette.surfaceSoft,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: AppPalette.line,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.apartment_rounded,
                                              color: AppPalette.orange,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    office.name,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.titleSmall,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Cod. ${office.code} | Nivel ${office.level}',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                  if (descendantsCount > 0) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Se agregaran automaticamente $descendantsCount oficinas hijas de su rama.',
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Column(
                                                      children: [
                                                        for (final branchOffice
                                                            in branchOffices)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  bottom: 4,
                                                                ),
                                                            child: Row(
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .account_tree_rounded,
                                                                  size: 16,
                                                                  color:
                                                                      AppPalette
                                                                          .muted,
                                                                ),
                                                                const SizedBox(
                                                                  width: 6,
                                                                ),
                                                                Expanded(
                                                                  child: Text(
                                                                    branchOffice
                                                                        .displayLabel,
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: Theme.of(
                                                                      context,
                                                                    ).textTheme.bodySmall,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () =>
                                                  _removeSelectedOffice(
                                                    office.id,
                                                  ),
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                color: AppPalette.muted,
                                              ),
                                              tooltip: 'Quitar oficina',
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                            if (excludedBranchOffices.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Ramas deseleccionadas',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final office in excludedBranchOffices)
                                    InputChip(
                                      label: Text(office.displayLabel),
                                      onDeleted: () =>
                                          _removeExcludedOffice(office.id),
                                      deleteIconColor: const Color(0xFFD94841),
                                      backgroundColor: const Color(0xFFFFF1F0),
                                      side: const BorderSide(
                                        color: Color(0xFFF2B8B5),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (expandedOffices.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _showExpandedOfficesPreview,
                                  icon: const Icon(Icons.visibility_outlined),
                                  label: Text(
                                    excludedBranchOffices.isNotEmpty
                                        ? 'Ver oficinas finales del evento'
                                        : expandedOffices.length ==
                                              directlySelectedOffices.length
                                        ? 'Ver oficinas seleccionadas'
                                        : 'Ver todas las oficinas que se asociaran',
                                  ),
                                ),
                              ),
                            ],
                            if (_showValidation &&
                                _selectedOfficeIds.isEmpty &&
                                _selectedJobTitleCodes.isEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Selecciona al menos una oficina base o un cargo global.',
                                style: TextStyle(
                                  color: Color(0xFFD94841),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Cargos por oficina',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Define que cargos podran asistir en cada oficina. Si dejas una oficina en Todos, no se filtrara por cargo para esa oficina.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppPalette.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (expandedOffices.isEmpty)
                              Text(
                                'Primero selecciona una oficina.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              )
                            else
                              for (final office in expandedOffices) ...[
                                Builder(
                                  builder: (context) {
                                    final selectedCodes =
                                        _officeJobTitleCodes[office.id] ??
                                        const <String>{};
                                    final selectedTitles = widget.jobTitles
                                        .where(
                                          (jobTitle) => selectedCodes.contains(
                                            jobTitle.code,
                                          ),
                                        )
                                        .toList(growable: false);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppPalette.surfaceSoft,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppPalette.line,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.apartment_rounded,
                                            color: AppPalette.orange,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  office.name,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleSmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  selectedTitles.isEmpty
                                                      ? 'Todos los cargos'
                                                      : '${selectedTitles.length} cargos: ${selectedTitles.map((item) => item.name).join(', ')}',
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _pickOfficeJobTitles(office),
                                            icon: const Icon(
                                              Icons.badge_rounded,
                                            ),
                                            label: const Text('Cargos'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Cargos globales del evento',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Selecciona cargos globales. Todas las personas con esos cargos podran asistir, sin importar su oficina o unidad.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                _showValidation &&
                                    _selectedOfficeIds.isEmpty &&
                                    _selectedJobTitleCodes.isEmpty
                                ? const Color(0xFFD94841)
                                : AppPalette.line,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        globalSelectedJobTitles.length == 1
                                            ? '1 cargo seleccionado'
                                            : '${globalSelectedJobTitles.length} cargos seleccionados',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        globalSelectedJobTitles.isEmpty
                                            ? 'Todavia no seleccionaste cargos.'
                                            : 'Aplicara sin importar la oficina.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _pickGlobalJobTitles,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppPalette.orange,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.badge_rounded),
                                  label: Text(
                                    globalSelectedJobTitles.isEmpty
                                        ? 'Seleccionar'
                                        : 'Cambiar',
                                  ),
                                ),
                              ],
                            ),
                            if (globalSelectedJobTitles.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final jobTitle
                                      in globalSelectedJobTitles)
                                    Chip(
                                      label: Text(jobTitle.name),
                                      avatar: const Icon(
                                        Icons.badge_rounded,
                                        size: 18,
                                        color: AppPalette.orange,
                                      ),
                                      backgroundColor: AppPalette.orangeSoft,
                                      side: const BorderSide(
                                        color: AppPalette.line,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (_showValidation &&
                                _selectedOfficeIds.isEmpty &&
                                _selectedJobTitleCodes.isEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Selecciona al menos una oficina o un cargo global.',
                                style: TextStyle(
                                  color: Color(0xFFD94841),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Controles del evento',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agrega los controles y define el rango horario en el que se permitira registrar asistencia para cada uno.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                _showValidation &&
                                    _controls.any(
                                      (control) =>
                                          control.controller.text
                                              .trim()
                                              .isEmpty ||
                                          _timeOfDayToMinutes(
                                                control.endTime,
                                              ) <=
                                              _timeOfDayToMinutes(
                                                control.startTime,
                                              ),
                                    )
                                ? const Color(0xFFD94841)
                                : AppPalette.line,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var index = 0;
                              index < _controls.length;
                              index++
                            ) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppPalette.surfaceSoft,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppPalette.line),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Control ${index + 1}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                        ),
                                        if (_controls.length > 1)
                                          IconButton(
                                            onPressed: () =>
                                                _removeControlAt(index),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Color(0xFFD94841),
                                            ),
                                            tooltip: 'Quitar control',
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _controls[index].controller,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Nombre del control, por ejemplo: Primer control',
                                        errorText:
                                            _showValidation &&
                                                _controls[index].controller.text
                                                    .trim()
                                                    .isEmpty
                                            ? 'Ingresa el nombre del control'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _pickControlTime(
                                              index,
                                              isStartTime: true,
                                            ),
                                            icon: const Icon(
                                              Icons.schedule_rounded,
                                            ),
                                            label: Text(
                                              'Desde ${_formatTimeOfDay(_controls[index].startTime)}',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _pickControlTime(
                                              index,
                                              isStartTime: false,
                                            ),
                                            icon: const Icon(
                                              Icons.schedule_rounded,
                                            ),
                                            label: Text(
                                              'Hasta ${_formatTimeOfDay(_controls[index].endTime)}',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_showValidation &&
                                        _timeOfDayToMinutes(
                                              _controls[index].endTime,
                                            ) <=
                                            _timeOfDayToMinutes(
                                              _controls[index].startTime,
                                            )) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'La hora final debe ser posterior a la hora inicial.',
                                        style: TextStyle(
                                          color: Color(0xFFD94841),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (index != _controls.length - 1)
                                const SizedBox(height: 10),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _addControl,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Agregar control'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Direccion',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText:
                              'Ingresa la direccion donde sera el evento.',
                          errorText:
                              _showValidation &&
                                  _addressController.text.trim().isEmpty
                              ? 'Ingresa la direccion del evento'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Punto del evento',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Toca el mapa para marcar el punto exacto donde sera el evento.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _isResolvingCurrentLocation
                              ? null
                              : () => _useCurrentLocation(),
                          icon: _isResolvingCurrentLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location_rounded),
                          label: Text(
                            _isResolvingCurrentLocation
                                ? 'Ubicando...'
                                : 'Usar mi ubicacion',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          height: mapHeight,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color:
                                  _showValidation && _selectedLocation == null
                                  ? const Color(0xFFD94841)
                                  : AppPalette.line,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter:
                                  _selectedLocation ?? _defaultEventLocation,
                              initialZoom: 13,
                              onMapReady: () {
                                _isMapReady = true;

                                final pendingLocation = _pendingMapLocation;

                                if (pendingLocation != null) {
                                  _mapController.move(pendingLocation, 16);
                                  _pendingMapLocation = null;
                                }
                              },
                              onTap: (_, point) {
                                setState(() {
                                  _selectedLocation = point;
                                });
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'qr',
                              ),
                              if (_selectedLocation != null)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _selectedLocation!,
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
                      if (_selectedLocation != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Punto seleccionado: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else if (_locationErrorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _locationErrorMessage!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFFD94841)),
                        ),
                      ] else if (_showValidation) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Debes seleccionar un punto en el mapa.',
                          style: TextStyle(
                            color: Color(0xFFD94841),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        'Fecha programada',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _pickDate,
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppPalette.line),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month_rounded,
                                color: AppPalette.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_formatDate(_selectedDate))),
                              const Icon(Icons.expand_more_rounded),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Hora de inicio',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _pickStartTime,
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppPalette.line),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                color: AppPalette.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _formatTimeOfDay(_selectedStartTime),
                                ),
                              ),
                              const Icon(Icons.expand_more_rounded),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppPalette.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: Text(isEditing ? 'Guardar cambios' : 'Guardar'),
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

class _EventOfficeSelectionSheet extends StatefulWidget {
  const _EventOfficeSelectionSheet({
    required this.offices,
    required this.selectedOfficeIds,
    required this.excludedOfficeIds,
  });

  final List<EventOffice> offices;
  final Set<int> selectedOfficeIds;
  final Set<int> excludedOfficeIds;

  @override
  State<_EventOfficeSelectionSheet> createState() =>
      _EventOfficeSelectionSheetState();
}

class _EventOfficeSelectionSheetState
    extends State<_EventOfficeSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();
  late final Set<int> _draftSelectedOfficeIds;
  late final Set<int> _draftExcludedOfficeIds;
  String _searchQuery = '';

  Set<int> get _rawExpandedOfficeIds =>
      _expandOfficeSelection(_draftSelectedOfficeIds, widget.offices);

  Set<int> get _expandedOfficeIds => _expandOfficeSelection(
    _draftSelectedOfficeIds,
    widget.offices,
    excludedOfficeIds: _draftExcludedOfficeIds,
  );

  List<EventOffice> get _filteredOffices {
    final normalizedQuery = _normalizeOfficeSearchText(_searchQuery);

    if (normalizedQuery.isEmpty) {
      return widget.offices;
    }

    return widget.offices
        .where((office) {
          return _officeTextLooksSimilar(
                _normalizeOfficeSearchText(office.name),
                normalizedQuery,
              ) ||
              _normalizeOfficeSearchText(
                office.code,
              ).contains(normalizedQuery) ||
              office.level.toString().contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _draftSelectedOfficeIds = _normalizeDirectOfficeSelection({
      ...widget.selectedOfficeIds,
    }, widget.offices);
    _draftExcludedOfficeIds = _normalizeExcludedOfficeSelection(
      _draftSelectedOfficeIds,
      {...widget.excludedOfficeIds},
      widget.offices,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _syncDraftOfficeSelection(Set<int> nextSelectedOfficeIds) {
    final normalizedSelection = _normalizeDirectOfficeSelection(
      nextSelectedOfficeIds,
      widget.offices,
    );
    final normalizedExclusions = _normalizeExcludedOfficeSelection(
      normalizedSelection,
      _draftExcludedOfficeIds,
      widget.offices,
    );

    _draftSelectedOfficeIds
      ..clear()
      ..addAll(normalizedSelection);
    _draftExcludedOfficeIds
      ..clear()
      ..addAll(normalizedExclusions);
  }

  void _toggleOffice(int officeId) {
    setState(() {
      final office = widget.offices.firstWhere((item) => item.id == officeId);

      if (_draftSelectedOfficeIds.contains(officeId)) {
        final nextSelectedOfficeIds = {..._draftSelectedOfficeIds}
          ..remove(officeId);
        _syncDraftOfficeSelection(nextSelectedOfficeIds);
        return;
      }

      if (_draftExcludedOfficeIds.contains(officeId)) {
        _draftExcludedOfficeIds.remove(officeId);
        final normalizedExclusions = _normalizeExcludedOfficeSelection(
          _draftSelectedOfficeIds,
          _draftExcludedOfficeIds,
          widget.offices,
        );
        _draftExcludedOfficeIds
          ..clear()
          ..addAll(normalizedExclusions);
        return;
      }

      if (_isOfficeCoveredByAnotherSelectedBranch(
        office,
        _draftSelectedOfficeIds,
        widget.offices,
      )) {
        _draftExcludedOfficeIds.add(officeId);
        final normalizedExclusions = _normalizeExcludedOfficeSelection(
          _draftSelectedOfficeIds,
          _draftExcludedOfficeIds,
          widget.offices,
        );
        _draftExcludedOfficeIds
          ..clear()
          ..addAll(normalizedExclusions);
        return;
      }

      final nextSelectedOfficeIds = {..._draftSelectedOfficeIds, officeId};
      _syncDraftOfficeSelection(nextSelectedOfficeIds);
    });
  }

  void _applySelection() {
    final normalizedSelection = _normalizeDirectOfficeSelection(
      _draftSelectedOfficeIds,
      widget.offices,
    );
    final normalizedExclusions = _normalizeExcludedOfficeSelection(
      normalizedSelection,
      _draftExcludedOfficeIds,
      widget.offices,
    );

    Navigator.of(context).pop(
      _EventOfficeSelectionResult(
        selectedOfficeIds: normalizedSelection.toList(growable: false),
        excludedOfficeIds: normalizedExclusions.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final filteredOffices = _filteredOffices;
    final visibleOfficeEntries = _buildOfficeSelectionEntries(
      filteredOffices,
      widget.offices,
    );
    final rawExpandedOfficeIds = _rawExpandedOfficeIds;
    final expandedOfficeIds = _expandedOfficeIds;
    final selectedBaseOfficeCount = _draftSelectedOfficeIds.length;
    final excludedBranchCount = _draftExcludedOfficeIds.length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 20, 12, 12 + bottomInset),
        child: Material(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(30),
          child: FractionallySizedBox(
            heightFactor: 0.94,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selecciona oficinas',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Elige las oficinas base del evento. Si una oficina tiene ramas hijas, se agregaran automaticamente, pero puedes deseleccionar subramas especificas que no iran al evento.',
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Buscar oficina',
                      hintText: 'Escribe nombre, codigo o nivel',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
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
                          '$selectedBaseOfficeCount oficinas base elegidas',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${expandedOfficeIds.length} oficinas finales quedaran asociadas al evento.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (excludedBranchCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '$excludedBranchCount ramas quedaran fuera del evento.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Usa la lista inferior para marcar oficinas base o deseleccionar ramas; aqui solo se muestra el resumen.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    filteredOffices.length == 1
                        ? '1 resultado'
                        : '${filteredOffices.length} resultados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredOffices.isEmpty
                        ? Center(
                            child: Text(
                              'No hay oficinas que coincidan con la busqueda.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Scrollbar(
                            controller: _resultsScrollController,
                            thumbVisibility: true,
                            child: ListView.separated(
                              controller: _resultsScrollController,
                              itemCount: visibleOfficeEntries.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final entry = visibleOfficeEntries[index];
                                final office = entry.office;
                                final parentOffice = entry.parentOffice;
                                final isBranchEntry = parentOffice != null;
                                final isDirectlySelected =
                                    _draftSelectedOfficeIds.contains(office.id);
                                final isDirectlyExcluded =
                                    _draftExcludedOfficeIds.contains(office.id);
                                final isIncludedBySelection =
                                    rawExpandedOfficeIds.contains(office.id);
                                final isIncludedByHierarchy = expandedOfficeIds
                                    .contains(office.id);
                                final isInheritedOnly =
                                    isIncludedByHierarchy &&
                                    !isDirectlySelected;
                                final isExcludedByHierarchy =
                                    isIncludedBySelection &&
                                    !isIncludedByHierarchy;
                                final isExcludedByParent =
                                    isExcludedByHierarchy &&
                                    !isDirectlyExcluded;
                                final branchOffices =
                                    _collectOfficeBranchOffices(
                                      office,
                                      widget.offices,
                                    );
                                final descendantsCount = branchOffices.length;
                                final cardColor = isDirectlySelected
                                    ? AppPalette.orangeSoft
                                    : isDirectlyExcluded
                                    ? const Color(0xFFFFF1F0)
                                    : isInheritedOnly
                                    ? const Color(0xFFF3F9F1)
                                    : isExcludedByParent
                                    ? const Color(0xFFFFF8F7)
                                    : Colors.white;
                                final borderColor = isDirectlySelected
                                    ? AppPalette.orange
                                    : isDirectlyExcluded
                                    ? const Color(0xFFD94841)
                                    : isInheritedOnly
                                    ? const Color(0xFF2E7D32)
                                    : isExcludedByParent
                                    ? AppPalette.muted
                                    : AppPalette.line;
                                final leadingIcon = isDirectlySelected
                                    ? Icons.check_circle_rounded
                                    : isDirectlyExcluded
                                    ? Icons.remove_circle_rounded
                                    : isInheritedOnly
                                    ? Icons.check_circle_outline_rounded
                                    : isExcludedByParent
                                    ? Icons.block_rounded
                                    : Icons.radio_button_unchecked_rounded;
                                final leadingColor = isDirectlySelected
                                    ? AppPalette.orange
                                    : isDirectlyExcluded
                                    ? const Color(0xFFD94841)
                                    : isInheritedOnly
                                    ? const Color(0xFF2E7D32)
                                    : isExcludedByParent
                                    ? const Color(0xFFD94841)
                                    : AppPalette.muted;

                                return Padding(
                                  padding: EdgeInsets.only(
                                    left: isBranchEntry ? 28 : 0,
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => _toggleOffice(office.id),
                                    child: Ink(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: cardColor,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Icon(
                                              leadingIcon,
                                              color: leadingColor,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  office.name,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleSmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Cod. ${office.code} | Nivel ${office.level}',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                if (isBranchEntry) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Rama de ${parentOffice.name}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color:
                                                              AppPalette.muted,
                                                        ),
                                                  ),
                                                ],
                                                if (isDirectlyExcluded) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    descendantsCount > 0
                                                        ? 'Esta rama no ira al evento. Se excluiran automaticamente $descendantsCount oficinas hijas.'
                                                        : 'Esta oficina no ira al evento aunque su oficina padre este seleccionada.',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: const Color(
                                                            0xFFD94841,
                                                          ),
                                                        ),
                                                  ),
                                                ] else if (isInheritedOnly) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Ira al evento porque esta dentro de una oficina padre seleccionada. Toca solo si quieres que esta rama no vaya.',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color:
                                                              AppPalette.night,
                                                        ),
                                                  ),
                                                ] else if (isExcludedByParent) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Esta oficina ya quedo fuera por una rama padre. Si quieres dejarla excluida por separado, tocala tambien.',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: const Color(
                                                            0xFFD94841,
                                                          ),
                                                        ),
                                                  ),
                                                ] else if (descendantsCount >
                                                    0) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Si la marcas, se agregan automaticamente $descendantsCount oficinas hijas de su rama.',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ],
                                            ),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _applySelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: const Text('Aplicar seleccion'),
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

class _EventJobTitleSelectionSheet extends StatefulWidget {
  const _EventJobTitleSelectionSheet({
    required this.jobTitles,
    required this.selectedJobTitleCodes,
    this.title = 'Selecciona cargos',
    this.allowAllJobTitles = true,
    this.helperText,
  });

  final List<EventJobTitle> jobTitles;
  final Set<String> selectedJobTitleCodes;
  final String title;
  final bool allowAllJobTitles;
  final String? helperText;

  @override
  State<_EventJobTitleSelectionSheet> createState() =>
      _EventJobTitleSelectionSheetState();
}

class _EventJobTitleSelectionSheetState
    extends State<_EventJobTitleSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();
  late final Set<String> _draftSelectedJobTitleCodes;
  String _searchQuery = '';

  List<EventJobTitle> get _filteredJobTitles {
    final normalizedQuery = _normalizeOfficeSearchText(_searchQuery);

    if (normalizedQuery.isEmpty) {
      return widget.jobTitles;
    }

    return widget.jobTitles
        .where((jobTitle) {
          return _normalizeOfficeSearchText(
                jobTitle.name,
              ).contains(normalizedQuery) ||
              _normalizeOfficeSearchText(
                jobTitle.code,
              ).contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _draftSelectedJobTitleCodes = {...widget.selectedJobTitleCodes};
  }

  @override
  void dispose() {
    _searchController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _toggleJobTitle(String code) {
    setState(() {
      if (_draftSelectedJobTitleCodes.contains(code)) {
        _draftSelectedJobTitleCodes.remove(code);
      } else {
        _draftSelectedJobTitleCodes.add(code);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _draftSelectedJobTitleCodes.clear();
    });
  }

  void _applySelection() {
    Navigator.of(context).pop(
      _EventJobTitleSelectionResult(
        selectedJobTitleCodes: _draftSelectedJobTitleCodes.toList(
          growable: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final filteredJobTitles = _filteredJobTitles;
    final allSelected =
        widget.allowAllJobTitles && _draftSelectedJobTitleCodes.isEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 20, 12, 12 + bottomInset),
        child: Material(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(30),
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.helperText ??
                                  (widget.allowAllJobTitles
                                      ? 'Puedes buscar por nombre o codigo. Usa Todos cuando no quieras filtrar por cargo.'
                                      : 'Selecciona uno o mas cargos.'),
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Buscar cargo',
                      hintText: 'Escribe cargo o codigo',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.allowAllJobTitles) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _selectAll,
                      child: Ink(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: allSelected
                              ? AppPalette.orangeSoft
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: allSelected
                                ? AppPalette.orange
                                : AppPalette.line,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              allSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: allSelected
                                  ? AppPalette.orange
                                  : AppPalette.muted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Todos los cargos',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    filteredJobTitles.length == 1
                        ? '1 resultado'
                        : '${filteredJobTitles.length} resultados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredJobTitles.isEmpty
                        ? Center(
                            child: Text(
                              'No hay cargos que coincidan con la busqueda.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Scrollbar(
                            controller: _resultsScrollController,
                            thumbVisibility: true,
                            child: ListView.separated(
                              controller: _resultsScrollController,
                              itemCount: filteredJobTitles.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final jobTitle = filteredJobTitles[index];
                                final isSelected = _draftSelectedJobTitleCodes
                                    .contains(jobTitle.code);

                                return InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => _toggleJobTitle(jobTitle.code),
                                  child: Ink(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppPalette.orangeSoft
                                          : Colors.white,
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
                                        Icon(
                                          isSelected
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          color: isSelected
                                              ? AppPalette.orange
                                              : AppPalette.muted,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                jobTitle.name,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Codigo ${jobTitle.code}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _applySelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: const Text('Aplicar seleccion'),
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

class _ExpandedEventOfficeSheet extends StatelessWidget {
  const _ExpandedEventOfficeSheet({
    required this.offices,
    required this.directOfficeIds,
  });

  final List<EventOffice> offices;
  final Set<int> directOfficeIds;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        child: Material(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(30),
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Oficinas asociadas al evento',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Aqui ves tanto las oficinas base que elegiste como las que se agregaran automaticamente por sus ramas.',
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
                  const SizedBox(height: 16),
                  Text(
                    offices.length == 1
                        ? '1 oficina asociada'
                        : '${offices.length} oficinas asociadas',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: offices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final office = offices[index];
                        final isDirectSelection = directOfficeIds.contains(
                          office.id,
                        );

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDirectSelection
                                ? AppPalette.orangeSoft
                                : AppPalette.surfaceSoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDirectSelection
                                  ? AppPalette.orange
                                  : AppPalette.line,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isDirectSelection
                                    ? Icons.check_circle_rounded
                                    : Icons.account_tree_rounded,
                                color: isDirectSelection
                                    ? AppPalette.orange
                                    : AppPalette.night,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      office.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Cod. ${office.code} | Nivel ${office.level}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isDirectSelection
                                          ? 'Seleccionada directamente por ti.'
                                          : 'Agregada automaticamente por la jerarquia del codigo.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: isDirectSelection
                                                ? AppPalette.orange
                                                : AppPalette.night,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
      ),
    );
  }
}

class _EventListCard extends StatelessWidget {
  const _EventListCard({
    required this.event,
    required this.canManageEvents,
    required this.isBusy,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final EventRecord event;
  final bool canManageEvents;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: isBusy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppPalette.orangeSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.event_rounded,
                      color: AppPalette.orange,
                    ),
                  ),
                  const SizedBox(width: 14),
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
                          _formatDateTime(event.date),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (canManageEvents)
                    PopupMenuButton<_EventCardAction>(
                      enabled: !isBusy,
                      tooltip: 'Acciones del evento',
                      onSelected: (value) {
                        switch (value) {
                          case _EventCardAction.edit:
                            onEdit();
                            return;
                          case _EventCardAction.delete:
                            onDelete();
                            return;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<_EventCardAction>(
                          value: _EventCardAction.edit,
                          child: Text('Editar'),
                        ),
                        PopupMenuItem<_EventCardAction>(
                          value: _EventCardAction.delete,
                          child: Text('Borrar'),
                        ),
                      ],
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: AppPalette.muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                event.address?.trim().isNotEmpty == true
                    ? 'Direccion: ${event.address!}'
                    : 'Sin direccion registrada.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(
                    icon: Icons.apartment_rounded,
                    label: event.officeCountLabel,
                  ),
                  _InfoChip(
                    icon: Icons.badge_rounded,
                    label: event.jobTitleCountLabel,
                  ),
                  _InfoChip(
                    icon: Icons.fact_check_outlined,
                    label: event.controlsLabel,
                  ),
                  _InfoChip(
                    icon: Icons.how_to_reg_rounded,
                    label: '${event.resolvedAttendedCount} asistieron',
                  ),
                  _InfoChip(
                    icon: Icons.visibility_outlined,
                    label: '${event.resolvedObservedCount} observaron',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionOptionCard extends StatelessWidget {
  const _ActionOptionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.buttonLabel,
    required this.onTap,
    this.accentColor = AppPalette.orange,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: accentColor),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListOptionButton extends StatelessWidget {
  const _ListOptionButton({
    required this.label,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppPalette.orangeSoft : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? AppPalette.orange : AppPalette.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppPalette.orange : AppPalette.muted,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppPalette.orange : AppPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const int _eventRosterPageSize = 30;

class _EventRosterTable extends StatefulWidget {
  const _EventRosterTable({
    required this.eventControls,
    required this.entries,
    required this.selectedListType,
  });

  final List<EventControl> eventControls;
  final List<EventRosterEntry> entries;
  final EventListType selectedListType;

  @override
  State<_EventRosterTable> createState() => _EventRosterTableState();
}

class _EventRosterTableState extends State<_EventRosterTable> {
  int _currentPage = 0;

  int get _pageCount {
    if (widget.entries.isEmpty) {
      return 1;
    }

    return ((widget.entries.length - 1) ~/ _eventRosterPageSize) + 1;
  }

  @override
  void didUpdateWidget(covariant _EventRosterTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.selectedListType != widget.selectedListType) {
      _currentPage = 0;
      return;
    }

    final maxPage = _pageCount - 1;
    if (_currentPage > maxPage) {
      _currentPage = maxPage;
    }
  }

  void _goToPage(int page) {
    final maxPage = _pageCount - 1;
    final nextPage = page.clamp(0, maxPage).toInt();

    if (nextPage == _currentPage) {
      return;
    }

    setState(() {
      _currentPage = nextPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.selectedListType == EventListType.attended
        ? AppPalette.orange
        : AppPalette.night;
    final statusLabel = widget.selectedListType == EventListType.attended
        ? 'Asistio'
        : 'Observado';
    final totalControls = widget.eventControls.length;
    final pageStart = _currentPage * _eventRosterPageSize;
    final rawPageEnd = pageStart + _eventRosterPageSize;
    final pageEnd = rawPageEnd > widget.entries.length
        ? widget.entries.length
        : rawPageEnd;
    final pageEntries = widget.entries.sublist(pageStart, pageEnd);
    final hasMultiplePages = widget.entries.length > _eventRosterPageSize;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.selectedListType == EventListType.attended
                        ? Icons.how_to_reg_rounded
                        : Icons.visibility_outlined,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.selectedListType == EventListType.attended
                        ? 'Tabla de asistencia'
                        : 'Tabla de observados',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final compactTable = availableWidth < 960;
                final horizontalMargin = compactTable ? 10.0 : 14.0;
                final columnSpacing = compactTable ? 12.0 : 18.0;
                final minTableWidth = compactTable ? 760.0 : availableWidth;
                final tableWidth = availableWidth < minTableWidth
                    ? minTableWidth
                    : availableWidth;
                final contentWidth =
                    tableWidth - (horizontalMargin * 2) - (columnSpacing * 4);
                final nameWidth = (contentWidth * 0.25)
                    .clamp(150.0, 210.0)
                    .toDouble();
                final officeWidth = (contentWidth * 0.30)
                    .clamp(170.0, 250.0)
                    .toDouble();
                final controlsWidth = (contentWidth * 0.11)
                    .clamp(80.0, 96.0)
                    .toDouble();
                final scannedAtWidth = (contentWidth * 0.16)
                    .clamp(110.0, 138.0)
                    .toDouble();
                final statusWidth =
                    (contentWidth -
                            nameWidth -
                            officeWidth -
                            controlsWidth -
                            scannedAtWidth)
                        .clamp(92.0, 132.0)
                        .toDouble();

                return ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        horizontalMargin: horizontalMargin,
                        columnSpacing: columnSpacing,
                        headingRowHeight: 60,
                        dataRowMinHeight: 72,
                        dataRowMaxHeight: 112,
                        headingRowColor: WidgetStatePropertyAll(
                          accentColor.withValues(alpha: 0.08),
                        ),
                        columns: [
                          DataColumn(
                            label: _buildTableLabel(
                              'Nombre completo',
                              width: nameWidth,
                            ),
                          ),
                          DataColumn(
                            label: _buildTableLabel(
                              'Oficina',
                              width: officeWidth,
                            ),
                          ),
                          DataColumn(
                            label: _buildTableLabel(
                              'Controles',
                              width: controlsWidth,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          DataColumn(
                            label: _buildTableLabel(
                              'Hora escaneo',
                              width: scannedAtWidth,
                            ),
                          ),
                          DataColumn(
                            label: _buildTableLabel(
                              'Estado',
                              width: statusWidth,
                            ),
                          ),
                        ],
                        rows: [
                          for (final entry in pageEntries)
                            DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: nameWidth,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          entry.fullName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: AppPalette.orange,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationColor:
                                                    AppPalette.orange,
                                              ),
                                        ),
                                        if (entry.note.trim().isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            entry.note,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  onTap: () => _showAttendanceControlsSheet(
                                    context,
                                    entry: entry,
                                    eventControls: widget.eventControls,
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: officeWidth,
                                    child: Text(
                                      entry.officeName ?? 'Sin oficina',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: controlsWidth,
                                    child: Text(
                                      totalControls > 0
                                          ? '${entry.attendedControlsCount}/$totalControls'
                                          : '${entry.registeredControlsCount}',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: scannedAtWidth,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _formatDate(entry.registeredAt),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatTime(entry.registeredAt),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: statusWidth,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: TextStyle(
                                            color: accentColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _RosterPaginationControls(
              currentPage: _currentPage,
              pageCount: _pageCount,
              pageStart: pageStart,
              pageEnd: pageEnd,
              totalEntries: widget.entries.length,
              showControls: hasMultiplePages,
              onFirst: () => _goToPage(0),
              onPrevious: () => _goToPage(_currentPage - 1),
              onNext: () => _goToPage(_currentPage + 1),
              onLast: () => _goToPage(_pageCount - 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _RosterPaginationControls extends StatelessWidget {
  const _RosterPaginationControls({
    required this.currentPage,
    required this.pageCount,
    required this.pageStart,
    required this.pageEnd,
    required this.totalEntries,
    required this.showControls,
    required this.onFirst,
    required this.onPrevious,
    required this.onNext,
    required this.onLast,
  });

  final int currentPage;
  final int pageCount;
  final int pageStart;
  final int pageEnd;
  final int totalEntries;
  final bool showControls;
  final VoidCallback onFirst;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLast;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isFirstPage = currentPage == 0;
    final isLastPage = currentPage >= pageCount - 1;
    final rangeLabel = totalEntries == 0
        ? 'Total: 0 registros'
        : 'Mostrando ${pageStart + 1}-$pageEnd de $totalEntries registros';

    if (!showControls) {
      return Text(rangeLabel, style: textTheme.bodySmall);
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(rangeLabel, style: textTheme.bodySmall),
        Text(
          'Pagina ${currentPage + 1} de $pageCount',
          style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton.filledTonal(
          onPressed: isFirstPage ? null : onFirst,
          tooltip: 'Primera pagina',
          icon: const Icon(Icons.first_page_rounded),
        ),
        IconButton.filledTonal(
          onPressed: isFirstPage ? null : onPrevious,
          tooltip: 'Pagina anterior',
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton.filledTonal(
          onPressed: isLastPage ? null : onNext,
          tooltip: 'Pagina siguiente',
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        IconButton.filledTonal(
          onPressed: isLastPage ? null : onLast,
          tooltip: 'Ultima pagina',
          icon: const Icon(Icons.last_page_rounded),
        ),
      ],
    );
  }
}

Widget _buildTableLabel(
  String label, {
  required double width,
  TextAlign textAlign = TextAlign.left,
}) {
  return SizedBox(
    width: width,
    child: Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    ),
  );
}

Future<void> _showAttendanceControlsSheet(
  BuildContext context, {
  required EventRosterEntry entry,
  required List<EventControl> eventControls,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _AttendanceControlsSheet(entry: entry, eventControls: eventControls),
  );
}

class _AttendanceControlsSheet extends StatelessWidget {
  const _AttendanceControlsSheet({
    required this.entry,
    required this.eventControls,
  });

  final EventRosterEntry entry;
  final List<EventControl> eventControls;

  @override
  Widget build(BuildContext context) {
    final controlsById = {
      for (final control in entry.controls) control.controlId: control,
    };

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.fullName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Controles realizados y no realizados',
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
                const SizedBox(height: 12),
                if (eventControls.isEmpty)
                  Text(
                    'Este evento todavia no tiene controles configurados.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ...eventControls.map((control) {
                    final recordedControl = controlsById[control.id];
                    final isAttended = recordedControl?.isAttended == true;
                    final isLate = recordedControl?.isLate == true;
                    final accentColor = recordedControl == null
                        ? AppPalette.muted
                        : isLate
                        ? AppPalette.orange
                        : isAttended
                        ? AppPalette.orange
                        : AppPalette.night;
                    final statusLabel = recordedControl == null
                        ? 'No realizado'
                        : isLate
                        ? 'Retrasado'
                        : isAttended
                        ? 'Asistio'
                        : 'Observado';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppPalette.surfaceSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppPalette.line),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              recordedControl == null
                                  ? Icons.remove_done_rounded
                                  : isLate
                                  ? Icons.schedule_rounded
                                  : isAttended
                                  ? Icons.how_to_reg_rounded
                                  : Icons.visibility_outlined,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  control.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  statusLabel,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: accentColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                if (recordedControl != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Registrado: ${_formatDateTime(recordedControl.registeredAt)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if ((recordedControl.note ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      recordedControl.note!,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventsLoadingState extends StatelessWidget {
  const _EventsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _EventsErrorState extends StatelessWidget {
  const _EventsErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppPalette.orangeSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: AppPalette.orange,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'No fue posible cargar eventos',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyEventsState extends StatelessWidget {
  const _EmptyEventsState({
    this.title = 'Todavia no hay eventos guardados',
    this.message =
        'Crea tu primer evento y quedara persistido en la base de datos junto con sus oficinas.',
    this.icon = Icons.event_busy_rounded,
  });

  final String title;
  final String message;
  final IconData icon;

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
              child: Icon(icon, color: AppPalette.orange),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyListState extends StatelessWidget {
  const _EmptyListState({required this.selectedListType});

  final EventListType selectedListType;

  @override
  Widget build(BuildContext context) {
    final isAttended = selectedListType == EventListType.attended;

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
              child: Icon(
                isAttended
                    ? Icons.how_to_reg_rounded
                    : Icons.visibility_outlined,
                color: AppPalette.orange,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isAttended
                  ? 'No hay personas en la lista de asistencia'
                  : 'No hay personas en la lista de observacion',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Aun no existen registros almacenados para esta lista.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final maxChipWidth = MediaQuery.sizeOf(context).width * 0.72;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxChipWidth),
          child: Ink(
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
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppPalette.muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _defaultEventLocation = LatLng(-16.489689, -68.119293);

class _OfficeSelectionEntry {
  const _OfficeSelectionEntry({required this.office, this.parentOffice});

  final EventOffice office;
  final EventOffice? parentOffice;
}

List<_OfficeSelectionEntry> _buildOfficeSelectionEntries(
  List<EventOffice> filteredOffices,
  List<EventOffice> allOffices,
) {
  final entries = <_OfficeSelectionEntry>[];
  final visibleParentByBranchOfficeId = <int, EventOffice>{};

  for (final parentOffice in filteredOffices) {
    final parentCode = _normalizeOfficeCode(parentOffice.code);
    final isExplicitSubmayoraltyParent = _submayoraltyEventBranchCodes
        .containsKey(parentCode);
    final branchOffices = _collectOfficeBranchOffices(parentOffice, allOffices);
    for (final branchOffice in branchOffices) {
      if (isExplicitSubmayoraltyParent) {
        visibleParentByBranchOfficeId[branchOffice.id] = parentOffice;
      } else {
        visibleParentByBranchOfficeId.putIfAbsent(
          branchOffice.id,
          () => parentOffice,
        );
      }
    }
  }

  for (final office in filteredOffices) {
    if (visibleParentByBranchOfficeId.containsKey(office.id)) {
      continue;
    }

    entries.add(_OfficeSelectionEntry(office: office));

    final branchOffices = _collectOfficeBranchOffices(office, allOffices);
    for (final branchOffice in branchOffices) {
      entries.add(
        _OfficeSelectionEntry(office: branchOffice, parentOffice: office),
      );
    }
  }

  return entries;
}

List<EventOffice> _collectOfficeBranchOffices(
  EventOffice office,
  List<EventOffice> offices,
) {
  return offices
      .where((candidate) {
        return candidate.id != office.id &&
            _isOfficeCoveredByBranch(candidate.code, office.code);
      })
      .toList(growable: false);
}

Set<int> _normalizeDirectOfficeSelection(
  Set<int> directOfficeIds,
  List<EventOffice> offices,
) {
  if (directOfficeIds.isEmpty) {
    return <int>{};
  }

  final selectedOffices = offices
      .where((office) => directOfficeIds.contains(office.id))
      .toList(growable: false);

  return selectedOffices
      .where(
        (office) => !selectedOffices.any(
          (candidate) =>
              candidate.id != office.id &&
              _isOfficeCoveredByBranch(office.code, candidate.code),
        ),
      )
      .map((office) => office.id)
      .toSet();
}

Set<int> _normalizeExcludedOfficeSelection(
  Set<int> selectedOfficeIds,
  Set<int> excludedOfficeIds,
  List<EventOffice> offices,
) {
  if (selectedOfficeIds.isEmpty || excludedOfficeIds.isEmpty) {
    return <int>{};
  }

  final selectedHierarchyOfficeIds = _expandOfficeSelection(
    selectedOfficeIds,
    offices,
  );
  final excludedOffices = offices
      .where(
        (office) =>
            excludedOfficeIds.contains(office.id) &&
            selectedHierarchyOfficeIds.contains(office.id) &&
            !selectedOfficeIds.contains(office.id),
      )
      .toList(growable: false);

  return excludedOffices.map((office) => office.id).toSet();
}

bool _isOfficeCoveredByAnotherSelectedBranch(
  EventOffice office,
  Set<int> selectedOfficeIds,
  List<EventOffice> offices,
) {
  return offices
      .where((candidate) => selectedOfficeIds.contains(candidate.id))
      .any(
        (candidate) =>
            candidate.id != office.id &&
            _isOfficeCoveredByBranch(office.code, candidate.code),
      );
}

Set<int> _expandOfficeSelection(
  Set<int> directOfficeIds,
  List<EventOffice> offices, {
  Set<int>? excludedOfficeIds,
}) {
  if (directOfficeIds.isEmpty) {
    return <int>{};
  }

  final resolvedExcludedOfficeIds = excludedOfficeIds ?? const <int>{};

  final selectedCodes = offices
      .where((office) => directOfficeIds.contains(office.id))
      .map((office) => _normalizeOfficeCode(office.code))
      .where((code) => code.isNotEmpty)
      .toList(growable: false);
  final excludedCodes = offices
      .where((office) => resolvedExcludedOfficeIds.contains(office.id))
      .map((office) => _normalizeOfficeCode(office.code))
      .where((code) => code.isNotEmpty)
      .toList(growable: false);

  return offices
      .where((office) {
        final officeCode = _normalizeOfficeCode(office.code);
        final isIncluded = selectedCodes.any(
          (selectedCode) =>
              officeCode == selectedCode ||
              _isOfficeCoveredByBranch(officeCode, selectedCode),
        );
        final isExcluded = excludedCodes.any(
          (excludedCode) =>
              officeCode == excludedCode ||
              _isOfficeCoveredByBranch(officeCode, excludedCode),
        );

        return isIncluded && !isExcluded;
      })
      .map((office) => office.id)
      .toSet();
}

bool _isOfficeCoveredByBranch(String officeCode, String branchCode) {
  final normalizedOfficeCode = _normalizeOfficeCode(officeCode);
  final normalizedBranchCode = _normalizeOfficeCode(branchCode);

  final explicitBranchCodes =
      _submayoraltyEventBranchCodes[normalizedBranchCode];
  if (explicitBranchCodes != null) {
    return normalizedOfficeCode == normalizedBranchCode ||
        explicitBranchCodes.contains(normalizedOfficeCode);
  }

  return normalizedOfficeCode == normalizedBranchCode ||
      normalizedOfficeCode.startsWith('$normalizedBranchCode.');
}

String _normalizeOfficeCode(String code) {
  return code.trim().replaceAll(RegExp(r'\.+$'), '');
}

const Map<String, Set<String>> _submayoraltyEventBranchCodes = {
  '10.2.2': {'10.4.3.1', '10.4.3.2', '10.4.3.3', '10.4.3.4'},
  '10.2.3': {'10.4.4.1', '10.4.4.2', '10.4.4.3', '10.4.4.4'},
  '10.2.4': {'10.4.5.1', '10.4.5.2', '10.4.5.3', '10.4.5.4'},
  '10.2.5': {'10.4.7.1', '10.4.7.2', '10.4.7.3', '10.4.7.4'},
  '10.2.6': {'10.4.6.1', '10.4.6.2', '10.4.6.3', '10.4.6.4'},
  '10.2.7': {'10.4.8.1', '10.4.8.2', '10.4.8.3', '10.4.8.4'},
};

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

bool _officeTextLooksSimilar(String value, String query) {
  if (value.isEmpty || query.isEmpty) {
    return false;
  }

  if (value == query || value.contains(query) || query.contains(value)) {
    return true;
  }

  final valueTokens = _officeSearchTokens(value);
  final queryTokens = _officeSearchTokens(query);

  if (valueTokens.isEmpty || queryTokens.isEmpty) {
    return false;
  }

  final matches = queryTokens
      .where((token) => valueTokens.any((valueToken) => valueToken == token))
      .length;
  final requiredMatches = queryTokens.length <= 2 ? queryTokens.length : 2;

  return matches >= requiredMatches;
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

String _formatDateTime(DateTime date) {
  return '${_formatDate(date)} ${_formatTime(date)}';
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '$hour:$minute';
}

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');

  return '$hour:$minute';
}

int _timeOfDayToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

TimeOfDay _addMinutesToTime(TimeOfDay time, int minutes) {
  final totalMinutes = (_timeOfDayToMinutes(time) + minutes) % (24 * 60);

  return TimeOfDay(hour: totalMinutes ~/ 60, minute: totalMinutes % 60);
}

TimeOfDay _parseTimeOfDay(String? value, TimeOfDay fallback) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value ?? '');
  final hour = int.tryParse(match?.group(1) ?? '');
  final minute = int.tryParse(match?.group(2) ?? '');

  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return fallback;
  }

  return TimeOfDay(hour: hour, minute: minute);
}
