import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/location_permission_settings.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/base64_avatar.dart';
import '../../../events/domain/entities/event_record.dart';
import '../../domain/entities/qr_details.dart';
import '../../domain/entities/qr_scan_result.dart';

class QrScanDetailsScreen extends StatefulWidget {
  const QrScanDetailsScreen({
    super.key,
    required this.scanResult,
    required this.currentUser,
    this.activeEventId,
    this.activeEventName,
    this.activeEventOffices = const [],
    this.activeEventJobTitles = const [],
    this.activeEventControls = const [],
    this.manualCi,
    this.prefetchedQrDetails,
  });

  final QrScanResult scanResult;
  final AppUser currentUser;
  final int? activeEventId;
  final String? activeEventName;
  final List<EventOffice> activeEventOffices;
  final List<EventJobTitle> activeEventJobTitles;
  final List<EventControl> activeEventControls;
  final String? manualCi;
  final QrDetails? prefetchedQrDetails;

  @override
  State<QrScanDetailsScreen> createState() => _QrScanDetailsScreenState();
}

class _QrScanDetailsScreenState extends State<QrScanDetailsScreen> {
  late final Future<QrDetails?> _qrDetailsFuture;
  String? _submittingActionKey;
  String? _lookupErrorMessage;

  @override
  void initState() {
    super.initState();
    // Apenas entra a la pantalla se resuelve el QR contra la base de datos.
    // Esto separa la lectura de camara del proceso de identificacion backend.
    _qrDetailsFuture = _loadQrDetails();
  }

  Future<QrDetails?> _loadQrDetails() async {
    if (widget.prefetchedQrDetails != null) {
      return widget.prefetchedQrDetails;
    }

    try {
      if (widget.manualCi != null) {
        final result = await dependencies.qrDetailsDataSource.getByCi(
          widget.manualCi!,
          eventId: widget.activeEventId,
        );
        return result?.toEntity();
      }

      return await dependencies.getQrDetailsByScan(
        widget.scanResult.value,
        eventId: widget.activeEventId,
      );
    } on BackendApiException catch (error) {
      _lookupErrorMessage = error.message;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        AppAlert.showError(context, error.message);
      });

