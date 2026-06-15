import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../auth/domain/entities/cargo_option.dart';
import '../../../auth/domain/entities/office_option.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _cisController = TextEditingController();
  List<OfficeOption> _offices = const [];
  List<CargoOption> _cargos = const [];
  Set<int> _selectedOfficeIds = {};
  Set<String> _selectedCargoCodes = {};
  Set<String> _selectedTipos = {};
  bool _sendToAll = true;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadReferences();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _cisController.dispose();
    super.dispose();
  }

  Future<void> _loadReferences() async {
    try {
      final results = await Future.wait([
        dependencies.authApiService.fetchOffices(),
        dependencies.authApiService.fetchCargos(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _offices = results[0] as List<OfficeOption>;
        _cargos = results[1] as List<CargoOption>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
      AppAlert.showError(context, 'No fue posible cargar oficinas y cargos.');
    }
  }

  List<String> get _parsedCis {
    return _cisController.text
        .split(RegExp(r'[\s,;]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  void _setSendToAll(bool value) {
    setState(() {
      _sendToAll = value;
      if (value) {
        _selectedOfficeIds = {};
        _selectedCargoCodes = {};
        _selectedTipos = {};
        _cisController.clear();
      }
    });
  }

  Future<void> _pickOffices() async {
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SelectionSheet<OfficeOption, int>(
        title: 'Seleccionar oficinas',
        items: _offices,
        selectedValues: _selectedOfficeIds,
        valueOf: (office) => office.id,
        titleOf: (office) => office.name,
        subtitleOf: (office) => 'Cod. ${office.code} | Nivel ${office.level}',
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _sendToAll = false;
      _selectedOfficeIds = result;
    });
  }

  Future<void> _pickCargos() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SelectionSheet<CargoOption, String>(
        title: 'Seleccionar cargos',
        items: _cargos,
        selectedValues: _selectedCargoCodes,
        valueOf: (cargo) => cargo.code,
        titleOf: (cargo) => cargo.name,
        subtitleOf: (cargo) => 'Cod. ${cargo.code}',
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _sendToAll = false;
      _selectedCargoCodes = result;
    });
  }

  void _toggleTipo(String tipo) {
    setState(() {
      _sendToAll = false;
      if (_selectedTipos.contains(tipo)) {
        _selectedTipos.remove(tipo);
      } else {
        _selectedTipos.add(tipo);
      }
    });
  }

  Future<void> _sendNotification() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final cis = _parsedCis;
    final hasFilters =
        _selectedOfficeIds.isNotEmpty ||
        _selectedCargoCodes.isNotEmpty ||
        _selectedTipos.isNotEmpty ||
        cis.isNotEmpty;

    if (title.length < 3 || body.length < 3) {
      AppAlert.showWarning(context, 'Escribe un titulo y mensaje validos.');
      return;
    }

    if (!_sendToAll && !hasFilters) {
      AppAlert.showWarning(context, 'Selecciona todos o al menos un filtro.');
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final result = await dependencies.notificationsApiService
          .sendNotification(
            title: title,
            body: body,
            sendToAll: _sendToAll,
            cargoCodigos: _selectedCargoCodes.toList(growable: false),
            oficinaIds: _selectedOfficeIds.toList(growable: false),
            cis: cis,
            tiposVinculo: _selectedTipos.toList(growable: false),
          );

      if (!mounted) {
        return;
      }

      final message =
          result.message ??
          'Enviadas: ${result.sent}. Fallidas: ${result.failed}. Destinatarios: ${result.requested}.';
      AppAlert.showSuccess(context, message);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible enviar la notificacion.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ColoredBox(
      color: AppPalette.cream.withValues(alpha: 0.55),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Enviar notificacion', style: textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Solo se enviara a dispositivos moviles registrados con Firebase.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _titleController,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Titulo',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyController,
                  maxLength: 500,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'Mensaje',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.message_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _sendToAll,
                  onChanged: _setSendToAll,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enviar a todos'),
                  subtitle: const Text(
                    'Ignora filtros y usa todos los tokens moviles activos.',
                  ),
                ),
                const SizedBox(height: 12),
                _FilterActions(
                  officesCount: _selectedOfficeIds.length,
                  cargosCount: _selectedCargoCodes.length,
                  onPickOffices: _pickOffices,
                  onPickCargos: _pickCargos,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tipo in _tipoOptions)
                      FilterChip(
                        label: Text(_tipoLabel(tipo)),
                        selected: _selectedTipos.contains(tipo),
                        onSelected: (_) => _toggleTipo(tipo),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _cisController,
                  onChanged: (_) {
                    if (_sendToAll && _cisController.text.trim().isNotEmpty) {
                      setState(() {
                        _sendToAll = false;
                      });
                    }
                  },
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'CI especificos',
                    hintText: 'Separados por coma, espacio o salto de linea',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendNotification,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_isSending ? 'Enviando...' : 'Enviar'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FilterActions extends StatelessWidget {
  const _FilterActions({
    required this.officesCount,
    required this.cargosCount,
    required this.onPickOffices,
    required this.onPickCargos,
  });

  final int officesCount;
  final int cargosCount;
  final VoidCallback onPickOffices;
  final VoidCallback onPickCargos;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: onPickOffices,
          icon: const Icon(Icons.apartment_rounded),
          label: Text(
            officesCount == 0 ? 'Oficinas' : '$officesCount oficinas',
          ),
        ),
        OutlinedButton.icon(
          onPressed: onPickCargos,
          icon: const Icon(Icons.work_outline_rounded),
          label: Text(cargosCount == 0 ? 'Cargos' : '$cargosCount cargos'),
        ),
      ],
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
    final normalizedQuery = _query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return widget.items;
    }

    return widget.items
        .where((item) {
          final text = '${widget.titleOf(item)} ${widget.subtitleOf(item)}'
              .toLowerCase();

          return text.contains(normalizedQuery);
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
                    child: ListView.separated(
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                        onPressed: () => setState(() => _draftSelected.clear()),
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

const _tipoOptions = ['ITEM', 'EVENTUAL', 'CONSULTOR'];

String _tipoLabel(String value) {
  switch (value) {
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
