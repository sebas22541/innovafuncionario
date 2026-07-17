import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/file_downloader.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../infrastructure/services/sworn_declarations_api_service.dart';

class SwornDeclarationsScreen extends StatefulWidget {
  const SwornDeclarationsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<SwornDeclarationsScreen> createState() =>
      _SwornDeclarationsScreenState();
}

class _SwornDeclarationsScreenState extends State<SwornDeclarationsScreen> {
  @override
  Widget build(BuildContext context) {
    if (widget.currentUser.isAdmin) {
      return const _SwornDeclarationAdminView();
    }

    if (widget.currentUser.isExternalUser) {
      return _SwornDeclarationEmployeeView(currentUser: widget.currentUser);
    }

    return const Center(
      child: Text('No tienes permisos para declaraciones juradas.'),
    );
  }
}

class _SwornDeclarationEmployeeView extends StatefulWidget {
  const _SwornDeclarationEmployeeView({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_SwornDeclarationEmployeeView> createState() =>
      _SwornDeclarationEmployeeViewState();
}

class _SwornDeclarationEmployeeViewState
    extends State<_SwornDeclarationEmployeeView> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  final _relatives = <_RelativeDraft>[_RelativeDraft()];
  final _cityHallRelatives = <_CityHallRelativeDraft>[];
  final _doublePerception = _DoublePerceptionDraft();
  final _sentences = _SentencesDraft();
  final _incompatibilities = _IncompatibilitiesDraft();
  final _address = _AddressDraft();
  List<SwornDeclarationRecord> _records = const [];
  bool _hasCityHallRelatives = false;
  bool _isLoadingRecords = true;
  bool _isSaving = false;
  bool _hasPreloadedLatestRecord = false;
  int? _editingRecordId;
  int _step = 0;

  static const _stepTitles = [
    'Consanguinidad y Afinidad',
    'Doble Percepcion',
    'Sentencias y Procesos',
    'Otras Incompatibilidades',
    'Datos Domiciliarios',
    'Familiares en la Alcaldia',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final relative in _relatives) {
      relative.dispose();
    }
    for (final relative in _cityHallRelatives) {
      relative.dispose();
    }
    _doublePerception.dispose();
    _sentences.dispose();
    _incompatibilities.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoadingRecords = true;
    });

    try {
      final records = await dependencies.swornDeclarationsApiService
          .fetchDeclarations(onlyMine: true);

      if (!mounted) {
        return;
      }

      setState(() {
        _records = records;
      });
      _preloadLatestRecord(records);
    } catch (_) {
      if (mounted) {
        setState(() {
          _records = const [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRecords = false;
        });
      }
    }
  }

  Future<void> _next() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    if (_step == 4) {
      await _captureAddressMapImage();
    }

    if (_step == _stepTitles.length - 1) {
      await _save();
      return;
    }

    setState(() {
      _step++;
    });
    await _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _captureAddressMapImage() async {
    final context = _address.mapKey.currentContext;

    if (context == null) {
      return;
    }

    final boundary = context.findRenderObject();

    if (boundary is! RenderRepaintBoundary) {
      return;
    }

    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();

      if (bytes != null) {
        _address.mapImageBase64 = base64Encode(bytes);
      }
    } catch (_) {
      // La captura del mapa no debe impedir guardar la declaracion.
    }
  }

  Future<void> _previous() async {
    if (_step == 0) {
      return;
    }

    setState(() {
      _step--;
    });
    await _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    if (_hasCityHallRelatives && _cityHallRelatives.isEmpty) {
      AppAlert.showWarning(
        context,
        'Debes registrar los datos de familiares que trabajan en la alcaldia.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final payload = _buildPayload();
      final editingRecordId = _editingRecordId;

      if (editingRecordId == null) {
        await dependencies.swornDeclarationsApiService.createDeclaration(
          managementYear: DateTime.now().year,
          payload: payload,
        );
      } else {
        await dependencies.swornDeclarationsApiService.updateDeclaration(
          id: editingRecordId,
          managementYear: DateTime.now().year,
          payload: payload,
        );
      }

      if (!mounted) {
        return;
      }

      AppAlert.showSuccess(
        context,
        editingRecordId == null
            ? 'La declaracion jurada fue enviada para revision.'
            : 'La declaracion jurada fue corregida y enviada nuevamente.',
        title: editingRecordId == null
            ? 'Declaracion enviada'
            : 'Declaracion reenviada',
      );
      _resetDraft();
      await _loadRecords();
    } on BackendApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No fue posible guardar la declaracion.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildPayload() {
    return {
      'consanguinidadAfinidad': _relatives
          .map((relative) => relative.toJson())
          .toList(),
      'doblePercepcion': _doublePerception.toJson(),
      'sentenciasProcesos': _sentences.toJson(),
      'otrasIncompatibilidades': _incompatibilities.toJson(),
      'datosDomiciliarios': _address.toJson(),
      'familiaresAlcaldia': {
        'tieneFamiliares': _hasCityHallRelatives,
        'familiares': _hasCityHallRelatives
            ? _cityHallRelatives.map((relative) => relative.toJson()).toList()
            : <Map<String, dynamic>>[],
      },
    };
  }

  void _resetDraft() {
    setState(() {
      for (final relative in _relatives) {
        relative.dispose();
      }
      for (final relative in _cityHallRelatives) {
        relative.dispose();
      }
      _relatives
        ..clear()
        ..add(_RelativeDraft());
      _cityHallRelatives.clear();
      _doublePerception.reset();
      _sentences.reset();
      _incompatibilities.reset();
      _address.reset();
      _hasCityHallRelatives = false;
      _editingRecordId = null;
      _hasPreloadedLatestRecord = false;
      _step = 0;
    });
    _pageController.jumpToPage(0);
  }

  void _editRejectedRecord(SwornDeclarationRecord record) {
    if (record.status != SwornDeclarationStatus.rejected) {
      return;
    }

    _loadRecordIntoDraft(record, editing: true);
    AppAlert.showWarning(
      context,
      'Edita la declaracion rechazada y vuelve a finalizar para enviarla.',
      title: 'Edicion habilitada',
    );
  }

  void _preloadLatestRecord(List<SwornDeclarationRecord> records) {
    if (_hasPreloadedLatestRecord ||
        _editingRecordId != null ||
        records.isEmpty) {
      return;
    }

    final latestRecord = records.firstWhere(
      (record) => record.status != SwornDeclarationStatus.rejected,
      orElse: () => records.first,
    );

    _loadRecordIntoDraft(latestRecord, editing: false);
    AppAlert.showSuccess(
      context,
      'Se precargaron los datos de tu ultima declaracion. Puedes modificar o aumentar lo necesario.',
      title: 'Datos precargados',
    );
  }

  void _loadRecordIntoDraft(
    SwornDeclarationRecord record, {
    required bool editing,
  }) {
    final payload = record.payload;
    final relatives = _readPayloadList(payload['consanguinidadAfinidad']);
    final cityHall = _readPayloadMap(payload['familiaresAlcaldia']);
    final cityHallRelatives = _readPayloadList(cityHall['familiares']);

    setState(() {
      for (final relative in _relatives) {
        relative.dispose();
      }
      for (final relative in _cityHallRelatives) {
        relative.dispose();
      }
      _relatives
        ..clear()
        ..addAll(
          relatives.isEmpty
              ? [_RelativeDraft()]
              : relatives.map((item) => _RelativeDraft.fromJson(item)),
        );
      _doublePerception.loadFromJson(
        _readPayloadMap(payload['doblePercepcion']),
      );
      _sentences.loadFromJson(_readPayloadMap(payload['sentenciasProcesos']));
      _incompatibilities.loadFromJson(
        _readPayloadMap(payload['otrasIncompatibilidades']),
      );
      _address.loadFromJson(_readPayloadMap(payload['datosDomiciliarios']));
      _hasCityHallRelatives = cityHall['tieneFamiliares'] == true;
      _cityHallRelatives
        ..clear()
        ..addAll(
          _hasCityHallRelatives
              ? (cityHallRelatives.isEmpty
                    ? [_CityHallRelativeDraft()]
                    : cityHallRelatives.map(
                        (item) => _CityHallRelativeDraft.fromJson(item),
                      ))
              : <_CityHallRelativeDraft>[],
        );
      _editingRecordId = editing ? record.id : null;
      _hasPreloadedLatestRecord = !editing;
      _step = 0;
    });
    _pageController.jumpToPage(0);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : AppPalette.night,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EmployeeSummaryCard(currentUser: widget.currentUser),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepHeader(
                      step: _step,
                      total: _stepTitles.length,
                      title: _stepTitles[_step],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: _step == 4 ? 760 : 620,
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _RelativesStep(
                            relatives: _relatives,
                            onChanged: () => setState(() {}),
                          ),
                          _DoublePerceptionStep(draft: _doublePerception),
                          _SentencesStep(draft: _sentences),
                          _IncompatibilitiesStep(draft: _incompatibilities),
                          _AddressStep(draft: _address),
                          _CityHallRelativesStep(
                            hasRelatives: _hasCityHallRelatives,
                            relatives: _cityHallRelatives,
                            onHasRelativesChanged: (value) => setState(() {
                              _hasCityHallRelatives = value;
                              if (value && _cityHallRelatives.isEmpty) {
                                _cityHallRelatives.add(
                                  _CityHallRelativeDraft(),
                                );
                              }
                            }),
                            onChanged: () => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (_step > 0)
                          OutlinedButton.icon(
                            onPressed: _isSaving ? null : _previous,
                            icon: const Icon(Icons.chevron_left_rounded),
                            label: const Text('Anterior'),
                          ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _isSaving ? null : _next,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _step == _stepTitles.length - 1
                                      ? Icons.check_rounded
                                      : Icons.chevron_right_rounded,
                                ),
                          label: Text(
                            _step == _stepTitles.length - 1
                                ? (_editingRecordId == null
                                      ? 'Finalizar'
                                      : 'Reenviar')
                                : 'Siguiente',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _EmployeeHistoryCard(
              records: _records,
              isLoading: _isLoadingRecords,
              onRefresh: _loadRecords,
              onEditRejected: _editRejectedRecord,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwornDeclarationAdminView extends StatefulWidget {
  const _SwornDeclarationAdminView();

  @override
  State<_SwornDeclarationAdminView> createState() =>
      _SwornDeclarationAdminViewState();
}

class _SwornDeclarationAdminViewState
    extends State<_SwornDeclarationAdminView> {
  final _searchController = TextEditingController();
  List<SwornDeclarationRecord> _records = const [];
  bool _isLoading = true;
  int? _reviewingId;
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

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await dependencies.swornDeclarationsApiService
          .fetchDeclarations(query: _searchController.text);

      if (!mounted) {
        return;
      }

      setState(() {
        _records = records;
      });
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
          _errorMessage = 'No fue posible cargar declaraciones juradas.';
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

  Future<void> _review(
    SwornDeclarationRecord record,
    SwornDeclarationStatus status,
  ) async {
    if (_reviewingId != null) {
      return;
    }

    setState(() {
      _reviewingId = record.id;
    });

    try {
      await dependencies.swornDeclarationsApiService.reviewDeclaration(
        id: record.id,
        status: status,
      );

      if (!mounted) {
        return;
      }

      await _load();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        AppAlert.showSuccess(
          context,
          status == SwornDeclarationStatus.approved
              ? 'Declaracion aprobada.'
              : 'Declaracion rechazada.',
        );
      }
    } on BackendApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No fue posible revisar la declaracion.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _reviewingId = null;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : AppPalette.night,
      ),
    );
  }

  Future<void> _openDetail(SwornDeclarationRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SwornDeclarationDetailDialog(
        record: record,
        isReviewing: _reviewingId == record.id,
        onApprove: record.status == SwornDeclarationStatus.pending
            ? () => _review(record, SwornDeclarationStatus.approved)
            : null,
        onReject: record.status == SwornDeclarationStatus.pending
            ? () => _review(record, SwornDeclarationStatus.rejected)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Declaraciones juradas',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(
                    width: 360,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar funcionario',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Buscar'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_errorMessage != null)
                Text(_errorMessage!)
              else if (_records.isEmpty)
                const Text('No hay declaraciones juradas registradas.')
              else
                _AdminDeclarationsTable(
                  records: _records,
                  reviewingId: _reviewingId,
                  onOpen: _openDetail,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelativesStep extends StatelessWidget {
  const _RelativesStep({required this.relatives, required this.onChanged});

  final List<_RelativeDraft> relatives;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (var index = 0; index < relatives.length; index++) ...[
          _RelativeEditor(
            index: index,
            draft: relatives[index],
            canRemove: relatives.length > 1,
            onRemove: () {
              relatives.removeAt(index).dispose();
              onChanged();
            },
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              relatives.add(_RelativeDraft());
              onChanged();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar familiar'),
          ),
        ),
      ],
    );
  }
}

class _DoublePerceptionStep extends StatefulWidget {
  const _DoublePerceptionStep({required this.draft});

  final _DoublePerceptionDraft draft;

  @override
  State<_DoublePerceptionStep> createState() => _DoublePerceptionStepState();
}

class _DoublePerceptionStepState extends State<_DoublePerceptionStep> {
  @override
  Widget build(BuildContext context) {
    final required = widget.draft.perceives;

    return ListView(
      children: [
        const Text(
          'Declara si percibes otra remuneracion con cargo a recursos publicos.',
        ),
        const SizedBox(height: 12),
        _YesNoField(
          label: 'Doble percepcion',
          value: widget.draft.perceives,
          yesLabel: 'Si percibo doble percepcion',
          noLabel: 'No percibo doble percepcion',
          onChanged: (value) => setState(() {
            widget.draft.perceives = value;
            if (!value) {
              widget.draft.clearOptionalValues();
            }
          }),
        ),
        const SizedBox(height: 14),
        _TextInput(
          controller: widget.draft.institution,
          label: 'Nombre de la institucion',
          required: required,
        ),
        _TextInput(
          controller: widget.draft.function,
          label: 'Funcion que desempena',
          required: required,
        ),
        _TextInput(
          controller: widget.draft.amount,
          label: 'Monto que percibe',
          required: required,
          keyboardType: TextInputType.number,
        ),
        _TextInput(
          controller: widget.draft.currentSalary,
          label: 'Remuneracion del cargo actual',
          required: required,
          keyboardType: TextInputType.number,
        ),
        _TextInput(
          controller: widget.draft.totalSalary,
          label: 'Monto total remuneracion',
          required: required,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}

class _SentencesStep extends StatefulWidget {
  const _SentencesStep({required this.draft});

  final _SentencesDraft draft;

  @override
  State<_SentencesStep> createState() => _SentencesStepState();
}

class _SentencesStepState extends State<_SentencesStep> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _ConditionalTextArea(
          label: 'Tengo sentencias ejecutoriadas pendientes',
          value: widget.draft.hasSentences,
          controller: widget.draft.sentencesDetail,
          detailLabel: 'Tipo de sentencia y juzgado',
          onChanged: (value) => setState(() {
            widget.draft.hasSentences = value;
            widget.draft.applyDefaults();
          }),
        ),
        _ConditionalTextArea(
          label: 'En la actualidad tengo algun proceso',
          value: widget.draft.hasProcesses,
          controller: widget.draft.processesDetail,
          detailLabel: 'Estado del proceso',
          onChanged: (value) => setState(() {
            widget.draft.hasProcesses = value;
            widget.draft.applyDefaults();
          }),
        ),
        _ConditionalTextArea(
          label: 'He sido destituido anteriormente',
          value: widget.draft.wasDismissed,
          controller: widget.draft.dismissalDetail,
          detailLabel: 'Motivo y anio',
          onChanged: (value) => setState(() {
            widget.draft.wasDismissed = value;
            widget.draft.applyDefaults();
          }),
        ),
      ],
    );
  }
}

class _IncompatibilitiesStep extends StatefulWidget {
  const _IncompatibilitiesStep({required this.draft});

  final _IncompatibilitiesDraft draft;

  @override
  State<_IncompatibilitiesStep> createState() => _IncompatibilitiesStepState();
}

class _IncompatibilitiesStepState extends State<_IncompatibilitiesStep> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _ConditionalTextArea(
          label: 'Recibo renta del sistema de reparto o compensacion',
          value: widget.draft.receivesPension,
          controller: widget.draft.pensionDetail,
          detailLabel: 'Fecha de suspension y documento adjunto',
          onChanged: (value) => setState(() {
            widget.draft.receivesPension = value;
            widget.draft.applyDefaults();
          }),
        ),
        _YesNoField(
          label: 'Compromiso por matrimonio con servidor(a) del GAMC',
          value: widget.draft.marriageCommitment,
          onChanged: (value) => setState(() {
            widget.draft.marriageCommitment = value;
          }),
        ),
        const SizedBox(height: 12),
        _ConditionalTextArea(
          label: 'Represento empresas privadas relacionadas con el Estado',
          value: widget.draft.representsCompanies,
          controller: widget.draft.companyName,
          detailLabel: 'Nombre de la empresa',
          onChanged: (value) => setState(() {
            widget.draft.representsCompanies = value;
            widget.draft.applyDefaults();
          }),
        ),
      ],
    );
  }
}

