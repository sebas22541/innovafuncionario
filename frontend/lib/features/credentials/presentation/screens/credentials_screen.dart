import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../auth/domain/entities/office_option.dart';

class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _officeController = TextEditingController();
  List<AppUser> _users = const [];
  List<OfficeOption> _offices = const [];
  List<AppUser> _results = const [];
  Set<String> _downloadingEmails = const {};
  int? _selectedOfficeId;
  bool _isLoading = true;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _ciController.dispose();
    _officeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        dependencies.authApiService.fetchUsers(
          requesterEmail: widget.currentUser.email,
        ),
        dependencies.authApiService.fetchOffices(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _users = results[0] as List<AppUser>;
        _offices = results[1] as List<OfficeOption>;
        _isLoading = false;
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'No fue posible cargar los datos de credenciales.';
        _isLoading = false;
      });
    }
  }

  void _search() {
    final ciQuery = _ciController.text.trim().toLowerCase();
    final selectedOffice = _selectedOffice();

    setState(() {
      _hasSearched = true;
      _results = _users
          .where((user) {
            final matchesCi =
                ciQuery.isEmpty || user.ci.toLowerCase().contains(ciQuery);
            final matchesOffice =
                selectedOffice == null || _matchesOffice(user, selectedOffice);

            return matchesCi && matchesOffice;
          })
          .toList(growable: false);
    });
  }

  void _clearFilters() {
    setState(() {
      _ciController.clear();
      _officeController.clear();
      _selectedOfficeId = null;
      _results = const [];
      _hasSearched = false;
    });
  }

  Future<void> _openOfficePicker() async {
    final selectedOffice = _selectedOffice();
    final result = await showModalBottomSheet<_OfficePickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _OfficePickerSheet(offices: _offices, selectedOffice: selectedOffice),
    );

    if (!mounted || result == null) {
      return;
    }

    final office = result.office;

    if (office == selectedOffice) {
      return;
    }

    setState(() {
      _selectedOfficeId = office?.id;
      _officeController.text = office?.name ?? '';
    });
  }

  Future<void> _downloadCredential(AppUser user) async {
    if (_downloadingEmails.contains(user.email)) {
      return;
    }

    setState(() {
      _downloadingEmails = {..._downloadingEmails, user.email};
    });

    try {
      final pdfBytes = await dependencies.authApiService.downloadCredentialPdf(
        email: user.email,
      );

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: _buildCredentialFilename(user),
      );
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible descargar la credencial.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingEmails = _downloadingEmails
              .where((email) => email != user.email)
              .toSet();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    'Buscar credenciales',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Filtra por carnet de identidad u oficina para descargar la credencial del funcionario.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 720;

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildCiField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildOfficeField()),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildCiField(),
                          const SizedBox(height: 12),
                          _buildOfficeField(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _search,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Buscar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _clearFilters,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Limpiar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _loadData,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Actualizar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _buildResultsContent(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsContent(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        key: ValueKey('loading'),
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return _CredentialsStateMessage(
        key: const ValueKey('error'),
        icon: Icons.warning_amber_rounded,
        title: 'No se pudieron cargar los datos',
        message: _errorMessage!,
        action: OutlinedButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      );
    }

    if (!_hasSearched) {
      return const _CredentialsStateMessage(
        key: ValueKey('empty-search'),
        icon: Icons.manage_search_rounded,
        title: 'Realiza una busqueda',
        message: 'Ingresa un CI, selecciona una oficina o usa ambos filtros.',
      );
    }

    if (_results.isEmpty) {
      return const _CredentialsStateMessage(
        key: ValueKey('empty-results'),
        icon: Icons.search_off_rounded,
        title: 'Sin resultados',
        message: 'No hay usuarios que coincidan con los filtros aplicados.',
      );
    }

    return Column(
      key: const ValueKey('results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_results.length} resultado${_results.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return _CredentialCardsList(
                users: _results,
                downloadingEmails: _downloadingEmails,
                onDownload: _downloadCredential,
              );
            }

            return _CredentialsTable(
              users: _results,
              downloadingEmails: _downloadingEmails,
              onDownload: _downloadCredential,
            );
          },
        ),
      ],
    );
  }

  Widget _buildCiField() {
    return TextField(
      controller: _ciController,
      decoration: const InputDecoration(
        labelText: 'Buscar por CI',
        hintText: 'Ej. 1234567',
        prefixIcon: Icon(Icons.credit_card_rounded),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
    );
  }

  Widget _buildOfficeField() {
    return TextField(
      key: ValueKey(_selectedOfficeId),
      controller: _officeController,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Oficina',
        hintText: 'Busca y selecciona una oficina',
        prefixIcon: Icon(Icons.account_tree_outlined),
        suffixIcon: Icon(Icons.search_rounded),
      ),
      onTap: _openOfficePicker,
    );
  }

  OfficeOption? _selectedOffice() {
    final selectedOfficeId = _selectedOfficeId;

    if (selectedOfficeId == null) {
      return null;
    }

    for (final office in _offices) {
      if (office.id == selectedOfficeId) {
        return office;
      }
    }

    return null;
  }
}

