import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/excel_exporter.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../infrastructure/services/exit_permits_api_service.dart';

class ExitPermitsScreen extends StatefulWidget {
  const ExitPermitsScreen({
    super.key,
    required this.currentUser,
    this.onPermitSent,
  });

  final AppUser currentUser;
  final VoidCallback? onPermitSent;

  @override
  State<ExitPermitsScreen> createState() => _ExitPermitsScreenState();
}

class ExitPermitRequestsScreen extends StatelessWidget {
  const ExitPermitRequestsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: _ExitPermitApprovalsList(currentUser: currentUser),
    );
  }
}

class MyExitPermitsScreen extends StatelessWidget {
  const MyExitPermitsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: _FuncionarioExitPermitsList(currentUser: currentUser),
    );
  }
}

class _ExitPermitsScreenState extends State<ExitPermitsScreen> {
  @override
  Widget build(BuildContext context) {
    if (widget.currentUser.isAdmin) {
      return _ExitPermitsAdminList(currentUser: widget.currentUser);
    }

    if (widget.currentUser.isExternalUser) {
      return _FuncionarioExitPermitsView(
        currentUser: widget.currentUser,
        onPermitSent: widget.onPermitSent,
      );
    }

    return const Center(
      child: Text('No tienes permisos para gestionar salidas.'),
    );
  }
}

class _FuncionarioExitPermitsView extends StatelessWidget {
  const _FuncionarioExitPermitsView({
    required this.currentUser,
    required this.onPermitSent,
  });

  final AppUser currentUser;
  final VoidCallback? onPermitSent;

  @override
  Widget build(BuildContext context) {
    final isDirector = _isDirectorUser(currentUser);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isDirector) ...[
            _ExitPermitForm(
              currentUser: currentUser,
              onPermitSent: onPermitSent,
            ),
          ],
          if (isDirector) _ExitPermitApprovalsList(currentUser: currentUser),
        ],
      ),
    );
  }
}

class _ExitPermitForm extends StatefulWidget {
  const _ExitPermitForm({
    required this.currentUser,
    required this.onPermitSent,
  });

  final AppUser currentUser;
  final VoidCallback? onPermitSent;

  @override
  State<_ExitPermitForm> createState() => _ExitPermitFormState();
}

class _ExitPermitFormState extends State<_ExitPermitForm> {
  final _formKey = GlobalKey<FormState>();
  final _destinationController = TextEditingController();
  final _descriptionController = TextEditingController();
  ExitPermitReason _reason = ExitPermitReason.work;
  DateTime _permitDate = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _destinationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _permitDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (picked != null) {
      setState(() {
        _permitDate = picked;
      });
    }
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_isSaving || _formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await dependencies.exitPermitsApiService.createExitPermit(
        reason: _reason,
        destination: _destinationController.text.trim(),
        description: _descriptionController.text.trim(),
        permitDate: _permitDate,
      );

      if (!mounted) {
        return;
      }