class _AddressStep extends StatefulWidget {
  const _AddressStep({required this.draft});

  final _AddressDraft draft;

  @override
  State<_AddressStep> createState() => _AddressStepState();
}

class _AddressStepState extends State<_AddressStep> {
  static const _cochabambaCenter = LatLng(-17.3895, -66.1568);

  @override
  Widget build(BuildContext context) {
    final selected = widget.draft.location;

    return ListView(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            child: RepaintBoundary(
              key: widget.draft.mapKey,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: selected ?? _cochabambaCenter,
                  initialZoom: selected == null ? 13 : 17,
                  onTap: (_, point) => setState(() {
                    widget.draft.location = point;
                    widget.draft.mapImageBase64 = null;
                  }),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                        'com.innova.funcionario.cochabamba.bo',
                  ),
                  if (selected != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: selected,
                          width: 44,
                          height: 44,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.red,
                            size: 42,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        if (selected == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Haz click en el mapa para marcar tu domicilio.',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        const SizedBox(height: 14),
        _TextInput(
          controller: widget.draft.street,
          label: 'Calle/Avenida',
          required: true,
        ),
        _TextInput(
          controller: widget.draft.zone,
          label: 'Barrio/Zona',
          required: true,
        ),
        _TextInput(
          controller: widget.draft.houseNumber,
          label: 'Numero de domicilio',
          required: true,
        ),
        _DropdownTextInput(
          label: 'Tipo de vivienda',
          value: widget.draft.houseType,
          values: const ['PROPIA', 'ALQUILADA', 'ANTICRETICO', 'OTRO'],
          onChanged: (value) => setState(() {
            widget.draft.houseType = value ?? 'OTRO';
          }),
        ),
        _TextInput(controller: widget.draft.building, label: 'Edificio'),
        _TextInput(controller: widget.draft.floor, label: 'Piso'),
        _TextInput(controller: widget.draft.department, label: 'Departamento'),
        _TextInput(controller: widget.draft.references, label: 'Referencias'),
        _TextInput(
          controller: widget.draft.cellPhone,
          label: 'Telefono celular',
          required: true,
          keyboardType: TextInputType.phone,
        ),
        _TextInput(
          controller: widget.draft.referencePhone,
          label: 'Telefono referencia',
          required: true,
          keyboardType: TextInputType.phone,
        ),
        _MapLocationValidator(location: selected),
      ],
    );
  }
}

class _CityHallRelativesStep extends StatelessWidget {
  const _CityHallRelativesStep({
    required this.hasRelatives,
    required this.relatives,
    required this.onHasRelativesChanged,
    required this.onChanged,
  });

