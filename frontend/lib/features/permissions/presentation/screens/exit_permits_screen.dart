import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../infrastructure/services/exit_permits_api_service.dart';

class ExitPermitsScreen extends StatefulWidget {
  const ExitPermitsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<ExitPermitsScreen> createState() => _ExitPermitsScreenState();
}

class _ExitPermitsScreenState extends State<ExitPermitsScreen> {
  @override
  Widget build(BuildContext context) {
    if (widget.currentUser.isAdmin) {
      return _ExitPermitsAdminList(currentUser: widget.currentUser);
    }

    if (widget.currentUser.isExternalUser) {
      return _FuncionarioExitPermitsView(currentUser: widget.currentUser);
    }

    return const Center(
      child: Text('No tienes permisos para gestionar salidas.'),
    );
  }
}

class _FuncionarioExitPermitsView extends StatelessWidget {
  const _FuncionarioExitPermitsView({required this.currentUser});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    final isBoss = _isBossUser(currentUser);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExitPermitForm(currentUser: currentUser),
          if (isBoss) ...[
            const SizedBox(height: 18),
            _ExitPermitApprovalsList(currentUser: currentUser),
          ],
        ],
      ),
    );
  }
}

class _ExitPermitForm extends StatefulWidget {
  const _ExitPermitForm({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_ExitPermitForm> createState() => _ExitPermitFormState();
}

class _ExitPermitFormState extends State<_ExitPermitForm> {
  final _formKey = GlobalKey<FormState>();
  final _destinationController = TextEditingController();
  final _descriptionController = TextEditingController();
  ExitPermitReason _reason = ExitPermitReason.work;
  DateTime _permitDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay? _endTime;
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

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );

    if (picked != null) {
      setState(() {
        _startTime = picked;
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() {
        _endTime = picked;
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
        startTime: _formatTimeOfDay(_startTime),
        endTime: _endTime == null ? null : _formatTimeOfDay(_endTime!),
      );

      if (!mounted) {
        return;
      }

      _destinationController.clear();
      _descriptionController.clear();
      setState(() {
        _reason = ExitPermitReason.work;
        _permitDate = DateTime.now();
        _startTime = TimeOfDay.now();
        _endTime = null;
      });
      _showMessage('Formulario de salida guardado.');
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
                    'Tiempo: de horas',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _PickerButton(
                        icon: Icons.schedule_rounded,
                        label: 'Inicio ${_formatTimeOfDay(_startTime)}',
                        onTap: _pickStartTime,
                      ),
                      _PickerButton(
                        icon: Icons.timer_outlined,
                        label: _endTime == null
                            ? 'Final pendiente'
                            : 'Final ${_formatTimeOfDay(_endTime!)}',
                        onTap: _pickEndTime,
                      ),
                      if (_endTime != null)
                        _PickerButton(
                          icon: Icons.close_rounded,
                          label: 'Quitar final',
                          onTap: () => setState(() {
                            _endTime = null;
                          }),
                        ),
                    ],
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
                        _isSaving ? 'Guardando...' : 'Guardar salida',
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

class _ExitPermitApprovalsList extends StatefulWidget {
  const _ExitPermitApprovalsList({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_ExitPermitApprovalsList> createState() =>
      _ExitPermitApprovalsListState();
}

class _ExitPermitApprovalsListState extends State<_ExitPermitApprovalsList> {
  List<ExitPermitRecord> _records = const [];
  bool _isLoading = true;
  int? _reviewingId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await dependencies.exitPermitsApiService
          .fetchPendingExitPermits();

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
          _errorMessage = 'No fue posible cargar las salidas pendientes.';
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

      setState(() {
        _records = _records
            .where((currentRecord) => currentRecord.id != record.id)
            .toList(growable: false);
      });
      _showMessage(
        status == ExitPermitStatus.approved
            ? 'Salida aprobada.'
            : 'Salida rechazada.',
      );
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Salidas por aprobar',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Actualizar',
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
              const Text('No hay salidas pendientes de tu oficina.')
            else
              Column(
                children: [
                  for (final record in _records) ...[
                    _ExitPermitReviewCard(
                      record: record,
                      isReviewing: _reviewingId == record.id,
                      onApprove: () =>
                          _review(record, ExitPermitStatus.approved),
                      onReject: () =>
                          _review(record, ExitPermitStatus.rejected),
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

class _ExitPermitsAdminList extends StatefulWidget {
  const _ExitPermitsAdminList({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_ExitPermitsAdminList> createState() => _ExitPermitsAdminListState();
}

class _ExitPermitsAdminListState extends State<_ExitPermitsAdminList> {
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
                    'Salidas del dia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
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
      return const Center(
        child: Text('No hay salidas registradas en esta fecha.'),
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(AppPalette.orangeSoft),
            columns: const [
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Hora')),
              DataColumn(label: Text('Motivo')),
              DataColumn(label: Text('Solicitante')),
              DataColumn(label: Text('CI')),
              DataColumn(label: Text('Item')),
              DataColumn(label: Text('Cargo')),
              DataColumn(label: Text('Oficina')),
              DataColumn(label: Text('Destino')),
              DataColumn(label: Text('Descripcion')),
              DataColumn(label: Text('Revisado por')),
            ],
            rows: [
              for (final record in _records)
                DataRow(
                  cells: [
                    DataCell(_StatusBadge(status: record.status)),
                    DataCell(Text(_formatTimeRange(record))),
                    DataCell(Text(record.reason.label)),
                    DataCell(
                      _ConstrainedCell(record.applicantFullName, width: 180),
                    ),
                    DataCell(Text(record.applicantCi)),
                    DataCell(Text(record.applicantItemNumber)),
                    DataCell(
                      _ConstrainedCell(record.applicantJobTitle, width: 160),
                    ),
                    DataCell(
                      _ConstrainedCell(record.applicantOffice, width: 190),
                    ),
                    DataCell(_ConstrainedCell(record.destination, width: 190)),
                    DataCell(_ConstrainedCell(record.description, width: 240)),
                    DataCell(
                      _ConstrainedCell(record.approvedByName, width: 180),
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

class _ExitPermitReviewCard extends StatelessWidget {
  const _ExitPermitReviewCard({
    required this.record,
    required this.isReviewing,
    required this.onApprove,
    required this.onReject,
  });

  final ExitPermitRecord record;
  final bool isReviewing;
  final VoidCallback onApprove;
  final VoidCallback onReject;

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
                  record.applicantFullName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusBadge(status: record.status),
            ],
          ),
          const SizedBox(height: 10),
          _SummaryRow(label: 'CI', value: record.applicantCi),
          _SummaryRow(label: 'Item', value: record.applicantItemNumber),
          _SummaryRow(label: 'Cargo', value: record.applicantJobTitle),
          _SummaryRow(label: 'Oficina', value: record.applicantOffice),
          const Divider(height: 22),
          _SummaryRow(label: 'Motivo', value: record.reason.label),
          _SummaryRow(label: 'Destino', value: record.destination),
          _SummaryRow(label: 'Descripcion', value: record.description),
          _SummaryRow(label: 'Fecha', value: _formatDate(record.permitDate)),
          _SummaryRow(label: 'Tiempo', value: _formatTimeRange(record)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
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
              OutlinedButton.icon(
                onPressed: isReviewing ? null : onReject,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Rechazar'),
              ),
            ],
          ),
        ],
      ),
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
            _SummaryRow(label: 'CI', value: currentUser.ci),
            _SummaryRow(label: 'Numero de item', value: currentUser.numeroItem),
            _SummaryRow(label: 'Cargo', value: currentUser.cargo),
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

class _ConstrainedCell extends StatelessWidget {
  const _ConstrainedCell(this.text, {required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text.trim().isEmpty ? '-' : text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year.toString().padLeft(4, '0')}';
}

String _formatTimeOfDay(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

String _formatTimeRange(ExitPermitRecord record) {
  final end = record.endTime.trim().isEmpty ? 'pendiente' : record.endTime;

  return '${record.startTime} - $end';
}

bool _isBossUser(AppUser user) {
  final cargo = user.cargo
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  return cargo.contains('jefe');
}
