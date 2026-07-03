import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../auth/domain/entities/cargo_option.dart';
import '../../../auth/domain/entities/office_option.dart';

class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  static const int _credentialsPerPage = 10;

  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _officeController = TextEditingController();
  final TextEditingController _cargoController = TextEditingController();
  List<AppUser> _users = const [];
  List<OfficeOption> _offices = const [];
  List<CargoOption> _cargos = const [];
  List<AppUser> _results = const [];
  Set<String> _downloadingEmails = const {};
  Set<String> _updatingPhotoEmails = const {};
  int? _selectedOfficeId;
  String? _selectedCargoCode;
  bool _isLoading = true;
  bool _hasSearched = false;
  int _currentPage = 0;
  String? _errorMessage;

  int get _totalPages =>
      _results.isEmpty ? 1 : ((_results.length - 1) ~/ _credentialsPerPage) + 1;
  int get _safeCurrentPage => _currentPage.clamp(0, _totalPages - 1);
  int get _visibleStartIndex => _results.isEmpty
      ? 0
      : (_safeCurrentPage * _credentialsPerPage).clamp(0, _results.length);
  int get _visibleEndIndex => _results.isEmpty
      ? 0
      : (_visibleStartIndex + _credentialsPerPage).clamp(0, _results.length);
  List<AppUser> get _visibleResults =>
      _results.sublist(_visibleStartIndex, _visibleEndIndex);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _ciController.dispose();
    _officeController.dispose();
    _cargoController.dispose();
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
        dependencies.authApiService.fetchCargos(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _users = results[0] as List<AppUser>;
        _offices = results[1] as List<OfficeOption>;
        _cargos = results[2] as List<CargoOption>;
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
    final query = _normalizeSearchText(_ciController.text);
    final selectedOffice = _selectedOffice();
    final selectedCargo = _selectedCargo();

    if (query.isEmpty && selectedOffice == null && selectedCargo == null) {
      AppAlert.showError(
        context,
        'Ingresa un dato de busqueda, selecciona una oficina o selecciona un cargo.',
      );
      setState(() {
        _hasSearched = false;
        _results = const [];
        _currentPage = 0;
      });
      return;
    }

    setState(() {
      _hasSearched = true;
      _currentPage = 0;
      _results = _users
          .where((user) {
            final matchesQuery =
                query.isEmpty || _userMatchesSearchQuery(user, query);
            final matchesOffice =
                selectedOffice == null || _matchesOffice(user, selectedOffice);
            final matchesCargo =
                selectedCargo == null || _matchesCargo(user, selectedCargo);

            return matchesQuery && matchesOffice && matchesCargo;
          })
          .toList(growable: false);
    });
  }

  void _clearFilters() {
    setState(() {
      _ciController.clear();
      _officeController.clear();
      _cargoController.clear();
      _selectedOfficeId = null;
      _selectedCargoCode = null;
      _results = const [];
      _hasSearched = false;
      _currentPage = 0;
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
      _currentPage = 0;
    });
  }

  Future<void> _openCargoPicker() async {
    final selectedCargo = _selectedCargo();
    final result = await showModalBottomSheet<_CargoPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _CargoPickerSheet(cargos: _cargos, selectedCargo: selectedCargo),
    );

    if (!mounted || result == null) {
      return;
    }

    final cargo = result.cargo;

    if (cargo == selectedCargo) {
      return;
    }

    setState(() {
      _selectedCargoCode = cargo?.code;
      _cargoController.text = cargo?.name ?? '';
      _currentPage = 0;
    });
  }

  Future<void> _downloadCredential(_CredentialPdfDraft draft) async {
    final user = draft.user;

    if (_downloadingEmails.contains(user.email)) {
      return;
    }

    setState(() {
      _downloadingEmails = {..._downloadingEmails, user.email};
    });

    try {
      final pdfBytes = await dependencies.authApiService.downloadCredentialPdf(
        email: user.email,
        nombreCompleto: draft.nombreCompleto,
        primerApellido: draft.primerApellido,
        segundoApellido: draft.segundoApellido,
        tercerApellido: draft.tercerApellido,
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

  Future<void> _changeCredentialPhoto(AppUser user) async {
    if (_updatingPhotoEmails.contains(user.email)) {
      return;
    }

    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    if (file == null) {
      return;
    }

    setState(() {
      _updatingPhotoEmails = {..._updatingPhotoEmails, user.email};
    });

    try {
      final bytes = await file.readAsBytes();
      final updatedUser = await dependencies.authApiService
          .updateCredentialPhoto(
            email: user.email,
            fotoData: base64Encode(bytes),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = _replaceUser(_users, updatedUser);
        _results = _replaceUser(_results, updatedUser);
        _currentPage = _safeCurrentPage;
      });

      AppAlert.showSuccess(context, 'Foto actualizada.');
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible actualizar la foto.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingPhotoEmails = _updatingPhotoEmails
              .where((email) => email != user.email)
              .toSet();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 20,
        isMobile ? 12 : 20,
        isMobile ? 12 : 20,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buscar credenciales',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Filtra por CI, nombre, apellido, usuario, item, cargo u oficina para descargar la credencial del funcionario.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 900;

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildCiField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildOfficeField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildCargoField()),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildCiField(),
                          const SizedBox(height: 12),
                          _buildOfficeField(),
                          const SizedBox(height: 12),
                          _buildCargoField(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final buttons = [
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
                      ];

                      if (constraints.maxWidth < 420) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < buttons.length;
                              index++
                            ) ...[
                              buttons[index],
                              if (index != buttons.length - 1)
                                const SizedBox(height: 10),
                            ],
                          ],
                        );
                      }

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: buttons,
                      );
                    },
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
        message:
            'Ingresa CI, nombre, apellido, cargo, oficina, item o selecciona un filtro.',
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
        _CredentialsPaginationBar(
          currentPage: _safeCurrentPage,
          totalPages: _totalPages,
          totalResults: _results.length,
          startIndex: _visibleStartIndex,
          endIndex: _visibleEndIndex,
          onPrevious: _safeCurrentPage == 0
              ? null
              : () {
                  setState(() {
                    _currentPage = _safeCurrentPage - 1;
                  });
                },
          onNext: _safeCurrentPage >= _totalPages - 1
              ? null
              : () {
                  setState(() {
                    _currentPage = _safeCurrentPage + 1;
                  });
                },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return _CredentialCardsList(
                users: _visibleResults,
                downloadingEmails: _downloadingEmails,
                updatingPhotoEmails: _updatingPhotoEmails,
                onDownload: _downloadCredential,
                onChangePhoto: _changeCredentialPhoto,
              );
            }

            return _CredentialsTable(
              users: _visibleResults,
              downloadingEmails: _downloadingEmails,
              updatingPhotoEmails: _updatingPhotoEmails,
              onDownload: _downloadCredential,
              onChangePhoto: _changeCredentialPhoto,
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
        labelText: 'Busqueda general',
        hintText: 'CI, nombre, apellido, cargo, oficina o item',
        prefixIcon: Icon(Icons.manage_search_rounded),
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

  Widget _buildCargoField() {
    return TextField(
      key: ValueKey(_selectedCargoCode),
      controller: _cargoController,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Cargo',
        hintText: 'Busca y selecciona un cargo',
        prefixIcon: Icon(Icons.badge_outlined),
        suffixIcon: Icon(Icons.search_rounded),
      ),
      onTap: _openCargoPicker,
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

  CargoOption? _selectedCargo() {
    final selectedCargoCode = _selectedCargoCode;

    if (selectedCargoCode == null) {
      return null;
    }

    for (final cargo in _cargos) {
      if (cargo.code == selectedCargoCode) {
        return cargo;
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

  const _OfficePickerResult.office(OfficeOption office) : this._(office);

  final OfficeOption? office;
}

class _CargoPickerSheet extends StatefulWidget {
  const _CargoPickerSheet({required this.cargos, required this.selectedCargo});

  final List<CargoOption> cargos;
  final CargoOption? selectedCargo;

  @override
  State<_CargoPickerSheet> createState() => _CargoPickerSheetState();
}

class _CargoPickerSheetState extends State<_CargoPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalizeSearchText(_searchController.text);
    final filteredCargos = widget.cargos
        .where((cargo) {
          if (query.isEmpty) {
            return true;
          }

          return _normalizeSearchText(cargo.name).contains(query) ||
              _normalizeSearchText(cargo.code).contains(query);
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
                          'Selecciona el cargo',
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
                      labelText: 'Buscar cargo',
                      hintText: 'Escribe cargo o codigo',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredCargos.isEmpty
                        ? const Center(child: Text('No se encontraron cargos.'))
                        : ListView.separated(
                            itemCount: filteredCargos.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final cargo = filteredCargos[index];
                              final isSelected =
                                  widget.selectedCargo?.code == cargo.code;

                              return InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => Navigator.of(
                                  context,
                                ).pop(_CargoPickerResult.cargo(cargo)),
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
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              cargo.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Codigo ${cargo.code}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
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

class _CargoPickerResult {
  const _CargoPickerResult._(this.cargo);

  const _CargoPickerResult.cargo(CargoOption cargo) : this._(cargo);

  final CargoOption? cargo;
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

class _CredentialsPaginationBar extends StatelessWidget {
  const _CredentialsPaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalResults,
    required this.startIndex,
    required this.endIndex,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final int totalResults;
  final int startIndex;
  final int endIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final firstVisible = totalResults == 0 ? 0 : startIndex + 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final summary = Text(
            'Mostrando $firstVisible-$endIndex de $totalResults credenciales',
            textAlign: isCompact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodyMedium,
          );
          final pageLabel = _CredentialsPageLabel(
            currentPage: currentPage,
            totalPages: totalPages,
          );
          final previousButton = OutlinedButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Anterior'),
          );
          final nextButton = OutlinedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Siguiente'),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: 12),
                Center(child: pageLabel),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(width: 150, child: previousButton),
                    SizedBox(width: 150, child: nextButton),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: summary),
              const SizedBox(width: 12),
              previousButton,
              const SizedBox(width: 10),
              pageLabel,
              const SizedBox(width: 10),
              nextButton,
            ],
          );
        },
      ),
    );
  }
}