  final bool hasRelatives;
  final List<_CityHallRelativeDraft> relatives;
  final ValueChanged<bool> onHasRelativesChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _YesNoField(
          label: 'Tengo familiares trabajando en la alcaldia',
          value: hasRelatives,
          onChanged: onHasRelativesChanged,
        ),
        const SizedBox(height: 12),
        if (hasRelatives) ...[
          for (var index = 0; index < relatives.length; index++) ...[
            _CityHallRelativeEditor(
              index: index,
              draft: relatives[index],
              canRemove: relatives.length > 1,
              onRemove: () {
                relatives.removeAt(index).dispose();
                onChanged();
              },
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                relatives.add(_CityHallRelativeDraft());
                onChanged();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar familiar'),
            ),
          ),
        ] else
          const Text('Marcaste que no tienes familiares en la alcaldia.'),
      ],
    );
  }
}

class _RelativeEditor extends StatelessWidget {
  const _RelativeEditor({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final _RelativeDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _EditorBox(
      title: 'Familiar ${index + 1}',
      canRemove: canRemove,
      onRemove: onRemove,
      children: [
        _DropdownTextInput(
          label: 'Parentesco',
          value: draft.relationship,
          values: const [
            'ESPOSO(A)',
            'PADRES',
            'HIJOS',
            'HERMANOS',
            'CUNADOS',
            'SOBRINOS',
            'OTRO',
          ],
          onChanged: (value) => draft.relationship = value ?? 'OTRO',
        ),
        _TextInput(controller: draft.names, label: 'Nombres', required: true),
        _TextInput(controller: draft.firstLastName, label: 'Apellido paterno'),
        _TextInput(controller: draft.secondLastName, label: 'Apellido materno'),
        _TextInput(
          controller: draft.identityDocument,
          label: 'Documento de identidad',
          required: true,
        ),
        _TextInput(controller: draft.occupation, label: 'Ocupacion'),
        _TextInput(controller: draft.workplace, label: 'Lugar de trabajo'),
        _DropdownTextInput(
          label: 'Fallecido',
          value: draft.deceased ? 'SI' : 'NO',
          values: const ['NO', 'SI'],
          onChanged: (value) => draft.deceased = value == 'SI',
        ),
      ],
    );
  }
}

class _CityHallRelativeEditor extends StatelessWidget {
  const _CityHallRelativeEditor({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final _CityHallRelativeDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _EditorBox(
      title: 'Familiar alcaldia ${index + 1}',
      canRemove: canRemove,
      onRemove: onRemove,
      children: [
        _TextInput(
          controller: draft.relationship,
          label: 'Parentesco',
          required: true,
        ),
        _TextInput(
          controller: draft.fullName,
          label: 'Nombre completo',
          required: true,
        ),
        _TextInput(controller: draft.jobTitle, label: 'Cargo', required: true),
        _TextInput(controller: draft.unit, label: 'Unidad', required: true),
      ],
    );
  }
}

class _AdminDeclarationsTable extends StatelessWidget {
  const _AdminDeclarationsTable({
    required this.records,
    required this.reviewingId,
    required this.onOpen,
  });