class _OfficePickerSheet extends StatefulWidget {
  const _OfficePickerSheet({
    required this.offices,
    required this.selectedOffice,
  });

  final List<OfficeOption> offices;
  final OfficeOption? selectedOffice;

  @override
  State<_OfficePickerSheet> createState() => _OfficePickerSheetState();
}

class _OfficePickerSheetState extends State<_OfficePickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalizeOfficeSearchText(_searchController.text);
    final filteredOffices = widget.offices
        .where((office) {
          if (query.isEmpty) {
            return true;
          }

          return _officeTextLooksSimilar(
                _normalizeOfficeSearchText(office.name),
                query,
              ) ||
              _normalizeOfficeSearchText(office.code).contains(query) ||
              office.level.toString().contains(query);
        })
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          20,
          12,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          clipBehavior: Clip.antiAlias,
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Selecciona la oficina',
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
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar oficina',
                      hintText: 'Escribe nombre, codigo o nivel',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: const Icon(Icons.layers_clear_outlined),
                    title: const Text('Todas las oficinas'),
                    onTap: () =>
                        Navigator.of(context).pop(_OfficePickerResult.all()),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: filteredOffices.isEmpty
                        ? const Center(
                            child: Text('No se encontraron oficinas.'),
                          )
                        : ListView.separated(
                            itemCount: filteredOffices.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final office = filteredOffices[index];
                              final isSelected =
                                  widget.selectedOffice?.id == office.id;

                              return InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => Navigator.of(
                                  context,
                                ).pop(_OfficePickerResult.office(office)),
                                child: Ink(
                                  padding: const EdgeInsets.all(14),
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
                                    children: [
                                      Expanded(
                                        child: Text(
                                          office.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          color: AppPalette.orange,
                                        ),
                                    ],
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
      ),
    );
  }
}

class _OfficePickerResult {
  const _OfficePickerResult._(this.office);

  const _OfficePickerResult.all() : this._(null);

  const _OfficePickerResult.office(OfficeOption office) : this._(office);

  final OfficeOption? office;
}

class _CredentialDownloadButton extends StatelessWidget {
  const _CredentialDownloadButton({
    required this.isDownloading,
    required this.onPressed,
    this.compact = false,
  });

  final bool isDownloading;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton.filled(
        onPressed: isDownloading ? null : onPressed,
        style: IconButton.styleFrom(
          backgroundColor: AppPalette.night,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppPalette.blueSoftStrong,
        ),
        tooltip: 'Descargar credencial',
        icon: isDownloading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.download_rounded),
      );
    }

    return ElevatedButton.icon(
      onPressed: isDownloading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.night,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      icon: isDownloading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.download_rounded),
      label: Text(isDownloading ? 'Descargando...' : 'Descargar'),
    );
  }
}

class _CredentialsTable extends StatelessWidget {
  const _CredentialsTable({
    required this.users,
    required this.downloadingEmails,
    required this.onDownload,
  });