class _CredentialsPageLabel extends StatelessWidget {
  const _CredentialsPageLabel({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppPalette.orangeSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line),
      ),
      child: Text(
        'Pagina ${currentPage + 1} de $totalPages',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CredentialsTable extends StatelessWidget {
  const _CredentialsTable({
    required this.users,
    required this.downloadingEmails,
    required this.updatingPhotoEmails,
    required this.onDownload,
    required this.onChangePhoto,
  });

  final List<AppUser> users;
  final Set<String> downloadingEmails;
  final Set<String> updatingPhotoEmails;
  final ValueChanged<_CredentialPdfDraft> onDownload;
  final ValueChanged<AppUser> onChangePhoto;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppPalette.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const _CredentialsListHeader(),
          for (final user in users)
            _CredentialEditableRow(
              key: ValueKey(user.email),
              user: user,
              compact: false,
              isDownloading: downloadingEmails.contains(user.email),
              isUpdatingPhoto: updatingPhotoEmails.contains(user.email),
              onDownload: onDownload,
              onChangePhoto: onChangePhoto,
            ),
        ],
      ),
    );
  }
}

class _CredentialCardsList extends StatelessWidget {
  const _CredentialCardsList({
    required this.users,
    required this.downloadingEmails,
    required this.updatingPhotoEmails,
    required this.onDownload,
    required this.onChangePhoto,
  });