  final List<SwornDeclarationRecord> records;
  final int? reviewingId;
  final ValueChanged<SwornDeclarationRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        if (compact) {
          return Column(
            children: [
              for (final record in records) ...[
                _DeclarationListTile(
                  record: record,
                  onTap: () => onOpen(record),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 44, child: Text('Nro')),
                  Expanded(flex: 3, child: Text('Funcionario')),
                  SizedBox(width: 110, child: Text('CI')),
                  SizedBox(width: 90, child: Text('Gestion')),
                  Expanded(flex: 2, child: Text('Oficina')),
                  SizedBox(width: 110, child: Text('Estado')),
                  SizedBox(width: 52),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < records.length; index++) ...[
              _DeclarationTableRow(
                index: index,
                record: records[index],
                onTap: () => onOpen(records[index]),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _DeclarationTableRow extends StatelessWidget {
  const _DeclarationTableRow({
    required this.index,
    required this.record,
    required this.onTap,
  });

  final int index;
  final SwornDeclarationRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppPalette.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(width: 44, child: Text('${index + 1}')),
              Expanded(
                flex: 3,
                child: Text(
                  record.employeeFullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: 110, child: Text(record.employeeCi)),
              SizedBox(width: 90, child: Text('${record.managementYear}')),
              Expanded(
                flex: 2,
                child: Text(
                  record.employeeOffice,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 110,
                child: _DeclarationStatusBadge(record.status),
              ),
              const SizedBox(width: 52, child: Icon(Icons.visibility_outlined)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeclarationListTile extends StatelessWidget {
  const _DeclarationListTile({
    required this.record,
    required this.onTap,
    this.onPdf,
    this.onEdit,
  });

  final SwornDeclarationRecord record;
  final VoidCallback onTap;
  final VoidCallback? onPdf;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppPalette.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      record.employeeFullName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _DeclarationStatusBadge(record.status),
                  if (onPdf != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      tooltip: 'Descargar PDF',
                    ),
                  ],
                  if (onEdit != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Editar y reenviar',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'CI ${record.employeeCi} - Gestion ${record.managementYear}',
              ),
              Text(record.employeeOffice),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeHistoryCard extends StatelessWidget {
  const _EmployeeHistoryCard({
    required this.records,
    required this.isLoading,
    required this.onRefresh,
    required this.onEditRejected,
  });

  final List<SwornDeclarationRecord> records;
  final bool isLoading;
  final VoidCallback onRefresh;
  final ValueChanged<SwornDeclarationRecord> onEditRejected;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                  'Mis anteriores registros',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (records.isEmpty)
              const Text('Aun no tienes declaraciones juradas registradas.')
            else
              Column(
                children: [
                  for (final record in records) ...[
                    _DeclarationListTile(
                      record: record,
                      onPdf: () =>
                          _downloadSwornDeclarationPdf(context, record),
                      onEdit: record.status == SwornDeclarationStatus.rejected
                          ? () => onEditRejected(record)
                          : null,
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => _SwornDeclarationDetailDialog(
                          record: record,
                          isReviewing: false,
                          onApprove: null,
                          onReject: null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SwornDeclarationDetailDialog extends StatelessWidget {
  const _SwornDeclarationDetailDialog({
    required this.record,
    required this.isReviewing,
    required this.onApprove,
    required this.onReject,
  });

  final SwornDeclarationRecord record;
  final bool isReviewing;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Declaracion jurada')),
          _DeclarationStatusBadge(record.status),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryRow(label: 'Funcionario', value: record.employeeFullName),
              _SummaryRow(label: 'CI', value: record.employeeCi),
              _SummaryRow(label: 'Item', value: record.employeeItemNumber),
              _SummaryRow(label: 'Cargo', value: record.employeeJobTitle),
              _SummaryRow(label: 'Oficina', value: record.employeeOffice),
              _SummaryRow(label: 'Gestion', value: '${record.managementYear}'),
              _SummaryRow(
                label: 'Fecha',
                value: _formatDateTime(record.createdAt),
              ),
              if (record.reviewedByName.isNotEmpty) ...[
                const Divider(height: 22),
                _SummaryRow(
                  label: 'Revisado por',
                  value: record.reviewedByName,
                ),
                _SummaryRow(
                  label: 'Revision',
                  value: record.reviewedAt == null
                      ? ''
                      : _formatDateTime(record.reviewedAt!),
                ),
                _SummaryRow(
                  label: 'Observacion',
                  value: record.reviewObservation,
                ),
              ],
              const Divider(height: 22),
              _PayloadSection(
                title: 'Consanguinidad y afinidad',
                value: record.payload['consanguinidadAfinidad'],
              ),
              _PayloadSection(
                title: 'Doble percepcion',
                value: record.payload['doblePercepcion'],
              ),
              _PayloadSection(
                title: 'Sentencias y procesos',
                value: record.payload['sentenciasProcesos'],
              ),
              _PayloadSection(
                title: 'Otras incompatibilidades',
                value: record.payload['otrasIncompatibilidades'],
              ),
              _PayloadSection(
                title: 'Datos domiciliarios',
                value: record.payload['datosDomiciliarios'],
              ),
              _PayloadSection(
                title: 'Familiares en la alcaldia',
                value: record.payload['familiaresAlcaldia'],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        OutlinedButton.icon(
          onPressed: () => _downloadSwornDeclarationPdf(context, record),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF'),
        ),
        if (onReject != null)
          OutlinedButton.icon(
            onPressed: isReviewing ? null : onReject,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Rechazar'),
          ),
        if (onApprove != null)
          FilledButton.icon(
            onPressed: isReviewing ? null : onApprove,
            icon: isReviewing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Aprobar'),
          ),
      ],
    );
  }
}

class _PayloadSection extends StatelessWidget {
  const _PayloadSection({required this.title, required this.value});

  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _PayloadValue(value: value),
        ],
      ),
    );
  }
}

class _PayloadValue extends StatelessWidget {
  const _PayloadValue({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    if (value is List) {
      final list = value! as List;

      if (list.isEmpty) {
        return const Text('Sin registros');
      }

      return Column(
        children: [
          for (var index = 0; index < list.length; index++)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                border: Border.all(color: AppPalette.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _PayloadValue(value: list[index]),
            ),
        ],
      );
    }

    if (value is Map) {
      final map = (value! as Map).entries.toList(growable: false);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in map)
            _SummaryRow(
              label: _humanizeKey(entry.key.toString()),
              value: _formatPayloadLeaf(entry.value),
            ),
        ],
      );
    }

    return Text(_formatPayloadLeaf(value));
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.total,
    required this.title,
  });

  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: (step + 1) / total),
        const SizedBox(height: 6),
        Text('Paso ${step + 1} de $total'),
      ],
    );
  }
}

class _EmployeeSummaryCard extends StatelessWidget {
  const _EmployeeSummaryCard({required this.currentUser});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Datos del funcionario',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _SummaryRow(label: 'Nombre', value: currentUser.fullName),
            _SummaryRow(label: 'CI', value: currentUser.ci),
            _SummaryRow(label: 'Item', value: currentUser.numeroItem),
            _SummaryRow(label: 'Cargo', value: currentUser.effectiveCargo),
            _SummaryRow(
              label: 'Oficina',
              value: currentUser.officeName ?? currentUser.unidad,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorBox extends StatelessWidget {
  const _EditorBox({
    required this.title,
    required this.canRemove,
    required this.onRemove,
    required this.children,
  });

  final String title;
  final bool canRemove;
  final VoidCallback onRemove;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppPalette.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Eliminar',
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.label,
    this.required = false,
    this.keyboardType,
    this.minLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final TextInputType? keyboardType;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: minLines > 1 ? 5 : 1,
        decoration: InputDecoration(labelText: required ? '$label (*)' : label),
        validator: required
            ? (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Campo obligatorio.';
                }

                return null;
              }
            : null,
      ),
    );
  }
}

class _DropdownTextInput extends StatelessWidget {
  const _DropdownTextInput({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: values.contains(value) ? value : values.first,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final item in values)
            DropdownMenuItem(value: item, child: Text(item)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _YesNoField extends StatelessWidget {
  const _YesNoField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.yesLabel = 'SI',
    this.noLabel = 'NO',
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String yesLabel;
  final String noLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            ChoiceChip(
              selected: value,
              label: Text(yesLabel),
              avatar: Icon(
                value ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
              ),
              onSelected: (_) => onChanged(true),
            ),
            ChoiceChip(
              selected: !value,
              label: Text(noLabel),
              avatar: Icon(
                !value ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
              ),
              onSelected: (_) => onChanged(false),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConditionalTextArea extends StatelessWidget {
  const _ConditionalTextArea({
    required this.label,
    required this.value,
    required this.controller,
    required this.detailLabel,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final TextEditingController controller;
  final String detailLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _YesNoField(label: label, value: value, onChanged: onChanged),
          const SizedBox(height: 12),
          _TextInput(
            controller: controller,
            label: detailLabel,
            required: value,
            minLines: 2,
          ),
        ],
      ),
    );
  }
}

class _MapLocationValidator extends StatelessWidget {
  const _MapLocationValidator({required this.location});

  final LatLng? location;

  @override
  Widget build(BuildContext context) {
    return FormField<LatLng>(
      initialValue: location,
      validator: (_) => location == null ? 'Debes marcar tu domicilio.' : null,
      builder: (field) {
        if (!field.hasError) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            field.errorText!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        );
      },
    );
  }
}

class _DeclarationStatusBadge extends StatelessWidget {
  const _DeclarationStatusBadge(this.status);

  final SwornDeclarationStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SwornDeclarationStatus.approved => Colors.green.shade700,
      SwornDeclarationStatus.rejected => Colors.red.shade700,
      SwornDeclarationStatus.pending => AppPalette.orange,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? 'Sin dato' : value.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: AppPalette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(displayValue)),
        ],
      ),
    );
  }
}