  final List<AppUser> users;
  final Set<String> downloadingEmails;
  final ValueChanged<AppUser> onDownload;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.3),
            1: FlexColumnWidth(0.85),
            2: FlexColumnWidth(2.7),
            3: FlexColumnWidth(1.25),
            4: FlexColumnWidth(0.75),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
            horizontalInside: BorderSide(color: AppPalette.line),
          ),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: AppPalette.blueSoft),
              children: [
                _TableHeader('Nombre', style: textTheme.titleSmall),
                _TableHeader('CI', style: textTheme.titleSmall),
                _TableHeader('Oficina', style: textTheme.titleSmall),
                _TableHeader('Cargo', style: textTheme.titleSmall),
                _TableHeader('PDF', style: textTheme.titleSmall),
              ],
            ),
            for (final user in users)
              TableRow(
                children: [
                  _TableCellText(user.fullName),
                  _TableCellText(user.ci),
                  _TableCellText(_resolvedOfficeName(user)),
                  _TableCellText(_resolvedJobTitle(user)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _CredentialDownloadButton(
                        compact: true,
                        isDownloading: downloadingEmails.contains(user.email),
                        onPressed: user.activo ? () => onDownload(user) : null,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CredentialCardsList extends StatelessWidget {
  const _CredentialCardsList({
    required this.users,
    required this.downloadingEmails,
    required this.onDownload,
  });

  final List<AppUser> users;
  final Set<String> downloadingEmails;
  final ValueChanged<AppUser> onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final user in users) ...[
          _CredentialResultTile(
            user: user,
            isDownloading: downloadingEmails.contains(user.email),
            onDownload: user.activo ? () => onDownload(user) : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CredentialResultTile extends StatelessWidget {
  const _CredentialResultTile({
    required this.user,
    required this.isDownloading,
    required this.onDownload,
  });

  final AppUser user;
  final bool isDownloading;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        border: Border.all(color: AppPalette.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.fullName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _CredentialMeta(label: 'CI', value: user.ci),
              _CredentialMeta(
                label: 'Oficina',
                value: _resolvedOfficeName(user),
              ),
              _CredentialMeta(label: 'Cargo', value: _resolvedJobTitle(user)),
            ],
          ),
          const SizedBox(height: 12),
          _CredentialDownloadButton(
            isDownloading: isDownloading,
            onPressed: onDownload,
          ),
        ],
      ),
    );
  }
}

class _CredentialMeta extends StatelessWidget {
  const _CredentialMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value.trim().isEmpty ? '-' : value),
        ],
      ),
    );
  }
}

class _CredentialsStateMessage extends StatelessWidget {
  const _CredentialsStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 46, color: AppPalette.muted),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.value, {required this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _TableCellText extends StatelessWidget {
  const _TableCellText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        value.trim().isEmpty ? '-' : value,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppPalette.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _resolvedOfficeName(AppUser user) {
  final officeName = (user.officeName ?? '').trim().isNotEmpty
      ? user.officeName!.trim()
      : user.unidad.trim();

  return officeName.isEmpty ? 'Sin oficina' : officeName;
}

bool _matchesOffice(AppUser user, OfficeOption office) {
  final effectiveOfficeId = user.hasCommission
      ? user.commissionOfficeId ?? user.officeId
      : user.primaryOfficeId ?? user.officeId;

  if (effectiveOfficeId == office.id) {
    return true;
  }

  final selectedOfficeCode = _normalizeExactOfficeValue(office.code);
  final userOfficeCode = _normalizeExactOfficeValue(user.officeCode ?? '');

  if (selectedOfficeCode.isNotEmpty && userOfficeCode == selectedOfficeCode) {
    return true;
  }

  final selectedOfficeName = _normalizeExactOfficeValue(office.name);
  final userOfficeName = _normalizeExactOfficeValue(
    user.hasCommission
        ? user.commissionOfficeName ?? ''
        : user.primaryOfficeName ?? user.officeName ?? user.unidad,
  );

  return selectedOfficeName.isNotEmpty && userOfficeName == selectedOfficeName;
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

String _normalizeSearchText(String value) {
  return _stripTextAccents(
    value.trim().toLowerCase(),
  ).replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[^a-z0-9 ]'), '');
}

String _normalizeOfficeSearchText(String value) {
  return _normalizeSearchText(value)
      .replaceAll(RegExp(r'\bcomision\b'), ' ')
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

String _normalizeExactOfficeValue(String value) {
  return _stripTextAccents(value.trim().toLowerCase())
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _resolvedJobTitle(AppUser user) {
  final jobTitle = user.cargo.trim();
  return jobTitle.isEmpty ? 'Sin cargo' : jobTitle;
}

String _buildCredentialFilename(AppUser user) {
  final ci = user.ci.trim();
  final fallbackName = user.firstName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final safeId = ci.isNotEmpty
      ? ci
      : (fallbackName.isEmpty ? 'usuario' : fallbackName);

  return 'credencial-$safeId.pdf';
}