  final List<AppUser> users;
  final Set<String> downloadingEmails;
  final Set<String> updatingPhotoEmails;
  final ValueChanged<_CredentialPdfDraft> onDownload;
  final ValueChanged<AppUser> onChangePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final user in users) ...[
          _CredentialEditableRow(
            key: ValueKey(user.email),
            user: user,
            compact: true,
            isDownloading: downloadingEmails.contains(user.email),
            isUpdatingPhoto: updatingPhotoEmails.contains(user.email),
            onDownload: onDownload,
            onChangePhoto: onChangePhoto,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CredentialsListHeader extends StatelessWidget {
  const _CredentialsListHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppPalette.blueSoft,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Text(
        'Datos para credenciales',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _CredentialEditableRow extends StatefulWidget {
  const _CredentialEditableRow({
    super.key,
    required this.user,
    required this.compact,
    required this.isDownloading,
    required this.isUpdatingPhoto,
    required this.onDownload,
    required this.onChangePhoto,
  });

  final AppUser user;
  final bool compact;
  final bool isDownloading;
  final bool isUpdatingPhoto;
  final ValueChanged<_CredentialPdfDraft> onDownload;
  final ValueChanged<AppUser> onChangePhoto;

  @override
  State<_CredentialEditableRow> createState() => _CredentialEditableRowState();
}

class _CredentialEditableRowState extends State<_CredentialEditableRow> {
  late final TextEditingController _nombreController;
  late final TextEditingController _primerApellidoController;
  late final TextEditingController _segundoApellidoController;
  late final TextEditingController _tercerApellidoController;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.user.nombreCompleto);
    _primerApellidoController = TextEditingController(
      text: widget.user.primerApellido,
    );
    _segundoApellidoController = TextEditingController(
      text: widget.user.segundoApellido,
    );
    _tercerApellidoController = TextEditingController(
      text: widget.user.tercerApellido,
    );
  }

  @override
  void didUpdateWidget(covariant _CredentialEditableRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.user.email != widget.user.email) {
      _nombreController.text = widget.user.nombreCompleto;
      _primerApellidoController.text = widget.user.primerApellido;
      _segundoApellidoController.text = widget.user.segundoApellido;
      _tercerApellidoController.text = widget.user.tercerApellido;
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _primerApellidoController.dispose();
    _segundoApellidoController.dispose();
    _tercerApellidoController.dispose();
    super.dispose();
  }

  void _download() {
    widget.onDownload(
      _CredentialPdfDraft(
        user: widget.user,
        nombreCompleto: _nombreController.text.trim(),
        primerApellido: _primerApellidoController.text.trim(),
        segundoApellido: _segundoApellidoController.text.trim(),
        tercerApellido: _tercerApellidoController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CredentialPhotoPreview(
                user: widget.user,
                isUpdating: widget.isUpdatingPhoto,
                onTap: () => widget.onChangePhoto(widget.user),
              ),
              const SizedBox(height: 14),
              _buildEditableFields(context),
              const SizedBox(height: 12),
              _buildMetadata(context),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _CredentialDownloadButton(
                  isDownloading: widget.isDownloading,
                  onPressed: widget.user.activo ? _download : null,
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CredentialPhotoPreview(
                user: widget.user,
                isUpdating: widget.isUpdatingPhoto,
                onTap: () => widget.onChangePhoto(widget.user),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEditableFields(context),
                    const SizedBox(height: 10),
                    _buildMetadata(context),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _CredentialDownloadButton(
                compact: true,
                isDownloading: widget.isDownloading,
                onPressed: widget.user.activo ? _download : null,
              ),
            ],
          );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.compact ? 14 : 16),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        border: widget.compact
            ? Border.all(color: AppPalette.line)
            : const Border(top: BorderSide(color: AppPalette.line)),
        borderRadius: BorderRadius.circular(widget.compact ? 16 : 0),
      ),
      child: content,
    );
  }

  Widget _buildEditableFields(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _CredentialInlineField(
          width: 190,
          controller: _nombreController,
          label: 'Nombres',
        ),
        _CredentialInlineField(
          width: 150,
          controller: _primerApellidoController,
          label: 'Primer apellido',
        ),
        _CredentialInlineField(
          width: 150,
          controller: _segundoApellidoController,
          label: 'Segundo apellido',
        ),
        _CredentialInlineField(
          width: 150,
          controller: _tercerApellidoController,
          label: 'Tercer apellido',
        ),
      ],
    );
  }

  Widget _buildMetadata(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _CredentialMeta(label: 'CI', value: widget.user.ci),
        if (widget.user.celular.trim().isNotEmpty)
          _CredentialMeta(label: 'Celular', value: widget.user.celular),
        _CredentialMeta(
          label: 'Oficina',
          value: _resolvedOfficeName(widget.user),
        ),
        _CredentialMeta(label: 'Cargo', value: _resolvedJobTitle(widget.user)),
        if (widget.user.lugar.trim().isNotEmpty)
          _CredentialMeta(label: 'Lugar', value: widget.user.lugar),
        _CredentialMeta(label: 'Tipo', value: widget.user.tipoVinculo),
        if (widget.user.numeroItem.trim().isNotEmpty)
          _CredentialMeta(label: 'Item', value: widget.user.numeroItem),
        _CredentialMeta(label: 'Estado', value: widget.user.estadoLabel),
      ],
    );
  }
}