class _RelativeDraft {
  _RelativeDraft();

  String relationship = 'ESPOSO(A)';
  bool deceased = false;
  final names = TextEditingController();
  final firstLastName = TextEditingController();
  final secondLastName = TextEditingController();
  final identityDocument = TextEditingController();
  final occupation = TextEditingController();
  final workplace = TextEditingController();

  factory _RelativeDraft.fromJson(Map<String, dynamic> source) {
    final draft = _RelativeDraft()
      ..relationship = _readPayloadString(source['parentesco'], 'OTRO')
      ..deceased = source['fallecido'] == true;
    draft.names.text = _readPayloadString(source['nombres']);
    draft.firstLastName.text = _readPayloadString(source['apellidoPaterno']);
    draft.secondLastName.text = _readPayloadString(source['apellidoMaterno']);
    draft.identityDocument.text = _readPayloadString(
      source['documentoIdentidad'],
    );
    draft.occupation.text = _readPayloadString(source['ocupacion']);
    draft.workplace.text = _readPayloadString(source['lugarTrabajo']);

    return draft;
  }

  Map<String, dynamic> toJson() {
    return {
      'parentesco': relationship,
      'nombres': names.text.trim(),
      'apellidoPaterno': firstLastName.text.trim(),
      'apellidoMaterno': secondLastName.text.trim(),
      'documentoIdentidad': identityDocument.text.trim(),
      'ocupacion': occupation.text.trim(),
      'lugarTrabajo': workplace.text.trim(),
      'fallecido': deceased,
    };
  }

  void dispose() {
    names.dispose();
    firstLastName.dispose();
    secondLastName.dispose();
    identityDocument.dispose();
    occupation.dispose();
    workplace.dispose();
  }
}

class _DoublePerceptionDraft {
  bool perceives = false;
  final institution = TextEditingController();
  final function = TextEditingController(text: 'NINGUNA');
  final amount = TextEditingController();
  final currentSalary = TextEditingController(text: '0');
  final totalSalary = TextEditingController(text: '0');

  void clearOptionalValues() {
    institution.clear();
    function.text = 'NINGUNA';
    amount.clear();
    currentSalary.text = '0';
    totalSalary.text = '0';
  }

  void reset() {
    perceives = false;
    clearOptionalValues();
  }

  void loadFromJson(Map<String, dynamic> source) {
    perceives = source['percibeDoblePercepcion'] == true;
    institution.text = _readPayloadString(source['institucion']);
    function.text = _readPayloadString(source['funcion'], 'NINGUNA');
    amount.text = _readPayloadString(source['montoPercibe']);
    currentSalary.text = _readPayloadString(
      source['remuneracionCargoActual'],
      '0',
    );
    totalSalary.text = _readPayloadString(
      source['montoTotalRemuneracion'],
      '0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'percibeDoblePercepcion': perceives,
      'institucion': institution.text.trim(),
      'funcion': function.text.trim(),
      'montoPercibe': amount.text.trim(),
      'remuneracionCargoActual': currentSalary.text.trim(),
      'montoTotalRemuneracion': totalSalary.text.trim(),
    };
  }

  void dispose() {
    institution.dispose();
    function.dispose();
    amount.dispose();
    currentSalary.dispose();
    totalSalary.dispose();
  }
}

class _SentencesDraft {
  bool hasSentences = false;
  bool hasProcesses = false;
  bool wasDismissed = false;
  final sentencesDetail = TextEditingController(text: 'NO APLICA');
  final processesDetail = TextEditingController(text: 'NO APLICA');
  final dismissalDetail = TextEditingController(text: 'NO APLICA');

  void applyDefaults() {
    if (!hasSentences) {
      sentencesDetail.text = 'NO APLICA';
    } else if (sentencesDetail.text.trim().toUpperCase() == 'NO APLICA') {
      sentencesDetail.clear();
    }

    if (!hasProcesses) {
      processesDetail.text = 'NO APLICA';
    } else if (processesDetail.text.trim().toUpperCase() == 'NO APLICA') {
      processesDetail.clear();
    }

    if (!wasDismissed) {
      dismissalDetail.text = 'NO APLICA';
    } else if (dismissalDetail.text.trim().toUpperCase() == 'NO APLICA') {
      dismissalDetail.clear();
    }
  }

  void reset() {
    hasSentences = false;
    hasProcesses = false;
    wasDismissed = false;
    applyDefaults();
  }

  void loadFromJson(Map<String, dynamic> source) {
    hasSentences = source['tieneSentencias'] == true;
    hasProcesses = source['tieneProcesos'] == true;
    wasDismissed = source['fueDestituido'] == true;
    sentencesDetail.text = _readPayloadString(
      source['detalleSentencias'],
      'NO APLICA',
    );
    processesDetail.text = _readPayloadString(
      source['detalleProcesos'],
      'NO APLICA',
    );
    dismissalDetail.text = _readPayloadString(
      source['detalleDestitucion'],
      'NO APLICA',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tieneSentencias': hasSentences,
      'detalleSentencias': sentencesDetail.text.trim(),
      'tieneProcesos': hasProcesses,
      'detalleProcesos': processesDetail.text.trim(),
      'fueDestituido': wasDismissed,
      'detalleDestitucion': dismissalDetail.text.trim(),
    };
  }