      _destinationController.clear();
      _descriptionController.clear();
      setState(() {
        _reason = ExitPermitReason.work;
        _permitDate = DateTime.now();
      });
      AppAlert.showSuccess(
        context,
        'Se envio el permiso correctamente.',
        title: 'Permiso enviado',
      );
      widget.onPermitSent?.call();
    } on BackendApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No fue posible guardar el formulario.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
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

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ApplicantSummaryCard(currentUser: widget.currentUser),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Formulario de salida',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Motivo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _ReasonChip(
                        label: ExitPermitReason.work.label,
                        selected: _reason == ExitPermitReason.work,
                        onTap: () => setState(() {
                          _reason = ExitPermitReason.work;
                        }),
                      ),
                      _ReasonChip(
                        label: ExitPermitReason.personal.label,
                        selected: _reason == ExitPermitReason.personal,
                        onTap: () => setState(() {
                          _reason = ExitPermitReason.personal;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _destinationController,
                    decoration: const InputDecoration(
                      labelText: 'Lugar de destino',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if ((value ?? '').trim().length < 2) {
                        return 'Escribe el lugar de destino.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                    minLines: 3,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Fecha del permiso',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _PickerButton(
                    icon: Icons.calendar_month_rounded,
                    label: _formatDate(_permitDate),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isSaving ? 'Guardando...' : 'Mandar permiso',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FuncionarioExitPermitsList extends StatefulWidget {
  const _FuncionarioExitPermitsList({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_FuncionarioExitPermitsList> createState() =>
      _FuncionarioExitPermitsListState();
}

class _FuncionarioExitPermitsListState
    extends State<_FuncionarioExitPermitsList> {
  DateTime _selectedDate = DateTime.now();
  List<ExitPermitRecord> _records = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await dependencies.exitPermitsApiService
          .fetchExitPermitsByDate(_selectedDate, onlyMine: true);

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
          _errorMessage = 'No fue posible cargar tus salidas.';
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

  @override
  Widget build(BuildContext context) {
    final isDirector = _isDirectorUser(widget.currentUser);

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
                  'Mis solicitudes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!isDirector)
                  _PickerButton(
                    icon: Icons.calendar_month_rounded,
                    label: _formatDate(_selectedDate),
                    onTap: _pickDate,
                  ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              Text(_errorMessage!)
            else if (_records.isEmpty)
              const Text('No tienes salidas registradas en esta fecha.')
            else
              Column(
                children: [
                  for (final record in _records) ...[
                    _MyExitPermitCard(
                      record: record,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ExitPermitApprovalsList extends StatefulWidget {
  const _ExitPermitApprovalsList({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_ExitPermitApprovalsList> createState() =>
      _ExitPermitApprovalsListState();
}

class _ExitPermitApprovalsListState extends State<_ExitPermitApprovalsList> {
  DateTime _selectedDate = DateTime.now();
  List<ExitPermitRecord> _records = const [];
  bool _isLoading = true;
  int? _reviewingId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await dependencies.exitPermitsApiService
          .fetchExitPermitsByDate(_selectedDate);

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
          _errorMessage = 'No fue posible cargar las salidas de tu oficina.';
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

  Future<void> _review(ExitPermitRecord record, ExitPermitStatus status) async {
    if (_reviewingId != null) {
      return;
    }

    setState(() {
      _reviewingId = record.id;
    });

    try {
      await dependencies.exitPermitsApiService.reviewExitPermit(
        id: record.id,
        status: status,
      );

      if (!mounted) {
        return;
      }

      await _load();
      if (!mounted) {
        return;
      }

      if (status == ExitPermitStatus.approved) {
        AppAlert.showSuccess(
          context,
          'Se acepto la solicitud.',
          title: 'Solicitud aceptada',
        );
      } else {
        AppAlert.showWarning(
          context,
          'Se rechazo la solicitud.',
          title: 'Solicitud rechazada',
        );
      }
    } on BackendApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No fue posible revisar la salida.', isError: true);
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

  @override
  Widget build(BuildContext context) {
    final isDirector = _isDirectorUser(widget.currentUser);

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
                  'Solicitudes recibidas',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!isDirector)
                  _PickerButton(
                    icon: Icons.calendar_month_rounded,
                    label: _formatDate(_selectedDate),
                    onTap: _pickDate,
                  ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              Text(_errorMessage!)
            else if (_records.isEmpty)
              Text(
                isDirector
                    ? 'No tienes solicitudes recibidas.'
                    : 'No hay solicitudes recibidas en esta fecha.',
              )
            else
              _ExitPermitOfficeTable(
                records: _records,
                reviewingId: _reviewingId,
                onOpen: (record) => _openReviewDialog(record),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReviewDialog(ExitPermitRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ExitPermitDetailDialog(
        record: record,
        isReviewing: _reviewingId == record.id,
        onApprove: record.status == ExitPermitStatus.pending
            ? () {
                Navigator.of(context).pop();
                _review(record, ExitPermitStatus.approved);
              }
            : null,
        onReject: record.status == ExitPermitStatus.pending
            ? () {
                Navigator.of(context).pop();
                _review(record, ExitPermitStatus.rejected);
              }
            : null,
      ),
    );
  }
}

class _ExitPermitsAdminList extends StatefulWidget {
  const _ExitPermitsAdminList({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_ExitPermitsAdminList> createState() => _ExitPermitsAdminListState();
}

class _ExitPermitsAdminListState extends State<_ExitPermitsAdminList> {
  DateTime _selectedDate = DateTime.now();
  final _searchController = TextEditingController();
  List<ExitPermitRecord> _records = const [];
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  bool get _hasSearch => _searchController.text.trim().isNotEmpty;

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
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await dependencies.exitPermitsApiService
          .fetchExitPermitsByDate(
            _selectedDate,
            query: _searchController.text,
            includeDate: !_hasSearch,
          );

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
          _errorMessage = 'No fue posible cargar las salidas.';
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
      final records = <ExitPermitRecord>[];

      for (final date in _datesInRange(range)) {
        records.addAll(
          await dependencies.exitPermitsApiService.fetchExitPermitsByDate(
            date,
            query: _searchController.text,
          ),
        );
      }

      await exportExcelWorkbook(
        fileName:
            'salidas_${_fileDate(range.start)}_${_fileDate(range.end)}.xlsx',
        sheetName: 'Salidas',
        headers: const [
          'Fecha permiso',
          'Funcionario',
          'CI',
          'Item',
          'Cargo',
          'Oficina',
          'Motivo',
          'Estado',
          'Destino',
          'Descripcion',
          'Hora salida',
          'Hora llegada',
          'Escaneo salida por',
          'Escaneo llegada por',
          'Aprobado/Revisado por',
          'Fecha aprobacion',
          'Fecha solicitud',
          'Ultima actualizacion',
        ],
        rows: [
          for (final record in records)
            [
              _formatDate(record.permitDate),
              record.applicantFullName,
              record.applicantCi,
              record.applicantItemNumber,
              record.applicantJobTitle,
              record.applicantOffice,
              record.reason.label,
              record.status.label,
              record.destination,
              record.description,
              record.startTime.isEmpty ? 'Pendiente' : record.startTime,
              record.arrivalTime.isEmpty ? 'Pendiente' : record.arrivalTime,
              record.departureScannerName,
              record.arrivalScannerName,
              record.approvedByName,
              record.approvedAt == null
                  ? ''
                  : _formatDateTime(record.approvedAt!),
              _formatDateTime(record.createdAt),
              _formatDateTime(record.updatedAt),
            ],
        ],
      );

      if (mounted) {
        AppAlert.showSuccess(context, 'Excel de salidas generado.');
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible exportar salidas.');
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
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _hasSearch
                        ? 'Historial de salidas del usuario'
                        : 'Solicitudes de salida del dia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (!_hasSearch)
                    _PickerButton(
                      icon: Icons.calendar_month_rounded,
                      label: _formatDate(_selectedDate),
                      onTap: _pickDate,
                    ),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoading || _isExporting ? null : _exportExcel,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.table_view_rounded),
                    label: Text(
                      _isExporting ? 'Exportando...' : 'Exportar Excel',
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'CI o nombre',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () {
                            _searchController.clear();
                            _load();
                          },
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Limpiar filtro'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: Card(child: _buildTable(context))),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    if (_records.isEmpty) {
      return Center(
        child: Text(
          _hasSearch
              ? 'No se encontraron salidas para ese CI o nombre.'
              : 'No hay salidas registradas en esta fecha.',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              border: Border.all(color: AppPalette.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Nombre completo',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 92,
                  child: Text(
                    'CI',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 104,
                  child: Text(
                    'Fecha',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: 12),
                Text('Estado', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }

        final record = _records[index - 1];

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openReadOnlyDialog(record),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                border: Border.all(color: AppPalette.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      record.applicantFullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 92,
                    child: Text(
                      record.applicantCi,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 104,
                    child: Text(
                      _formatDate(record.permitDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _StatusBadge(status: record.status),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openReadOnlyDialog(ExitPermitRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ExitPermitDetailDialog(
        record: record,
        isReviewing: false,
        onApprove: null,
        onReject: null,
      ),
    );
  }
}

class _MyExitPermitCard extends StatelessWidget {
  const _MyExitPermitCard({
    required this.record,
  });

  final ExitPermitRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.orangeSoft,
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
                  '${record.reason.label} - ${record.destination}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusBadge(status: record.status),
            ],
          ),
          const SizedBox(height: 10),
          _SummaryRow(label: 'Fecha', value: _formatDate(record.permitDate)),
          _SummaryRow(label: 'Salida', value: _formatDepartureTime(record)),
          _SummaryRow(label: 'Llegada', value: _formatArrivalTime(record)),
          _SummaryRow(label: 'Descripcion', value: record.description),
          if (record.status == ExitPermitStatus.approved) ...[
            const SizedBox(height: 10),
            Text(
              _approvedPermitHint(record),
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExitPermitOfficeTable extends StatelessWidget {
  const _ExitPermitOfficeTable({
    required this.records,
    required this.reviewingId,
    required this.onOpen,
  });

  final List<ExitPermitRecord> records;
  final int? reviewingId;
  final ValueChanged<ExitPermitRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppPalette.orangeSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  'Nombre completo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Text(
                  'Fecha',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 12),
              Text('Estado', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final record in records) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: reviewingId == null ? () => onOpen(record) : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppPalette.line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.applicantFullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: Text(
                        _formatDate(record.permitDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _StatusBadge(status: record.status),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ExitPermitDetailDialog extends StatelessWidget {
  const _ExitPermitDetailDialog({
    required this.record,
    required this.isReviewing,
    required this.onApprove,
    required this.onReject,
  });

  final ExitPermitRecord record;
  final bool isReviewing;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Solicitud de salida')),
          _StatusBadge(status: record.status),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryRow(label: 'Nombre', value: record.applicantFullName),
            _SummaryRow(label: 'CI', value: record.applicantCi),
            _SummaryRow(label: 'Item', value: record.applicantItemNumber),
            _SummaryRow(label: 'Cargo', value: record.applicantJobTitle),
            _SummaryRow(label: 'Oficina', value: record.applicantOffice),
            const Divider(height: 22),
            _SummaryRow(label: 'Motivo', value: record.reason.label),
            _SummaryRow(label: 'Destino', value: record.destination),
            _SummaryRow(label: 'Descripcion', value: record.description),
            _SummaryRow(label: 'Fecha', value: _formatDate(record.permitDate)),
            _SummaryRow(label: 'Salida', value: _formatDepartureTime(record)),
            _SummaryRow(label: 'Llegada', value: _formatArrivalTime(record)),
            _SummaryRow(
              label: 'Escaneo salida',
              value: record.departureScannerName,
            ),
            _SummaryRow(
              label: 'Escaneo llegada',
              value: record.arrivalScannerName,
            ),
            _SummaryRow(label: 'Revisado por', value: record.approvedByName),
          ],
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

class _ApplicantSummaryCard extends StatelessWidget {
  const _ApplicantSummaryCard({required this.currentUser});

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
              'Datos del solicitante',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _SummaryRow(label: 'Nombre', value: currentUser.fullName),
            _SummaryRow(label: 'Numero de item', value: currentUser.numeroItem),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ExitPermitStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ExitPermitStatus.approved => Colors.green.shade700,
      ExitPermitStatus.rejected => Colors.red.shade700,
      ExitPermitStatus.pending => AppPalette.orange,
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
            width: 118,
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

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      avatar: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 18,
      ),
      onSelected: (_) => onTap(),
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

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year.toString().padLeft(4, '0')}';
}

String _formatDepartureTime(ExitPermitRecord record) {
  final departure = record.startTime.trim();

  return departure.isEmpty ? 'pendiente' : departure;
}

String _formatArrivalTime(ExitPermitRecord record) {
  final arrival = record.arrivalTime.trim();

  return arrival.isEmpty ? 'pendiente' : arrival;
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

String _approvedPermitHint(ExitPermitRecord record) {
  if (record.startTime.trim().isEmpty) {
    return 'Permiso aprobado. Registra la salida con el QR de tu credencial.';
  }

  if (record.arrivalTime.trim().isEmpty) {
    return 'Salida registrada. Registra la llegada con el QR de tu credencial.';
  }

  return 'Salida y llegada registradas por QR.';
}

bool _isDirectorUser(AppUser user) {
  final cargo = user.effectiveCargo
      .toLowerCase()
      .replaceAll('ÃƒÂ¡', 'a')
      .replaceAll('ÃƒÂ©', 'e')
      .replaceAll('ÃƒÂ­', 'i')
      .replaceAll('ÃƒÂ³', 'o')
      .replaceAll('ÃƒÂº', 'u');

  return cargo.contains('director') || cargo.contains('direcctor');
}