class _CredentialInlineField extends StatelessWidget {
  const _CredentialInlineField({
    required this.width,
    required this.controller,
    required this.label,
  });

  final double width;
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

class _CredentialPhotoPreview extends StatelessWidget {
  const _CredentialPhotoPreview({
    required this.user,
    required this.isUpdating,
    required this.onTap,
  });

  final AppUser user;
  final bool isUpdating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cambiar foto',
      child: InkWell(
        onTap: isUpdating ? null : onTap,
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Container(
              width: 112,
              height: 138,
              padding: const EdgeInsets.all(4),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: _CredentialPhotoBorderShape(
                  side: const BorderSide(color: AppPalette.orange, width: 2.2),
                ),
              ),
              child: ClipPath(
                clipper: const _CredentialPhotoClipper(),
                child: _CredentialPdfPhotoImage(
                  user: user,
                  width: 104,
                  height: 130,
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: AppPalette.night,
                foregroundColor: Colors.white,
                child: isUpdating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.photo_camera_outlined, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialPdfPhotoImage extends StatelessWidget {
  const _CredentialPdfPhotoImage({
    required this.user,
    required this.width,
    required this.height,
  });

  final AppUser user;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final photoSource = user.fotoUrl?.trim();
    final photoUri = _tryParseCredentialPhotoUri(photoSource);
    final photoBytes = photoUri == null
        ? _tryDecodeCredentialPhotoBytes(photoSource)
        : null;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * pixelRatio).round();
    final cacheHeight = (height * pixelRatio).round();

    if (photoUri != null) {
      return CachedNetworkImage(
        imageUrl: photoUri.toString(),
        width: width,
        height: height,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        maxWidthDiskCache: cacheWidth,
        maxHeightDiskCache: cacheHeight,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        placeholder: (_, _) =>
            _CredentialPhotoFallback(user: user, width: width, height: height),
        errorWidget: (_, _, _) =>
            _CredentialPhotoFallback(user: user, width: width, height: height),
      );
    }

    if (photoBytes != null) {
      return Image.memory(
        photoBytes,
        width: width,
        height: height,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            _CredentialPhotoFallback(user: user, width: width, height: height),
      );
    }

    return _CredentialPhotoFallback(user: user, width: width, height: height);
  }
}

class _CredentialPhotoFallback extends StatelessWidget {
  const _CredentialPhotoFallback({
    required this.user,
    required this.width,
    required this.height,
  });

  final AppUser user;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final label = user.fullName.trim();

    return Container(
      width: width,
      height: height,
      color: AppPalette.orangeSoft,
      alignment: Alignment.center,
      child: Text(
        label.isEmpty ? 'U' : label.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: AppPalette.orange,
          fontSize: width * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CredentialPhotoClipper extends CustomClipper<Path> {
  const _CredentialPhotoClipper();

  @override
  Path getClip(Size size) {
    return _credentialPhotoPath(size);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CredentialPhotoBorderShape extends ShapeBorder {
  const _CredentialPhotoBorderShape({required this.side});

  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _credentialPhotoPath(rect.size).shift(rect.topLeft);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _credentialPhotoPath(rect.size).shift(rect.topLeft);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = side.toPaint();
    canvas.drawPath(getOuterPath(rect), paint);
  }

  @override
  ShapeBorder scale(double t) {
    return _CredentialPhotoBorderShape(side: side.scale(t));
  }
}

Path _credentialPhotoPath(Size size) {
  final topRightRadius = size.width * 0.42;
  final bottomLeftRadius = size.width * 0.30;

  return Path()
    ..moveTo(bottomLeftRadius, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - topRightRadius)
    ..quadraticBezierTo(
      size.width,
      size.height,
      size.width - topRightRadius,
      size.height,
    )
    ..lineTo(0, size.height)
    ..lineTo(0, bottomLeftRadius)
    ..quadraticBezierTo(0, 0, bottomLeftRadius, 0)
    ..close();
}

class _CredentialPdfDraft {
  const _CredentialPdfDraft({
    required this.user,
    required this.nombreCompleto,
    required this.primerApellido,
    required this.segundoApellido,
    required this.tercerApellido,
  });

  final AppUser user;
  final String nombreCompleto;
  final String primerApellido;
  final String segundoApellido;
  final String tercerApellido;
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

String _resolvedOfficeName(AppUser user) {
  final officeName = (user.officeName ?? '').trim().isNotEmpty
      ? user.officeName!.trim()
      : user.unidad.trim();

  return officeName.isEmpty ? 'Sin oficina' : officeName;
}

List<AppUser> _replaceUser(List<AppUser> users, AppUser updatedUser) {
  return users
      .map((user) => user.email == updatedUser.email ? updatedUser : user)
      .toList(growable: false);
}

bool _userMatchesSearchQuery(AppUser user, String query) {
  final searchableText = _searchableTextForUser(user);

  if (searchableText.contains(query)) {
    return true;
  }

  final tokens = query
      .split(' ')
      .where((token) => token.trim().isNotEmpty)
      .toList(growable: false);

  return tokens.isNotEmpty &&
      tokens.every((token) => searchableText.contains(token));
}

String _searchableTextForUser(AppUser user) {
  return _normalizeSearchText(
    '${user.ci} ${user.celular} ${user.fullName} ${user.nombreCompleto} '
    '${user.primerApellido} ${user.segundoApellido} ${user.tercerApellido} '
    '${user.email} ${user.numeroItem} ${user.tipoVinculo} '
    '${user.cargoCodigo ?? ''} ${user.cargo} '
    '${user.subcargoCodigo ?? ''} ${user.subcargo} '
    '${user.cargoEfectivoCodigo ?? ''} ${user.cargoEfectivo} '
    '${user.officeCode ?? ''} ${user.officeName ?? ''} ${user.unidad} '
    '${user.primaryOfficeName ?? ''} ${user.commissionOfficeName ?? ''}',
  );
}

Uri? _tryParseCredentialPhotoUri(String? photoSource) {
  if (photoSource == null || photoSource.isEmpty) {
    return null;
  }

  final parsedUri = Uri.tryParse(photoSource);

  if (parsedUri == null) {
    return null;
  }

  if (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') {
    return parsedUri;
  }

  return null;
}

Uint8List? _tryDecodeCredentialPhotoBytes(String? photoSource) {
  if (photoSource == null || photoSource.isEmpty) {
    return null;
  }

  try {
    return base64Decode(photoSource);
  } catch (_) {
    return null;
  }
}

bool _matchesOffice(AppUser user, OfficeOption office) {
  final userOfficeIds = {
    user.officeId,
    user.primaryOfficeId,
    user.commissionOfficeId,
  };

  if (userOfficeIds.contains(office.id)) {
    return true;
  }

  final selectedOfficeCode = _normalizeExactOfficeValue(office.code);
  final userOfficeCode = _normalizeExactOfficeValue(user.officeCode ?? '');

  if (selectedOfficeCode.isNotEmpty && userOfficeCode == selectedOfficeCode) {
    return true;
  }

  final selectedOfficeName = _normalizeExactOfficeValue(office.name);
  final userOfficeNames = [
    user.officeName ?? '',
    user.primaryOfficeName ?? '',
    user.commissionOfficeName ?? '',
    user.unidad,
  ].map(_normalizeExactOfficeValue);

  return selectedOfficeName.isNotEmpty &&
      userOfficeNames.any((name) => name == selectedOfficeName);
}

bool _matchesCargo(AppUser user, CargoOption cargo) {
  final selectedCargoCode = cargo.code.trim().toUpperCase();
  final userCargoCodes = {
    (user.cargoCodigo ?? '').trim().toUpperCase(),
    (user.subcargoCodigo ?? '').trim().toUpperCase(),
    (user.cargoEfectivoCodigo ?? '').trim().toUpperCase(),
    (user.effectiveCargoCode ?? '').trim().toUpperCase(),
  };

  if (selectedCargoCode.isNotEmpty &&
      userCargoCodes.contains(selectedCargoCode)) {
    return true;
  }

  final selectedCargoName = _normalizeSearchText(cargo.name);
  final userCargoNames = [
    user.cargo,
    user.subcargo,
    user.cargoEfectivo,
    user.effectiveCargo,
  ].map(_normalizeSearchText);

  return selectedCargoName.isNotEmpty &&
      userCargoNames.any((name) => name == selectedCargoName);
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
  return _stripTextAccents(
    value.trim().toLowerCase(),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _resolvedJobTitle(AppUser user) {
  final jobTitle = user.effectiveCargo.trim();
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