  void dispose() {
    sentencesDetail.dispose();
    processesDetail.dispose();
    dismissalDetail.dispose();
  }
}

class _IncompatibilitiesDraft {
  bool receivesPension = false;
  bool marriageCommitment = true;
  bool representsCompanies = false;
  final pensionDetail = TextEditingController(text: 'NO APLICA');
  final companyName = TextEditingController(text: 'NO APLICA');

  void applyDefaults() {
    if (!receivesPension) {
      pensionDetail.text = 'NO APLICA';
    } else if (pensionDetail.text.trim().toUpperCase() == 'NO APLICA') {
      pensionDetail.clear();
    }

    if (!representsCompanies) {
      companyName.text = 'NO APLICA';
    } else if (companyName.text.trim().toUpperCase() == 'NO APLICA') {
      companyName.clear();
    }
  }

  void reset() {
    receivesPension = false;
    marriageCommitment = true;
    representsCompanies = false;
    applyDefaults();
  }

  void loadFromJson(Map<String, dynamic> source) {
    receivesPension = source['recibeRenta'] == true;
    marriageCommitment = source['compromisoMatrimonio'] != false;
    representsCompanies = source['representaEmpresas'] == true;
    pensionDetail.text = _readPayloadString(
      source['detalleRenta'],
      'NO APLICA',
    );
    companyName.text = _readPayloadString(source['nombreEmpresa'], 'NO APLICA');
  }

  Map<String, dynamic> toJson() {
    return {
      'recibeRenta': receivesPension,
      'detalleRenta': pensionDetail.text.trim(),
      'compromisoMatrimonio': marriageCommitment,
      'representaEmpresas': representsCompanies,
      'nombreEmpresa': companyName.text.trim(),
    };
  }

  void dispose() {
    pensionDetail.dispose();
    companyName.dispose();
  }
}

class _AddressDraft {
  String houseType = 'OTRO';
  LatLng? location;
  String? mapImageBase64;
  final mapKey = GlobalKey();
  final street = TextEditingController();
  final zone = TextEditingController();
  final houseNumber = TextEditingController();
  final building = TextEditingController();
  final floor = TextEditingController();
  final department = TextEditingController();
  final references = TextEditingController();
  final cellPhone = TextEditingController();
  final referencePhone = TextEditingController();

  void reset() {
    houseType = 'OTRO';
    location = null;
    mapImageBase64 = null;
    street.clear();
    zone.clear();
    houseNumber.clear();
    building.clear();
    floor.clear();
    department.clear();
    references.clear();
    cellPhone.clear();
    referencePhone.clear();
  }

  void loadFromJson(Map<String, dynamic> source) {
    houseType = _readPayloadString(source['tipoVivienda'], 'OTRO');
    final latitude = _readPayloadDouble(source['latitud']);
    final longitude = _readPayloadDouble(source['longitud']);
    location = latitude == null || longitude == null
        ? null
        : LatLng(latitude, longitude);
    mapImageBase64 = _readPayloadString(source['mapaImagenPngBase64']);
    street.text = _readPayloadString(source['calleAvenida']);
    zone.text = _readPayloadString(source['barrioZona']);
    houseNumber.text = _readPayloadString(source['numeroDomicilio']);
    building.text = _readPayloadString(source['edificio']);
    floor.text = _readPayloadString(source['piso']);
    department.text = _readPayloadString(source['departamento']);
    references.text = _readPayloadString(source['referencias']);
    cellPhone.text = _readPayloadString(source['telefonoCelular']);
    referencePhone.text = _readPayloadString(source['telefonoReferencia']);
  }

  Map<String, dynamic> toJson() {
    return {
      'calleAvenida': street.text.trim(),
      'barrioZona': zone.text.trim(),
      'numeroDomicilio': houseNumber.text.trim(),
      'tipoVivienda': houseType,
      'edificio': building.text.trim(),
      'piso': floor.text.trim(),
      'departamento': department.text.trim(),
      'referencias': references.text.trim(),
      'telefonoCelular': cellPhone.text.trim(),
      'telefonoReferencia': referencePhone.text.trim(),
      'latitud': location?.latitude,
      'longitud': location?.longitude,
      'mapaImagenPngBase64': mapImageBase64 ?? '',
    };
  }

  void dispose() {
    street.dispose();
    zone.dispose();
    houseNumber.dispose();
    building.dispose();
    floor.dispose();
    department.dispose();
    references.dispose();
    cellPhone.dispose();
    referencePhone.dispose();
  }
}

class _CityHallRelativeDraft {
  _CityHallRelativeDraft();

  final relationship = TextEditingController();
  final fullName = TextEditingController();
  final jobTitle = TextEditingController();
  final unit = TextEditingController();

  factory _CityHallRelativeDraft.fromJson(Map<String, dynamic> source) {
    final draft = _CityHallRelativeDraft();
    draft.relationship.text = _readPayloadString(source['parentesco']);
    draft.fullName.text = _readPayloadString(source['nombreCompleto']);
    draft.jobTitle.text = _readPayloadString(source['cargo']);
    draft.unit.text = _readPayloadString(source['unidad']);

    return draft;
  }

  Map<String, dynamic> toJson() {
    return {
      'parentesco': relationship.text.trim(),
      'nombreCompleto': fullName.text.trim(),
      'cargo': jobTitle.text.trim(),
      'unidad': unit.text.trim(),
    };
  }

  void dispose() {
    relationship.dispose();
    fullName.dispose();
    jobTitle.dispose();
    unit.dispose();
  }
}

Future<void> _downloadSwornDeclarationPdf(
  BuildContext context,
  SwornDeclarationRecord record,
) async {
  try {
    final pdfBytes = await dependencies.swornDeclarationsApiService
        .downloadDeclarationPdf(id: record.id);

    await downloadFile(
      fileName: _buildSwornDeclarationFilename(record),
      bytes: pdfBytes,
      mimeType: 'application/pdf',
    );
  } catch (_) {
    if (context.mounted) {
      AppAlert.showError(context, 'No fue posible generar el PDF.');
    }
  }
}

Map<String, dynamic> _readPayloadMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return const {};
}

List<Map<String, dynamic>> _readPayloadList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value.map(_readPayloadMap).toList(growable: false);
}

String _readPayloadString(Object? value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }

  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

double? _readPayloadDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value);
  }

  return null;
}

// ignore: unused_element
Future<Uint8List> _buildSwornDeclarationPdf(
  SwornDeclarationRecord record,
) async {
  final document = pw.Document();
  final templateBytes = (await rootBundle.load(
    'assets/templates/declaracion_jurada.pdf',
  )).buffer.asUint8List();
  final templatePages = <_TemplatePageImage>[];

  await for (final page in Printing.raster(templateBytes, dpi: 144)) {
    templatePages.add(
      _TemplatePageImage(
        image: pw.MemoryImage(await page.toPng()),
        format: PdfPageFormat(
          page.width * PdfPageFormat.inch / 144,
          page.height * PdfPageFormat.inch / 144,
        ),
      ),
    );
  }

  final pages = templatePages.isEmpty
      ? [const _TemplatePageImage(image: null, format: PdfPageFormat.a4)]
      : templatePages;
  const outputPageCount = 6;

  for (var pageIndex = 0; pageIndex < outputPageCount; pageIndex++) {
    final template =
        pages[pageIndex < pages.length ? pageIndex : pages.length - 1];
    final overlay = switch (pageIndex) {
      0 => _buildPdfPageOneOverlay(record),
      1 => _buildPdfPageTwoOverlay(record),
      2 => <pw.Widget>[],
      3 => _buildPdfPageFourOverlay(record),
      4 => _buildPdfPageFiveOverlay(record),
      5 => _buildPdfPageSixOverlay(record),
      _ => <pw.Widget>[],
    };

    document.addPage(
      pw.Page(
        pageFormat: template.format,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            if (template.image != null)
              pw.Positioned.fill(
                child: pw.Image(template.image!, fit: pw.BoxFit.fill),
              ),
            ..._buildPdfHeaderOverlay(record, pageIndex + 1, outputPageCount),
            ...overlay,
          ],
        ),
      ),
    );
  }

  return document.save();
}