      return null;
    }
  }

  Future<void> _registerAttendance(
    EventListType listType, {
    required EventControl control,
  }) async {
    // Registro operativo:
    // QR ya leido -> control seleccionado -> POST /api/asistencias -> upsert backend.
    if (widget.activeEventId == null || widget.activeEventName == null) {
      AppAlert.showWarning(
        context,
        'Primero selecciona un evento desde la seccion Eventos.',
      );
      return;
    }

    String? observation;

    if (listType == EventListType.observed) {
      observation = await _promptObservationReason();

      if (!mounted || observation == null) {
        return;
      }
    }

    final actionKey = '${control.id}-${listType.name}';

    setState(() {
      _submittingActionKey = actionKey;
    });

    try {
      final location = await _resolveCurrentLocation();
      await dependencies.eventsApiService.registerAttendance(
        eventId: widget.activeEventId!,
        controlId: control.id,
        qrValue: widget.manualCi == null ? widget.scanResult.value : null,
        ci: widget.manualCi,
        listType: listType,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
        scannedAt: widget.scanResult.scannedAt,
        observation: observation,
        payloadFields: widget.manualCi == null
            ? widget.scanResult.payloadFields
            : null,
      );

      if (!mounted) {
        return;
      }

      final actionLabel = listType == EventListType.attended
          ? 'Asistencia guardada en ${control.name}'
          : 'Observacion guardada en ${control.name}';
      final actionMessage = widget.manualCi == null
          ? '$actionLabel para ${widget.activeEventName}.'
          : '$actionLabel por CI para ${widget.activeEventName}.';

      Navigator.of(context).pop(actionMessage);
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible guardar el registro.');
    } finally {
      if (mounted) {
        setState(() {
          _submittingActionKey = null;
        });
      }
    }
  }

  Future<_AttendanceLocationSnapshot> _resolveCurrentLocation() async {
    final isLocationEnabled = await LocationPermissionSettings.isEnabled();

    if (!isLocationEnabled) {
      throw StateError(
        'Habilita la ubicacion en Configuracion para registrar la asistencia.',
      );
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw StateError('Activa tu ubicacion para registrar la asistencia.');
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    return _AttendanceLocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }

  Future<String?> _promptObservationReason() async {
    final controller = TextEditingController();
    String? validationMessage;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Motivo de observacion'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.manualCi == null
                          ? 'Describe por que esta persona quedara observada en este control.'
                          : 'Describe por que esta persona quedara observada en este control. El registro indicara ademas que fue hecho por CI.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) {
                        if (validationMessage == null) {
                          return;
                        }

                        setDialogState(() {
                          validationMessage = null;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Escribe el motivo de la observacion',
                        errorText: validationMessage,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final trimmedReason = controller.text.trim();

                    if (trimmedReason.isEmpty) {
                      setDialogState(() {
                        validationMessage =
                            'Debes escribir el motivo de la observacion.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(trimmedReason);
                  },
                  child: const Text('Guardar observacion'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  bool get _hasActiveEventContext =>
      widget.activeEventId != null && widget.activeEventName != null;

  String? _buildAttendanceRestrictionMessage(QrDetails? qrDetails) {
    if (_lookupErrorMessage != null) {
      return null;
    }

    if (!_hasActiveEventContext ||
        (widget.activeEventOffices.isEmpty &&
            widget.activeEventJobTitles.isEmpty)) {
      return null;
    }

    if (qrDetails == null) {
      return 'Este usuario no esta permitido asistir a este evento.';
    }

    final allowedOfficeIds = widget.activeEventOffices
        .map((office) => office.id)
        .toSet();
    final allowedCargoCodes = widget.activeEventJobTitles
        .map((jobTitle) => jobTitle.code)
        .toSet();
    final allowedCargoNames = widget.activeEventJobTitles
        .map((jobTitle) => _normalizeQrRestrictionText(jobTitle.name))
        .toSet();
    final userCargoName = _normalizeQrRestrictionText(
      qrDetails.fields['Cargo'] ?? '',
    );

    if ((qrDetails.officeId != null &&
            allowedOfficeIds.contains(qrDetails.officeId)) ||
        (qrDetails.cargoCodigo != null &&
            allowedCargoCodes.contains(qrDetails.cargoCodigo)) ||
        (userCargoName.isNotEmpty && allowedCargoNames.contains(userCargoName))) {
      return null;
    }

    return 'Este usuario no esta permitido asistir a este evento.';
  }

  String? _buildAttendanceRestrictionDetail(QrDetails? qrDetails) {
    if (_lookupErrorMessage != null) {
      return null;
    }

    if (!_hasActiveEventContext ||
        (widget.activeEventOffices.isEmpty &&
            widget.activeEventJobTitles.isEmpty)) {
      return null;
    }

    if (qrDetails == null) {
      return 'No se encontro una persona registrada con oficina o cargo valido para compararla contra este evento.';
    }

    if (qrDetails.officeId == null && qrDetails.cargoCodigo == null) {
      return 'La persona escaneada no tiene oficina ni cargo asociado en la base de datos.';
    }

    return 'La oficina o cargo del usuario no esta asociado a este evento.';
  }

  QrEventControlRecord? _findExistingControlRecord(
    QrDetails? qrDetails,
    EventControl control,
  ) {
    final controls = qrDetails?.eventAttendance?.controls ?? const [];

    for (final currentControl in controls) {
      if (currentControl.controlId == control.id) {
        return currentControl;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppPalette.cream,
      appBar: AppBar(
        title: Text(
          widget.manualCi == null ? 'Detalle del QR' : 'Detalle por CI',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.activeEventName != null) ...[
                Card(
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
                                'Evento activo',
                                style: textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.activeEventName!,
                                style: textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              FutureBuilder<QrDetails?>(
                future: _qrDetailsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Consultando la persona en la base de datos...',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (_lookupErrorMessage != null) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Error',
                              style: textTheme.titleLarge?.copyWith(
                                color: const Color(0xFFD94841),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _lookupErrorMessage!,
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Usuario', style: textTheme.titleLarge),
                            const SizedBox(height: 10),
                            Text(
                              'No fue posible consultar el usuario del QR.',
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final qrDetails = snapshot.data;

                  if (qrDetails == null) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Usuario', style: textTheme.titleLarge),
                            const SizedBox(height: 10),
                            Text(
                              'Este QR todavia no coincide con un usuario registrado.',
                              style: textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _hasActiveEventContext
                                  ? 'Como no se pudo validar su oficina, en este evento solo podras guardarlo como Observado.'
                                  : 'Puedes guardarlo igual en este evento para pruebas usando Asistio u Observado.',
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final visibleFields = qrDetails.fields.entries.toList(
                    growable: false,
                  );

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Usuario', style: textTheme.titleLarge),
                          const SizedBox(height: 18),
                          Center(
                            child: Base64Avatar(
                              size: 172,
                              fallbackLabel: qrDetails.title,
                              photoSource: qrDetails.photoUrl,
                              borderRadius: BorderRadius.circular(46),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: Text(
                              qrDetails.title,
                              textAlign: TextAlign.center,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          for (final entry in visibleFields)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      entry.key,
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 6,
                                    child: Text(
                                      entry.value,
                                      style: textTheme.bodyMedium?.copyWith(
                                        height: 1.3,
                                      ),
                                    ),
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
              if (widget.scanResult.displayValue !=
                  widget.scanResult.value) ...[
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vista legible', style: textTheme.titleLarge),
                        const SizedBox(height: 10),
                        SelectionArea(
                          child: SelectableText(
                            widget.scanResult.displayValue,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              FutureBuilder<QrDetails?>(
                future: _qrDetailsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox.shrink();
                  }

                  final restrictionMessage = _buildAttendanceRestrictionMessage(
                    snapshot.data,
                  );
                  final restrictionDetail = _buildAttendanceRestrictionDetail(
                    snapshot.data,
                  );

                  if (restrictionMessage == null || restrictionDetail == null) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Card(
                      color: AppPalette.orangeSoft,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.block_rounded,
                              color: AppPalette.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    restrictionMessage,
                                    style: textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$restrictionDetail Solo puedes registrarlo como Observado.',
                                    style: textTheme.bodyMedium,
                                  ),
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
              FutureBuilder<QrDetails?>(
                future: _qrDetailsFuture,
                builder: (context, snapshot) {
                  if (_lookupErrorMessage != null) {
                    return const SizedBox.shrink();
                  }

                  final qrDetails = snapshot.data;
                  final isLookupPending =
                      snapshot.connectionState != ConnectionState.done;
                  final restrictionMessage = _buildAttendanceRestrictionMessage(
                    qrDetails,
                  );

                  if (restrictionMessage != null) {
                    return const SizedBox.shrink();
                  }

                  if (!_hasActiveEventContext) {
                    return const SizedBox.shrink();
                  }

                  if (widget.activeEventControls.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'Este evento no tiene controles configurados.',
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registrar controles',
                              style: textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.manualCi == null
                                  ? 'Selecciona el control correspondiente y marca si la persona asistio u observado en ese punto del evento.'
                                  : 'Selecciona el control correspondiente. Este registro fue iniciado por CI y solo puede guardarse como Observado.',
                              style: textTheme.bodyMedium,
                            ),
                            if (widget.manualCi != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppPalette.orangeSoft,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppPalette.line),
                                ),
                                child: Text(
                                  'El sistema guardara la observacion con la nota: Registrado manualmente por CI ${widget.manualCi!.trim()}.',
                                  style: textTheme.bodySmall,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            for (final control
                                in widget.activeEventControls) ...[
                              Builder(
                                builder: (context) {
                                  final existingControl =
                                      _findExistingControlRecord(
                                        qrDetails,
                                        control,
                                      );

                                  return _ControlRegistrationCard(
                                    control: control,
                                    existingControl: existingControl,
                                    isLookupPending: isLookupPending,
                                    submittingActionKey: _submittingActionKey,
                                    allowAttended: widget.manualCi == null,
                                    observedActionLabel: widget.manualCi == null
                                        ? 'Observado'
                                        : 'Registrar por CI',
                                    onRegister: (listType) =>
                                        _registerAttendance(
                                          listType,
                                          control: control,
                                        ),
                                  );
                                },
                              ),
                              if (control != widget.activeEventControls.last)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _normalizeQrRestrictionText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class _AttendanceLocationSnapshot {
  const _AttendanceLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
}

class _ControlRegistrationCard extends StatelessWidget {
  const _ControlRegistrationCard({
    required this.control,
    required this.existingControl,
    required this.isLookupPending,
    required this.submittingActionKey,
    required this.onRegister,
    this.allowAttended = true,
    this.observedActionLabel = 'Observado',
  });

  final EventControl control;
  final QrEventControlRecord? existingControl;
  final bool isLookupPending;
  final String? submittingActionKey;
  final ValueChanged<EventListType> onRegister;
  final bool allowAttended;
  final String observedActionLabel;

  @override
  Widget build(BuildContext context) {
    final attendedKey = '${control.id}-${EventListType.attended.name}';
    final observedKey = '${control.id}-${EventListType.observed.name}';
    final isSubmittingAttended = submittingActionKey == attendedKey;
    final isSubmittingObserved = submittingActionKey == observedKey;
    final isBusy = submittingActionKey != null;
    final hasExistingRecord = existingControl != null;
    final isExistingAttended = existingControl?.isAttended == true;
    final statusAccent = hasExistingRecord
        ? isExistingAttended
              ? const Color(0xFF16A34A)
              : AppPalette.night
        : AppPalette.muted;
    final statusLabel = hasExistingRecord
        ? isExistingAttended
              ? 'Asistio'
              : 'Observado'
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(control.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (hasExistingRecord)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: statusAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusAccent.withValues(alpha: 0.24)),
              ),
              child: Row(
                children: [
                  Icon(
                    isExistingAttended
                        ? Icons.check_circle_rounded
                        : Icons.info_rounded,
                    color: statusAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusLabel!,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: statusAccent,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Este control ya fue registrado.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (allowAttended)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: isBusy || isLookupPending
                        ? null
                        : () => onRegister(EventListType.attended),
                    child: isSubmittingAttended
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Asistio'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: isBusy || isLookupPending
                        ? null
                        : () => onRegister(EventListType.observed),
                    child: isSubmittingObserved
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(observedActionLabel),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isBusy || isLookupPending
                    ? null
                    : () => onRegister(EventListType.observed),
                child: isSubmittingObserved
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(observedActionLabel),
              ),
            ),
        ],
      ),
    );
  }
}
