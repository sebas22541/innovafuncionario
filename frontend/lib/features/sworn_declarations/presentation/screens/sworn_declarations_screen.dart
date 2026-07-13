import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
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
      await dependencies.swornDeclarationsApiService.createDeclaration(
        managementYear: DateTime.now().year,
        payload: _buildPayload(),
      );

      if (!mounted) {
        return;
      }

      AppAlert.showSuccess(
        context,
        'La declaracion jurada fue enviada para revision.',
        title: 'Declaracion enviada',
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
      'consanguinidadAfinidad':
          _relatives.map((relative) => relative.toJson()).toList(),
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
                                ? 'Finalizar'
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
  State<_IncompatibilitiesStep> createState() =>
      _IncompatibilitiesStepState();
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
            child: FlutterMap(
              options: MapOptions(
                initialCenter: selected ?? _cochabambaCenter,
                initialZoom: 13,
                onTap: (_, point) => setState(() {
                  widget.draft.location = point;
                }),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.innova.funcionario.cochabamba.bo',
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
        _TextInput(
          controller: draft.firstLastName,
          label: 'Apellido paterno',
        ),
        _TextInput(
          controller: draft.secondLastName,
          label: 'Apellido materno',
        ),
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
                _DeclarationListTile(record: record, onTap: () => onOpen(record)),
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
              SizedBox(width: 110, child: _DeclarationStatusBadge(record.status)),
              const SizedBox(width: 52, child: Icon(Icons.visibility_outlined)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeclarationListTile extends StatelessWidget {
  const _DeclarationListTile({required this.record, required this.onTap});

  final SwornDeclarationRecord record;
  final VoidCallback onTap;

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
                ],
              ),
              const SizedBox(height: 6),
              Text('CI ${record.employeeCi} - Gestion ${record.managementYear}'),
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
  });

  final List<SwornDeclarationRecord> records;
  final bool isLoading;
  final VoidCallback onRefresh;

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
              _SummaryRow(label: 'Fecha', value: _formatDateTime(record.createdAt)),
              if (record.reviewedByName.isNotEmpty) ...[
                const Divider(height: 22),
                _SummaryRow(label: 'Revisado por', value: record.reviewedByName),
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
  String relationship = 'ESPOSO(A)';
  bool deceased = false;
  final names = TextEditingController();
  final firstLastName = TextEditingController();
  final secondLastName = TextEditingController();
  final identityDocument = TextEditingController();
  final occupation = TextEditingController();
  final workplace = TextEditingController();

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
  final relationship = TextEditingController();
  final fullName = TextEditingController();
  final jobTitle = TextEditingController();
  final unit = TextEditingController();

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