List<pw.Widget> _buildPdfHeaderOverlay(
  SwornDeclarationRecord record,
  int page,
  int totalPages,
) {
  final dateText = _formatSpanishDate(record.createdAt);
  final code = _buildSwornDeclarationCode(record);

  return [
    _pdfErase(34, 110, 140, 12),
    _pdfText(36, 111, dateText, size: 7, italic: true),
    _pdfErase(285, 110, 160, 12),
    _pdfText(286, 111, code, size: 7, italic: true),
    _pdfErase(452, 110, 82, 12),
    _pdfText(455, 111, 'Pagina $page de $totalPages', size: 7, italic: true),
    _pdfErase(83, 793, 116, 10),
    _pdfText(84, 794, dateText, size: 6, italic: true),
    _pdfErase(423, 793, 78, 10),
    _pdfText(425, 794, 'Pagina $page de $totalPages', size: 6, italic: true),
  ];
}

List<pw.Widget> _buildPdfPageOneOverlay(SwornDeclarationRecord record) {
  final relatives = _relativeRows(record);

  return [
    _pdfText(91, 229, record.employeeFullName, size: 6.2),
    _pdfText(316, 229, record.employeeCi, size: 6.2),
    _pdfText(386, 229, 'Sin dato', size: 6.2),
    _pdfText(145, 252, 'Sin dato', size: 6.2),
    _pdfText(319, 252, 'Sin dato', size: 6.2),
    _pdfText(137, 275, record.employeeOffice, size: 6.2),
    _pdfText(88, 297, record.employeeJobTitle, size: 6.2),
    _pdfText(228, 297, record.employeeItemNumber, size: 6.2),
    _pdfText(386, 297, 'Sin dato', size: 6.2),
    ..._pdfRelativeGroup(relatives, const ['ESPOSO(A)'], [371]),
    ..._pdfRelativeGroup(relatives, const ['UNION LIBRE'], [441]),
    ..._pdfRelativeGroup(relatives, const ['DIVORCIADO(A)'], [510]),
    ..._pdfRelativeGroup(relatives, const ['SEPARADO(A)'], [579]),
    ..._pdfRelativeGroup(
      relatives,
      const ['PADRE O MADRE DE LOS HIJOS'],
      [649],
    ),
    ..._pdfRelativeGroup(relatives, const ['PADRES'], [719, 741]),
  ];
}

List<pw.Widget> _buildPdfPageTwoOverlay(SwornDeclarationRecord record) {
  final relatives = _relativeRows(record);

  return [
    ..._pdfRelativeGroup(relatives, const ['HERMANOS'], [194]),
    ..._pdfRelativeGroup(relatives, const ['HIJOS'], [252]),
    ..._pdfRelativeGroup(relatives, const ['TIOS'], [323, 344, 365, 386]),
    ..._pdfRelativeGroup(relatives, const ['PRIMOS'], [470, 491]),
    ..._pdfRelativeGroup(relatives, const ['SOBRINOS'], [555, 576]),
    ..._pdfRelativeGroup(relatives, const ['SUEGROS'], [650]),
    ..._pdfRelativeGroup(
      relatives,
      const ['YERNOS - NUERAS', 'YERNOS', 'NUERAS'],
      [719],
    ),
    ..._pdfRelativeGroup(relatives, const ['CUNADOS', 'CUÑADOS'], [792]),
  ];
}

List<pw.Widget> _buildPdfPageFourOverlay(SwornDeclarationRecord record) {
  final doublePerception = _payloadMap(record.payload['doblePercepcion']);
  final sentences = _payloadMap(record.payload['sentenciasProcesos']);
  final perceives = doublePerception['percibeDoblePercepcion'] == true;
  final hasSentences = sentences['tieneSentencias'] == true;
  final hasProcesses = sentences['tieneProcesos'] == true;
  final wasDismissed = sentences['fueDestituido'] == true;

  return [
    _pdfCenteredText(
      296,
      250,
      perceives ? 'SI PERCIBO DOBLE PERCEPCION' : 'NO PERCIBO DOBLE PERCEPCION',
    ),
    _pdfText(
      303,
      337,
      _pdfValue(doublePerception['institucion'], dashIfEmpty: true),
      size: 7,
    ),
    _pdfText(
      303,
      360,
      _pdfValue(doublePerception['funcion'], fallback: 'NINGUNA'),
      size: 7,
    ),
    _pdfText(
      303,
      383,
      _pdfValue(doublePerception['montoPercibe'], dashIfEmpty: true),
      size: 7,
    ),
    _pdfCenteredText(296, 480, hasSentences ? 'SI' : 'NO'),
    if (hasSentences)
      _pdfText(
        55,
        490,
        _pdfValue(sentences['detalleSentencias']),
        size: 6,
        maxWidth: 485,
      ),
    _pdfCenteredText(296, 528, hasProcesses ? 'SI' : 'NINGUNO'),
    if (hasProcesses)
      _pdfText(
        55,
        538,
        _pdfValue(sentences['detalleProcesos']),
        size: 6,
        maxWidth: 485,
      ),
    _pdfCenteredText(296, 574, wasDismissed ? 'SI' : 'NO'),
    if (wasDismissed)
      _pdfText(
        55,
        584,
        _pdfValue(sentences['detalleDestitucion']),
        size: 6,
        maxWidth: 485,
      ),
  ];
}

List<pw.Widget> _buildPdfPageFiveOverlay(SwornDeclarationRecord record) {
  final incompatibilities = _payloadMap(
    record.payload['otrasIncompatibilidades'],
  );
  final receivesPension = incompatibilities['recibeRenta'] == true;
  final marriageCommitment = incompatibilities['compromisoMatrimonio'] == true;
  final representsCompanies = incompatibilities['representaEmpresas'] == true;

  return [
    _pdfCenteredText(296, 224, receivesPension ? 'SI' : 'NO'),
    if (receivesPension)
      _pdfText(
        55,
        234,
        _pdfValue(incompatibilities['detalleRenta']),
        size: 6,
        maxWidth: 485,
      ),
    _pdfCenteredText(296, 294, marriageCommitment ? 'SI' : 'NO'),
    _pdfCenteredText(296, 364, representsCompanies ? 'SI' : 'NO'),
    if (representsCompanies)
      _pdfText(
        55,
        374,
        _pdfValue(incompatibilities['nombreEmpresa']),
        size: 6,
        maxWidth: 485,
      ),
  ];
}

List<pw.Widget> _buildPdfPageSixOverlay(SwornDeclarationRecord record) {
  final address = _payloadMap(record.payload['datosDomiciliarios']);
  final mapImage = _readBase64Png(address['mapaImagenPngBase64']);

  return [
    _pdfText(170, 236, record.employeeFullName, size: 6.5),
    _pdfText(170, 259, record.employeeCi, size: 6.5),
    _pdfText(316, 259, _pdfValue(address['barrioZona']), size: 6.5),
    _pdfText(170, 282, _pdfValue(address['calleAvenida']), size: 6.5),
    _pdfText(371, 282, _pdfValue(address['numeroDomicilio']), size: 6.5),
    _pdfText(485, 282, _pdfValue(address['tipoVivienda']), size: 6.5),
    _pdfText(
      130,
      305,
      _pdfValue(address['telefonoFijo'], fallback: 'S/N'),
      size: 6.5,
    ),
    _pdfText(285, 305, _pdfValue(address['telefonoCelular']), size: 6.5),
    _pdfText(486, 305, _pdfValue(address['telefonoReferencia']), size: 6.5),
    if (mapImage != null)
      pw.Positioned(
        left: 45,
        top: 355,
        child: pw.Image(
          pw.MemoryImage(mapImage),
          width: 482,
          height: 217,
          fit: pw.BoxFit.cover,
        ),
      )
    else
      _pdfText(55, 420, 'No se capturo imagen del mapa.', size: 8),
    _pdfLegalText(55, 606),
    _pdfSignatureLine(45, 732, 'FIRMA'),
    _pdfSignatureLine(357, 732, 'ACLARACION DE FIRMA'),
  ];
}

List<_PdfRelativeRow> _relativeRows(SwornDeclarationRecord record) {
  final raw = record.payload['consanguinidadAfinidad'];

  if (raw is! List) {
    return const [];
  }

  return raw
      .whereType<Map>()
      .map((item) {
        return _PdfRelativeRow(
          relationship: _pdfValue(item['parentesco']).toUpperCase(),
          fullName: [
            _pdfValue(item['apellidoPaterno']),
            _pdfValue(item['apellidoMaterno']),
            _pdfValue(item['nombres']),
          ].where((part) => part.isNotEmpty && part != 'Sin dato').join(' '),
          occupation: _pdfValue(item['ocupacion'], dashIfEmpty: true),
          workplace: _pdfValue(item['lugarTrabajo'], dashIfEmpty: true),
          document: _pdfValue(item['documentoIdentidad'], dashIfEmpty: true),
          deceased: item['fallecido'] == true ? 'SI' : '',
        );
      })
      .toList(growable: false);
}

List<pw.Widget> _pdfRelativeGroup(
  List<_PdfRelativeRow> rows,
  List<String> relationships,
  List<double> yPositions,
) {
  final normalizedRelationships = relationships
      .map((relationship) => relationship.toUpperCase())
      .toSet();
  final matches = rows
      .where((row) => normalizedRelationships.contains(row.relationship))
      .take(yPositions.length)
      .toList(growable: false);
  final widgets = <pw.Widget>[];

  for (var index = 0; index < matches.length; index++) {
    final row = matches[index];
    final y = yPositions[index];

    widgets.addAll([
      _pdfText(52, y, row.fullName, size: 5.7, maxWidth: 142),
      _pdfText(201, y, row.occupation, size: 5.7, maxWidth: 140),
      _pdfText(352, y, row.workplace, size: 5.7, maxWidth: 95),
      _pdfText(456, y, row.document, size: 5.7, maxWidth: 35),
      _pdfText(502, y, row.deceased, size: 5.7, maxWidth: 35),
    ]);
  }

  return widgets;
}

pw.Widget _pdfText(
  double x,
  double y,
  String value, {
  double size = 7,
  double? maxWidth,
  bool italic = false,
}) {
  return pw.Positioned(
    left: x,
    top: y,
    child: pw.SizedBox(
      width: maxWidth,
      child: pw.Text(
        value,
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: size,
          fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        ),
      ),
    ),
  );
}

pw.Widget _pdfCenteredText(double centerX, double y, String value) {
  return pw.Positioned(
    left: centerX - 120,
    top: y,
    child: pw.SizedBox(
      width: 240,
      child: pw.Center(
        child: pw.Text(
          value,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ),
  );
}

pw.Widget _pdfErase(double x, double y, double width, double height) {
  return pw.Positioned(
    left: x,
    top: y,
    child: pw.Container(width: width, height: height, color: PdfColors.white),
  );
}

pw.Widget _pdfLegalText(double x, double y) {
  return _pdfText(
    x,
    y,
    'Tengo conocimiento que de existir falsedad en los datos consignados en el presente formulario, '
    'la misma constituye un delito tipificado en el parrafo II del articulo 345 Bis del Codigo Penal Boliviano, '
    'declaro que la informacion que detallo es fidedigna, caso contrario sere sujeto a responsabilidad penal y administrativa.',
    size: 6.2,
    maxWidth: 490,
  );
}

pw.Widget _pdfSignatureLine(double x, double y, String label) {
  return pw.Positioned(
    left: x,
    top: y,
    child: pw.Column(
      children: [
        pw.Container(width: 160, height: 0.7, color: PdfColors.black),
        pw.SizedBox(height: 5),
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

String _pdfValue(
  Object? value, {
  String fallback = 'Sin dato',
  bool dashIfEmpty = false,
}) {
  if (value == null) {
    return dashIfEmpty ? '----------------' : fallback;
  }

  final text = value.toString().trim();

  if (text.isEmpty || text.toUpperCase() == 'NO APLICA') {
    return dashIfEmpty ? '----------------' : fallback;
  }

  return text;
}

String _buildSwornDeclarationCode(SwornDeclarationRecord record) {
  return 'DJ-${record.id}-${record.employeeCi}'.replaceAll(RegExp(r'\\s+'), '');
}

String _formatSpanishDate(DateTime date) {
  const months = [
    'ENERO',
    'FEBRERO',
    'MARZO',
    'ABRIL',
    'MAYO',
    'JUNIO',
    'JULIO',
    'AGOSTO',
    'SEPTIEMBRE',
    'OCTUBRE',
    'NOVIEMBRE',
    'DICIEMBRE',
  ];
  final local = date.toLocal();

  return '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]} DE ${local.year}';
}

Map<String, dynamic> _payloadMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return const {};
}

Uint8List? _readBase64Png(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}

String _buildSwornDeclarationFilename(SwornDeclarationRecord record) {
  final safeCi = record.employeeCi.trim().isEmpty
      ? record.id.toString()
      : record.employeeCi.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

  return 'DJ-${record.id}-$safeCi.pdf';
}

class _PdfRelativeRow {
  const _PdfRelativeRow({
    required this.relationship,
    required this.fullName,
    required this.occupation,
    required this.workplace,
    required this.document,
    required this.deceased,
  });

  final String relationship;
  final String fullName;
  final String occupation;
  final String workplace;
  final String document;
  final String deceased;
}

class _TemplatePageImage {
  const _TemplatePageImage({required this.image, required this.format});

  final pw.ImageProvider? image;
  final PdfPageFormat format;
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year.toString().padLeft(4, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _humanizeKey(String key) {
  final words = key
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ')
      .trim();

  if (words.isEmpty) {
    return key;
  }

  return words.substring(0, 1).toUpperCase() + words.substring(1);
}

String _formatPayloadLeaf(Object? value) {
  if (value == null) {
    return 'Sin dato';
  }

  if (value is bool) {
    return value ? 'SI' : 'NO';
  }

  if (value is List) {
    return value.isEmpty ? 'Sin registros' : '${value.length} registro(s)';
  }

  if (value is Map) {
    return value.isEmpty ? 'Sin dato' : '${value.length} campo(s)';
  }

  final text = value.toString().trim();
  return text.isEmpty ? 'Sin dato' : text;
}
