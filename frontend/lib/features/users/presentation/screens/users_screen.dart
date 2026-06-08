import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/base64_avatar.dart';
import '../../../auth/domain/entities/cargo_option.dart';
import '../../../auth/domain/entities/office_option.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  static const int _usersPerPage = 20;

  List<AppUser> _users = const [];
  List<OfficeOption> _offices = const [];
  List<CargoOption> _cargos = const [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isLoadingReferenceData = false;
  final Set<int> _updatingUserIds = <int>{};
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _userSearchIndex = <String, String>{};
  Timer? _searchDebounce;
  String _searchQuery = '';
  List<AppUser>? _filteredUsersCache;
  OfficeOption? _selectedFilterOffice;
  CargoOption? _selectedFilterCargo;
  String? _errorMessage;
  int _currentPage = 0;

  int get _adminCount => _users.where((user) => user.isAdmin).length;
  int get _controlCount => _users.where((user) => user.isControl).length;
  int get _credentialsCount =>
      _users.where((user) => user.isCredentials).length;
  int get _externalCount => _users.where((user) => user.isExternalUser).length;
  int get _activeUsersCount => _users.where((user) => user.activo).length;
  List<AppUser> get _filteredUsers {
    final cachedUsers = _filteredUsersCache;

    if (cachedUsers != null) {
      return cachedUsers;
    }

    final query = _searchQuery;
    final selectedOffice = _selectedFilterOffice;
    final selectedCargo = _selectedFilterCargo;

    if (selectedCargo != null) {
      final filteredUsers = _users
          .where((user) => _userMatchesCargo(user, selectedCargo))
          .toList(growable: false);
      _filteredUsersCache = filteredUsers;
      return filteredUsers;
    }

    if (query.isEmpty && selectedOffice == null) {
      _filteredUsersCache = _users;
      return _users;
    }

    final filteredUsers = _users
        .where((user) {
          final matchesOffice =
              selectedOffice == null ||
              _userBelongsToOffice(user, selectedOffice);

          if (!matchesOffice) {
            return false;
          }

          if (query.isEmpty) {
            return true;
          }

          return _searchableTextForUser(user).contains(query);
        })
        .toList(growable: false);

    _filteredUsersCache = filteredUsers;
    return filteredUsers;
  }

  int get _totalPages => _filteredUsers.isEmpty
      ? 1
      : ((_filteredUsers.length - 1) ~/ _usersPerPage) + 1;
  int get _safeCurrentPage => _currentPage.clamp(0, _totalPages - 1);
  int get _visibleStartIndex => _filteredUsers.isEmpty
      ? 0
      : (_safeCurrentPage * _usersPerPage).clamp(0, _filteredUsers.length);
  int get _visibleEndIndex => _filteredUsers.isEmpty
      ? 0
      : (_visibleStartIndex + _usersPerPage).clamp(0, _filteredUsers.length);
  List<AppUser> get _visibleUsers =>
      _filteredUsers.sublist(_visibleStartIndex, _visibleEndIndex);

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadOfficesForFilter();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _invalidateUserFilters({bool clearSearchIndex = false}) {
    _filteredUsersCache = null;

    if (clearSearchIndex) {
      _userSearchIndex.clear();
    }
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }

      final nextQuery = _normalizeSearchText(value);

      if (nextQuery == _searchQuery) {
        return;
      }

      setState(() {
        _searchQuery = nextQuery;
        _selectedFilterCargo = null;
        _currentPage = 0;
        _invalidateUserFilters();
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();

    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _currentPage = 0;
      _invalidateUserFilters();
    });
  }

  String _searchableTextForUser(AppUser user) {
    final cacheKey =
        '${user.id ?? 'new'}|${user.email}|${user.ci}|${user.celular}|${user.fullName}|'
        '${user.cargoCodigo}|${user.cargo}|'
        '${user.officeCode}|${user.officeName}|${user.primaryOfficeName}|'
        '${user.commissionOfficeName}|${user.unidad}|${user.lugar}';
    final cachedText = _userSearchIndex[cacheKey];

    if (cachedText != null) {
      return cachedText;
    }

    final searchableText = _normalizeSearchText(
      '${user.ci} ${user.celular} ${user.fullName} ${user.nombreCompleto} '
      '${user.primerApellido} ${user.segundoApellido} '
      '${user.tercerApellido} ${user.email} '
      '${user.cargoCodigo ?? ''} ${user.cargo} '
      '${user.officeCode} ${user.officeName} '
      '${user.primaryOfficeName} ${user.commissionOfficeName} '
      '${user.unidad} ${user.lugar}',
    );
    _userSearchIndex[cacheKey] = searchableText;

    return searchableText;
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final users = await dependencies.authApiService.fetchUsers(
        requesterEmail: widget.currentUser.email,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = _sortUsers(users);
        _invalidateUserFilters(clearSearchIndex: true);
        _currentPage = _safeCurrentPage;
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'No fue posible cargar los usuarios.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openCreateDialog() async {
    if (_isCreating || !await _ensureReferenceData()) {
      return;
    }

    if (!mounted) {
      return;
    }

    final draft = await showDialog<_ManagedUserDraft>(
      context: context,
      builder: (context) =>
          _ManagedUserDialog(offices: _offices, cargos: _cargos),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final createdUser = await dependencies.authApiService.createManagedUser(
        requesterEmail: widget.currentUser.email,
        role: draft.role,
        email: draft.email,
        nombreCompleto: draft.nombreCompleto,
        primerApellido: draft.primerApellido,
        segundoApellido: draft.segundoApellido,
        tercerApellido: draft.tercerApellido,
        ci: draft.ci,
        celular: draft.celular,
        tipoVinculo: draft.tipoVinculo,
        oficinaId: draft.office.id,
        oficinaComisionId: draft.commissionOffice?.id,
        cargoCodigo: draft.cargo.code,
        unidad: draft.office.name,
        cargo: draft.cargo.name,
        lugar: draft.lugar,
        numeroItem: draft.numeroItem,
        activo: draft.activo,
        fotoData: draft.fotoData!,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = _sortUsers([createdUser, ..._users]);
        _invalidateUserFilters(clearSearchIndex: true);
        _currentPage = 0;
      });

      AppAlert.showSuccess(
        context,
        'Usuario ${createdUser.fullName} creado como ${createdUser.roleLabel.toLowerCase()}.',
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

      AppAlert.showError(context, 'No fue posible crear el usuario.');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _toggleUserActive(AppUser user) async {
    final userId = user.id;

    if (userId == null || _updatingUserIds.contains(userId)) {
      return;
    }

    setState(() {
      _updatingUserIds.add(userId);
    });

    try {
      final updatedUser = await dependencies.authApiService
          .updateUserActiveStatus(
            requesterEmail: widget.currentUser.email,
            userId: userId,
            activo: !user.activo,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = _sortUsers([
          updatedUser,
          ..._users.where((item) => item.id != updatedUser.id),
        ]);
        _invalidateUserFilters(clearSearchIndex: true);
        _currentPage = _safeCurrentPage;
      });

      AppAlert.showSuccess(
        context,
        updatedUser.activo ? 'Usuario activado.' : 'Usuario desactivado.',
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

      AppAlert.showError(
        context,
        'No fue posible actualizar el estado del usuario.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingUserIds.remove(userId);
        });
      }
    }
  }

  Future<void> _openEditDialog(AppUser user) async {
    final userId = user.id;

    if (userId == null || _updatingUserIds.contains(userId)) {
      return;
    }

    if (!await _ensureReferenceData()) {
      return;
    }

    if (!mounted) {
      return;
    }

    final draft = await showDialog<_ManagedUserDraft>(
      context: context,
      builder: (context) => _ManagedUserDialog(
        offices: _offices,
        cargos: _cargos,
        initialUser: user,
      ),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _updatingUserIds.add(userId);
    });

    try {
      final updatedUser = await dependencies.authApiService.updateManagedUser(
        requesterEmail: widget.currentUser.email,
        userId: userId,
        role: draft.role,
        email: draft.email,
        password: draft.password,
        nombreCompleto: draft.nombreCompleto,
        primerApellido: draft.primerApellido,
        segundoApellido: draft.segundoApellido,
        tercerApellido: draft.tercerApellido,
        ci: draft.ci,
        celular: draft.celular,
        tipoVinculo: draft.tipoVinculo,
        oficinaId: draft.office.id,
        oficinaComisionId: draft.commissionOffice?.id,
        cargoCodigo: draft.cargo.code,
        unidad: draft.office.name,
        cargo: draft.cargo.name,
        lugar: draft.lugar,
        numeroItem: draft.numeroItem,
        activo: draft.activo,
        fotoData: draft.fotoData,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = _sortUsers([
          updatedUser,
          ..._users.where((item) => item.id != updatedUser.id),
        ]);
        _invalidateUserFilters(clearSearchIndex: true);
        _currentPage = _safeCurrentPage;
      });

      AppAlert.showSuccess(context, 'Usuario actualizado.');
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible actualizar el usuario.');
    } finally {
      if (mounted) {
        setState(() {
          _updatingUserIds.remove(userId);
        });
      }
    }
  }

  Future<bool> _ensureReferenceData() async {
    if (_offices.isNotEmpty && _cargos.isNotEmpty) {
      return true;
    }

    if (_isLoadingReferenceData) {
      return false;
    }

    setState(() {
      _isLoadingReferenceData = true;
    });

    try {
      final offices = _offices.isEmpty
          ? await dependencies.authApiService.fetchOffices()
          : _offices;
      final cargos = _cargos.isEmpty
          ? await dependencies.authApiService.fetchCargos()
          : _cargos;

      if (!mounted) {
        return false;
      }

      setState(() {
        _offices = offices;
        _cargos = cargos;
      });

      if (offices.isEmpty || cargos.isEmpty) {
        AppAlert.showWarning(
          context,
          'No hay oficinas o cargos disponibles para gestionar usuarios.',
        );
        return false;
      }

      return true;
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
      return false;
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar oficinas y cargos.');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReferenceData = false;
        });
      }
    }
  }

  Future<void> _loadOfficesForFilter() async {
    if (_offices.isNotEmpty || _isLoadingReferenceData) {
      return;
    }

    setState(() {
      _isLoadingReferenceData = true;
    });

    try {
      final offices = await dependencies.authApiService.fetchOffices();

      if (!mounted) {
        return;
      }

      setState(() {
        _offices = offices;
      });
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar las oficinas.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReferenceData = false;
        });
      }
    }
  }

  Future<void> _loadCargosForFilter() async {
    if (_cargos.isNotEmpty || _isLoadingReferenceData) {
      return;
    }

    setState(() {
      _isLoadingReferenceData = true;
    });

    try {
      final cargos = await dependencies.authApiService.fetchCargos();

      if (!mounted) {
        return;
      }

      setState(() {
        _cargos = cargos;
      });
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar los cargos.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReferenceData = false;
        });
      }
    }
  }

  Future<void> _pickFilterOffice() async {
    await _loadOfficesForFilter();

    if (!mounted || _offices.isEmpty) {
      return;
    }

    final office = await showModalBottomSheet<OfficeOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OfficeSelectionSheet(
        offices: _offices,
        selectedOffice: _selectedFilterOffice,
        title: 'Filtrar por oficina',
        searchLabel: 'Buscar oficina',
        searchHint: 'Escribe nombre, codigo o nivel',
      ),
    );

    if (!mounted || office == null) {
      return;
    }

    setState(() {
      _selectedFilterOffice = office;
      _selectedFilterCargo = null;
      _currentPage = 0;
      _invalidateUserFilters();
    });
  }

  Future<void> _pickFilterCargo() async {
    await _loadCargosForFilter();

    if (!mounted || _cargos.isEmpty) {
      return;
    }

    final cargo = await showModalBottomSheet<CargoOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CargoSelectionSheet(
        cargos: _cargos,
        selectedCargo: _selectedFilterCargo,
      ),
    );

    if (!mounted || cargo == null) {
      return;
    }

    _searchDebounce?.cancel();

    setState(() {
      _selectedFilterCargo = cargo;
      _selectedFilterOffice = null;
      _searchController.clear();
      _searchQuery = '';
      _currentPage = 0;
      _invalidateUserFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleUsers = _visibleUsers;
    final filteredUsers = _filteredUsers;

    if (_isLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _users.isEmpty) {
      return _UsersErrorState(message: _errorMessage!, onRetry: _loadData);
    }

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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Usuarios del sistema',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Aqui el administrador puede gestionar las cuentas con rol administrador, control, credenciales y funcionario.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loadData,
                        tooltip: 'Recargar usuarios',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _UserStatsGrid(
                    stats: [
                      _UserStatItem(
                        label: 'Administradores',
                        value: '$_adminCount',
                        icon: Icons.verified_user_outlined,
                      ),
                      _UserStatItem(
                        label: 'Control',
                        value: '$_controlCount',
                        icon: Icons.fact_check_outlined,
                      ),
                      _UserStatItem(
                        label: 'Credenciales',
                        value: '$_credentialsCount',
                        icon: Icons.badge_outlined,
                      ),
                      _UserStatItem(
                        label: 'Funcionarios',
                        value: '$_externalCount',
                        icon: Icons.person_outline_rounded,
                      ),
                      _UserStatItem(
                        label: 'Activos',
                        value: '$_activeUsersCount',
                        icon: Icons.verified_user_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: (_isCreating || _isLoadingReferenceData)
                        ? null
                        : _openCreateDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    icon: (_isCreating || _isLoadingReferenceData)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(
                      _isCreating
                          ? 'Creando usuario...'
                          : _isLoadingReferenceData
                          ? 'Cargando datos...'
                          : 'Crear usuario',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: _handleSearchChanged,
                    decoration: InputDecoration(
                      labelText: 'Buscar usuarios',
                      hintText:
                          'Busca por CI, nombre, usuario, cargo u oficina',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar busqueda',
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _OfficeFilterField(
                    selectedOffice: _selectedFilterOffice,
                    isLoading: _isLoadingReferenceData,
                    onTap: _pickFilterOffice,
                    onClear: _selectedFilterOffice == null
                        ? null
                        : () {
                            setState(() {
                              _selectedFilterOffice = null;
                              _currentPage = 0;
                              _invalidateUserFilters();
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  _CargoFilterField(
                    selectedCargo: _selectedFilterCargo,
                    isLoading: _isLoadingReferenceData,
                    onTap: _pickFilterCargo,
                    onClear: _selectedFilterCargo == null
                        ? null
                        : () {
                            setState(() {
                              _selectedFilterCargo = null;
                              _currentPage = 0;
                              _invalidateUserFilters();
                            });
                          },
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD94841),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_users.isEmpty)
            const _EmptyUsersState()
          else if (filteredUsers.isEmpty)
            const _NoSearchUsersState()
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UsersPaginationBar(
                  currentPage: _safeCurrentPage,
                  totalPages: _totalPages,
                  totalUsers: filteredUsers.length,
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
                for (final user in visibleUsers) ...[
                  _UserListCard(
                    user: user,
                    isUpdating:
                        user.id != null && _updatingUserIds.contains(user.id),
                    onEdit: () => _openEditDialog(user),
                    onToggleActive: () => _toggleUserActive(user),
                  ),
                  const SizedBox(height: 12),
                ],
                _UsersPaginationBar(
                  currentPage: _safeCurrentPage,
                  totalPages: _totalPages,
                  totalUsers: filteredUsers.length,
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
              ],
            ),
        ],
      ),
    );
  }
}

class _UsersPaginationBar extends StatelessWidget {
  const _UsersPaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalUsers,
    required this.startIndex,
    required this.endIndex,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final int totalUsers;
  final int startIndex;
  final int endIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final firstVisible = totalUsers == 0 ? 0 : startIndex + 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 560;
            final summary = Text(
              'Mostrando $firstVisible-$endIndex de $totalUsers usuarios',
              textAlign: isCompact ? TextAlign.center : TextAlign.start,
              style: Theme.of(context).textTheme.bodyMedium,
            );
            final pageLabel = _PaginationPageLabel(
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
      ),
    );
  }
}

class _PaginationPageLabel extends StatelessWidget {
  const _PaginationPageLabel({
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

class _UserStatItem {
  const _UserStatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _UserStatsGrid extends StatelessWidget {
  const _UserStatsGrid({required this.stats});

  final List<_UserStatItem> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final maxWidth = constraints.maxWidth;
        final columnCount = maxWidth >= 920
            ? 4
            : maxWidth >= 560
            ? 2
            : 1;
        final cardWidth = columnCount == 1
            ? maxWidth
            : (maxWidth - (spacing * (columnCount - 1))) / columnCount;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final stat in stats)
              _UserStatCard(
                width: cardWidth,
                label: stat.label,
                value: stat.value,
                icon: stat.icon,
              ),
          ],
        );
      },
    );
  }
}

class _UserStatCard extends StatelessWidget {
  const _UserStatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 112),
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
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserListCard extends StatelessWidget {
  const _UserListCard({
    required this.user,
    required this.isUpdating,
    required this.onEdit,
    required this.onToggleActive,
  });

  final AppUser user;
  final bool isUpdating;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 430;
            final avatar = Base64Avatar(
              size: isCompact ? 64 : 72,
              fallbackLabel: user.initial,
              photoSource: user.fotoUrl,
              borderRadius: BorderRadius.circular(18),
            );
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isCompact
                            ? constraints.maxWidth
                            : constraints.maxWidth - 100,
                      ),
                      child: Text(
                        user.fullName,
                        softWrap: true,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    _RoleChip(role: user.role),
                    _StatusChip(isActive: user.activo),
                    OutlinedButton.icon(
                      onPressed: isUpdating ? null : onEdit,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Editar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: isUpdating ? null : onToggleActive,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        side: BorderSide(
                          color: user.activo
                              ? const Color(0xFFD94841)
                              : AppPalette.orange,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: isUpdating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              user.activo
                                  ? Icons.block_outlined
                                  : Icons.check_circle_outline_rounded,
                              size: 16,
                            ),
                      label: Text(user.activo ? 'Desactivar' : 'Activar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    _UserMeta(label: 'CI', value: user.ci),
                    if (user.celular.trim().isNotEmpty)
                      _UserMeta(label: 'Celular', value: user.celular),
                    _UserMeta(label: 'Usuario', value: user.email),
                    _UserMeta(
                      label: 'Oficina',
                      value: _resolvedOfficeName(user),
                    ),
                    if (user.hasCommission &&
                        (user.primaryOfficeName ?? '').trim().isNotEmpty)
                      _UserMeta(
                        label: 'Oficina base',
                        value: user.primaryOfficeName!,
                      ),
                    _UserMeta(label: 'Cargo', value: user.cargo),
                    if (user.lugar.trim().isNotEmpty)
                      _UserMeta(label: 'Lugar', value: user.lugar),
                    _UserMeta(
                      label: 'Tipo',
                      value: _tipoVinculoLabel(user.tipoVinculo),
                    ),
                    if (user.numeroItem.trim().isNotEmpty)
                      _UserMeta(label: 'Item', value: user.numeroItem),
                  ],
                ),
              ],
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [avatar, const SizedBox(height: 12), details],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final AppUserRole role;

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (role) {
      AppUserRole.admin => AppPalette.orange,
      AppUserRole.control => AppPalette.night,
      AppUserRole.credentials => AppPalette.orange,
      AppUserRole.external => AppPalette.muted,
    };
    final backgroundColor = switch (role) {
      AppUserRole.admin => AppPalette.orangeSoft,
      AppUserRole.control => AppPalette.blueSoftStrong,
      AppUserRole.credentials => AppPalette.orangeSoft,
      AppUserRole.external => AppPalette.surfaceSoft,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withValues(alpha: 0.42)),
      ),
      child: Text(
        role.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: accentColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.line),
      ),
      child: Text(
        isActive ? 'Activo' : 'Inactivo',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _UserMeta extends StatelessWidget {
  const _UserMeta({required this.label, required this.value});

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

class _UsersErrorState extends StatelessWidget {
  const _UsersErrorState({required this.message, required this.onRetry});

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
                  'No fue posible cargar los usuarios',
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

class _EmptyUsersState extends StatelessWidget {
  const _EmptyUsersState();

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
              child: const Icon(
                Icons.person_search_rounded,
                color: AppPalette.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Todavia no hay usuarios cargados',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Crea el primer usuario desde esta pantalla.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchUsersState extends StatelessWidget {
  const _NoSearchUsersState();

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
              child: const Icon(
                Icons.search_off_rounded,
                color: AppPalette.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No hay usuarios con esa busqueda',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficeFilterField extends StatelessWidget {
  const _OfficeFilterField({
    required this.selectedOffice,
    required this.isLoading,
    required this.onTap,
    required this.onClear,
  });

  final OfficeOption? selectedOffice;
  final bool isLoading;
  final Future<void> Function() onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final office = selectedOffice;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: isLoading ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Filtrar por oficina',
          prefixIcon: const Icon(Icons.account_tree_outlined),
          suffixIcon: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : office == null
              ? const Icon(Icons.search_rounded)
              : IconButton(
                  tooltip: 'Quitar filtro de oficina',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        child: Text(
          office?.displayLabel ?? 'Todas las oficinas',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: office == null ? AppPalette.muted : AppPalette.night,
          ),
        ),
      ),
    );
  }
}

class _CargoFilterField extends StatelessWidget {
  const _CargoFilterField({
    required this.selectedCargo,
    required this.isLoading,
    required this.onTap,
    required this.onClear,
  });

  final CargoOption? selectedCargo;
  final bool isLoading;
  final Future<void> Function() onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cargo = selectedCargo;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: isLoading ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Filtrar por cargo',
          prefixIcon: const Icon(Icons.badge_outlined),
          suffixIcon: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : cargo == null
              ? const Icon(Icons.search_rounded)
              : IconButton(
                  tooltip: 'Quitar filtro de cargo',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        child: Text(
          cargo?.displayLabel ?? 'Todos los cargos',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: cargo == null ? AppPalette.muted : AppPalette.night,
          ),
        ),
      ),
    );
  }
}

class _ManagedUserDialog extends StatefulWidget {
  const _ManagedUserDialog({
    required this.offices,
    required this.cargos,
    this.initialUser,
  });

  final List<OfficeOption> offices;
  final List<CargoOption> cargos;
  final AppUser? initialUser;

  @override
  State<_ManagedUserDialog> createState() => _ManagedUserDialogState();
}

class _ManagedUserDialogState extends State<_ManagedUserDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _celularController = TextEditingController();
  final TextEditingController _nombreCompletoController =
      TextEditingController();
  final TextEditingController _primerApellidoController =
      TextEditingController();
  final TextEditingController _segundoApellidoController =
      TextEditingController();
  final TextEditingController _tercerApellidoController =
      TextEditingController();
  final TextEditingController _unidadController = TextEditingController();
  final TextEditingController _commissionOfficeController =
      TextEditingController();
  final TextEditingController _cargoController = TextEditingController();
  final TextEditingController _lugarController = TextEditingController();
  final TextEditingController _numeroItemController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  AppUserRole _selectedRole = AppUserRole.control;
  String _selectedTipoVinculo = 'ITEM';
  bool _selectedActivo = true;
  OfficeOption? _selectedOffice;
  OfficeOption? _selectedCommissionOffice;
  bool _hasCommission = false;
  CargoOption? _selectedCargo;
  Uint8List? _photoBytes;
  bool _showPhotoError = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _changePassword = false;
  bool get _isEditing => widget.initialUser != null;

  @override
  void initState() {
    super.initState();

    final user = widget.initialUser;

    if (user == null) {
      return;
    }

    _selectedRole = user.role;
    final tipoVinculo = user.tipoVinculo.trim().toUpperCase();
    _selectedTipoVinculo = switch (tipoVinculo) {
      'EVENTUAL' => 'EVENTUAL',
      'CONSULTOR' => 'CONSULTOR',
      _ => 'ITEM',
    };
    _selectedActivo = user.activo;
    _ciController.text = user.ci;
    _celularController.text = user.celular;
    _nombreCompletoController.text = user.nombreCompleto;
    _primerApellidoController.text = user.primerApellido;
    _segundoApellidoController.text = user.segundoApellido;
    _tercerApellidoController.text = user.tercerApellido;
    _numeroItemController.text = user.numeroItem;

    _selectedOffice = _findInitialOffice(
      officeId: user.primaryOfficeId ?? user.officeId,
      officeCode: user.hasCommission ? null : user.officeCode,
      officeName: user.primaryOfficeName,
    );
    _unidadController.text =
        _selectedOffice?.name ??
        user.primaryOfficeName ??
        _resolvedOfficeName(user);
    _hasCommission = user.hasCommission;
    _selectedCommissionOffice = _findInitialOffice(
      officeId: user.commissionOfficeId,
      officeCode: user.hasCommission ? user.officeCode : null,
      officeName: user.commissionOfficeName,
    );
    _commissionOfficeController.text =
        _selectedCommissionOffice?.name ?? user.commissionOfficeName ?? '';
    _selectedCargo = _findInitialCargo(user);
    _cargoController.text = _selectedCargo?.name ?? user.cargo;
    _lugarController.text = user.lugar;
  }

  @override
  void dispose() {
    _ciController.dispose();
    _celularController.dispose();
    _nombreCompletoController.dispose();
    _primerApellidoController.dispose();
    _segundoApellidoController.dispose();
    _tercerApellidoController.dispose();
    _unidadController.dispose();
    _commissionOfficeController.dispose();
    _cargoController.dispose();
    _lugarController.dispose();
    _numeroItemController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickOffice() async {
    final office = await showModalBottomSheet<OfficeOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OfficeSelectionSheet(
        offices: widget.offices,
        selectedOffice: _selectedOffice,
      ),
    );

    if (!mounted || office == null) {
      return;
    }

    setState(() {
      _selectedOffice = office;
      _unidadController.text = office.name;
    });
  }

  Future<void> _pickCargo() async {
    final cargo = await showModalBottomSheet<CargoOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CargoSelectionSheet(
        cargos: widget.cargos,
        selectedCargo: _selectedCargo,
      ),
    );

    if (!mounted || cargo == null) {
      return;
    }

    setState(() {
      _selectedCargo = cargo;
      _cargoController.text = cargo.name;

      if (!_isPorteroCargo(cargo)) {
        _lugarController.clear();
      }
    });
  }

  Future<void> _pickCommissionOffice() async {
    final office = await showModalBottomSheet<OfficeOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OfficeSelectionSheet(
        offices: widget.offices,
        selectedOffice: _selectedCommissionOffice,
      ),
    );

    if (!mounted || office == null) {
      return;
    }

    setState(() {
      _selectedCommissionOffice = office;
      _commissionOfficeController.text = office.name;
    });
  }

  OfficeOption? _findInitialOffice({
    int? officeId,
    String? officeCode,
    String? officeName,
  }) {
    for (final office in widget.offices) {
      if (officeId != null && office.id == officeId) {
        return office;
      }

      if (officeCode != null &&
          office.code.toLowerCase() == officeCode.toLowerCase()) {
        return office;
      }

      if (officeName != null &&
          office.name.toLowerCase() == officeName.toLowerCase()) {
        return office;
      }
    }

    return null;
  }

  CargoOption? _findInitialCargo(AppUser user) {
    for (final cargo in widget.cargos) {
      if (cargo.name.toLowerCase() == user.cargo.toLowerCase()) {
        return cargo;
      }
    }

    return null;
  }

  Future<void> _pickPhoto() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    if (file == null) {
      return;
    }

    final bytes = await file.readAsBytes();

    if (!mounted) {
      return;
    }

    setState(() {
      _photoBytes = bytes;
      _showPhotoError = false;
    });
  }

  void _submit() {
    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      return;
    }

    if (_selectedOffice == null ||
        _selectedCargo == null ||
        (_hasCommission && _selectedCommissionOffice == null)) {
      return;
    }

    if (!_isEditing && _photoBytes == null) {
      setState(() {
        _showPhotoError = true;
      });
      return;
    }

    Navigator.of(context).pop(
      _ManagedUserDraft(
        role: _selectedRole,
        tipoVinculo: _selectedTipoVinculo,
        activo: _selectedActivo,
        ci: _ciController.text.trim(),
        celular: _celularController.text.trim(),
        nombreCompleto: _nombreCompletoController.text.trim(),
        primerApellido: _primerApellidoController.text.trim(),
        segundoApellido: _segundoApellidoController.text.trim(),
        tercerApellido: _tercerApellidoController.text.trim(),
        office: _selectedOffice!,
        commissionOffice: _hasCommission ? _selectedCommissionOffice : null,
        cargo: _selectedCargo!,
        lugar: _isPorteroCargo(_selectedCargo)
            ? _lugarController.text.trim()
            : '',
        numeroItem: _numeroItemController.text.trim(),
        email: _ciController.text.trim(),
        password: _isEditing
            ? (_changePassword && _passwordController.text.trim().isNotEmpty
                  ? _passwordController.text.trim()
                  : null)
            : null,
        fotoData: _photoBytes == null ? null : base64Encode(_photoBytes!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = _selectedRole.label.toLowerCase();
    final actionLabel = _isEditing ? 'Guardar cambios' : 'Crear usuario';

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 860),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? 'Editar $roleLabel' : 'Crear $roleLabel',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppPalette.line),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing
                            ? 'Actualiza los datos del usuario y guarda los cambios.'
                            : 'Completa los datos del usuario. El acceso se creara automaticamente con CI como usuario y primer apellido + CI como contrasena inicial.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      _DropdownField<AppUserRole>(
                        label: 'Rol del sistema',
                        isRequired: true,
                        value: _selectedRole,
                        items: const [
                          DropdownMenuItem(
                            value: AppUserRole.control,
                            child: Text('Control'),
                          ),
                          DropdownMenuItem(
                            value: AppUserRole.admin,
                            child: Text('Administrador'),
                          ),
                          DropdownMenuItem(
                            value: AppUserRole.credentials,
                            child: Text('Credenciales'),
                          ),
                          DropdownMenuItem(
                            value: AppUserRole.external,
                            child: Text('Funcionario'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _selectedRole = value;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _DropdownField<String>(
                        label: 'Tipo de vinculacion',
                        isRequired: true,
                        value: _selectedTipoVinculo,
                        items: const [
                          DropdownMenuItem(value: 'ITEM', child: Text('Item')),
                          DropdownMenuItem(
                            value: 'EVENTUAL',
                            child: Text('Eventual'),
                          ),
                          DropdownMenuItem(
                            value: 'CONSULTOR',
                            child: Text('Consultor'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _selectedTipoVinculo = value;

                            if (value != 'ITEM') {
                              _numeroItemController.clear();
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _ciController,
                        label: 'CI',
                        hint: 'Ingresa el carnet de identidad',
                        isRequired: true,
                        validator: _requiredValidator('Ingresa el CI.'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _celularController,
                        label: 'Celular',
                        hint: 'Ingresa el numero de celular',
                        isRequired: true,
                        keyboardType: TextInputType.phone,
                        validator: _requiredValidator(
                          'Ingresa el numero de celular.',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _nombreCompletoController,
                        label: 'Nombre completo',
                        hint: 'Ingresa los nombres',
                        isRequired: true,
                        validator: _requiredValidator('Ingresa los nombres.'),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _primerApellidoController,
                        label: 'Primer apellido',
                        hint: 'Ingresa el primer apellido',
                        isRequired: true,
                        validator: _requiredValidator(
                          'Ingresa el primer apellido.',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _segundoApellidoController,
                        label: 'Segundo apellido',
                        hint: 'Ingresa el segundo apellido',
                        isRequired: true,
                        validator: _requiredValidator(
                          'Ingresa el segundo apellido.',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _tercerApellidoController,
                        label: 'Tercer apellido (opcional)',
                        hint: 'Ingresa el tercer apellido si aplica',
                        validator: (_) => null,
                      ),
                      const SizedBox(height: 14),
                      _PickerField(
                        controller: _unidadController,
                        label: 'Unidad / oficina',
                        hint: 'Selecciona una unidad registrada',
                        icon: Icons.apartment_rounded,
                        isRequired: true,
                        onTap: _pickOffice,
                        validator: _requiredValidator(
                          'Selecciona una unidad valida.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedOffice == null
                            ? '${widget.offices.length} unidades cargadas desde la base de datos.'
                            : 'Codigo ${_selectedOffice!.code} | Nivel ${_selectedOffice!.level}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _selectedOffice == null
                              ? null
                              : AppPalette.orange,
                          fontWeight: _selectedOffice == null
                              ? null
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _hasCommission,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Comision'),
                        onChanged: (value) {
                          setState(() {
                            _hasCommission = value ?? false;

                            if (!_hasCommission) {
                              _selectedCommissionOffice = null;
                              _commissionOfficeController.clear();
                            }
                          });
                        },
                      ),
                      if (_hasCommission) ...[
                        const SizedBox(height: 10),
                        _PickerField(
                          controller: _commissionOfficeController,
                          label: 'Oficina de comision',
                          hint: 'Selecciona la oficina de comision',
                          icon: Icons.swap_horiz_rounded,
                          isRequired: true,
                          onTap: _pickCommissionOffice,
                          validator: _requiredValidator(
                            'Selecciona la oficina de comision.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedCommissionOffice == null
                              ? 'Esta oficina contara como principal para eventos.'
                              : 'Comision: ${_selectedCommissionOffice!.name}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _selectedCommissionOffice == null
                                    ? null
                                    : AppPalette.orange,
                                fontWeight: _selectedCommissionOffice == null
                                    ? null
                                    : FontWeight.w600,
                              ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _PickerField(
                        controller: _cargoController,
                        label: 'Cargo',
                        hint: 'Selecciona un cargo registrado',
                        icon: Icons.badge_outlined,
                        isRequired: true,
                        onTap: _pickCargo,
                        validator: _requiredValidator(
                          'Selecciona un cargo valido.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedCargo == null
                            ? '${widget.cargos.length} cargos cargados desde la base de datos.'
                            : 'Codigo ${_selectedCargo!.code}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _selectedCargo == null
                              ? null
                              : AppPalette.orange,
                          fontWeight: _selectedCargo == null
                              ? null
                              : FontWeight.w600,
                        ),
                      ),
                      if (_isPorteroCargo(_selectedCargo)) ...[
                        const SizedBox(height: 14),
                        _FormField(
                          controller: _lugarController,
                          label: 'Lugar',
                          hint: 'Ingresa el lugar al que pertenece',
                          isRequired: true,
                          validator: _requiredValidator('Ingresa el lugar.'),
                        ),
                      ],
                      if (_selectedTipoVinculo == 'ITEM') ...[
                        const SizedBox(height: 14),
                        _FormField(
                          controller: _numeroItemController,
                          label: 'Numero item',
                          hint: 'Ingresa el numero item',
                          isRequired: true,
                          validator: _requiredValidator(
                            'Ingresa el numero item.',
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _DropdownField<bool>(
                        label: 'Estado',
                        isRequired: true,
                        value: _selectedActivo,
                        items: const [
                          DropdownMenuItem(value: true, child: Text('Activo')),
                          DropdownMenuItem(
                            value: false,
                            child: Text('Inactivo'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _selectedActivo = value;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _PhotoPickerField(
                        photoBytes: _photoBytes,
                        existingPhotoSource: widget.initialUser?.fotoUrl,
                        isRequired: !_isEditing,
                        showError: _showPhotoError,
                        onPickPhoto: _pickPhoto,
                      ),
                      const SizedBox(height: 14),
                      _AccessInfoCard(
                        isEditing: _isEditing,
                        ci: _ciController.text,
                        primerApellido: _primerApellidoController.text,
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: _changePassword,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Cambiar contrasena'),
                          onChanged: (value) {
                            setState(() {
                              _changePassword = value ?? false;

                              if (!_changePassword) {
                                _passwordController.clear();
                                _confirmPasswordController.clear();
                              }
                            });
                          },
                        ),
                        if (_changePassword) ...[
                          const SizedBox(height: 14),
                          _FormField(
                            controller: _passwordController,
                            label: 'Nueva contrasena',
                            hint: '*******',
                            obscureText: _hidePassword,
                            isRequired: true,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _hidePassword = !_hidePassword;
                                });
                              },
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                            validator: (value) {
                              final password = (value ?? '').trim();

                              if (password.length < 6) {
                                return 'La contrasena debe tener al menos 6 caracteres.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          _FormField(
                            controller: _confirmPasswordController,
                            label: 'Confirmar nueva contrasena',
                            hint: '*******',
                            obscureText: _hideConfirmPassword,
                            isRequired: true,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _hideConfirmPassword = !_hideConfirmPassword;
                                });
                              },
                              icon: Icon(
                                _hideConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                            validator: (value) {
                              final password = _passwordController.text.trim();
                              final confirmation = (value ?? '').trim();

                              if (confirmation != password) {
                                return 'Las contrasenas no coinciden.';
                              }

                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        ],
                      ],
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
                    child: Text(actionLabel),
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

class _ManagedUserDraft {
  const _ManagedUserDraft({
    required this.role,
    required this.tipoVinculo,
    required this.activo,
    required this.ci,
    required this.celular,
    required this.nombreCompleto,
    required this.primerApellido,
    required this.segundoApellido,
    required this.tercerApellido,
    required this.office,
    required this.commissionOffice,
    required this.cargo,
    required this.lugar,
    required this.numeroItem,
    required this.email,
    required this.password,
    required this.fotoData,
  });

  final AppUserRole role;
  final String tipoVinculo;
  final bool activo;
  final String ci;
  final String celular;
  final String nombreCompleto;
  final String primerApellido;
  final String segundoApellido;
  final String tercerApellido;
  final OfficeOption office;
  final OfficeOption? commissionOffice;
  final CargoOption cargo;
  final String lugar;
  final String numeroItem;
  final String email;
  final String? password;
  final String? fotoData;
}

class _AccessInfoCard extends StatelessWidget {
  const _AccessInfoCard({
    required this.isEditing,
    required this.ci,
    required this.primerApellido,
  });

  final bool isEditing;
  final String ci;
  final String primerApellido;

  @override
  Widget build(BuildContext context) {
    final normalizedCi = ci.trim();
    final initialPassword = _buildInitialPassword(
      primerApellido: primerApellido,
      ci: ci,
    );

    return Container(
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
            'Acceso a la app',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            isEditing
                ? 'Usuario: ${normalizedCi.isEmpty ? 'CI del usuario' : normalizedCi}'
                : 'Usuario inicial: ${normalizedCi.isEmpty ? 'CI del usuario' : normalizedCi}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!isEditing) ...[
            const SizedBox(height: 4),
            Text(
              'Contrasena inicial: ${initialPassword.isEmpty ? 'primer apellido + CI' : initialPassword}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    this.obscureText = false,
    this.suffixIcon,
    this.onChanged,
    this.onFieldSubmitted,
    this.keyboardType,
    this.isRequired = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?) validator;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? keyboardType;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        label: _RequiredFieldLabel(label: label, isRequired: isRequired),
        hintText: hint,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isRequired = false,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        label: _RequiredFieldLabel(label: label, isRequired: isRequired),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onTap,
    required this.validator,
    this.isRequired = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Future<void> Function() onTap;
  final String? Function(String?) validator;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final hasValue = controller.text.trim().isNotEmpty;

    return FormField<String>(
      validator: (_) => validator(controller.text),
      builder: (state) {
        final hasError = state.hasError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RequiredFieldLabel(
              label: label,
              isRequired: isRequired,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                await onTap();
                state.didChange(controller.text);
              },
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 17,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: hasError ? const Color(0xFFD94841) : AppPalette.line,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: hasValue
                          ? Text(
                              controller.text.trim(),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: AppPalette.night),
                            )
                          : _RequiredFieldLabel(
                              label: hint,
                              isRequired: isRequired,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: AppPalette.muted),
                            ),
                    ),
                    Icon(icon, color: AppPalette.orange),
                  ],
                ),
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 6),
              Text(
                state.errorText!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFFD94841)),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PhotoPickerField extends StatelessWidget {
  const _PhotoPickerField({
    required this.photoBytes,
    required this.existingPhotoSource,
    required this.isRequired,
    required this.showError,
    required this.onPickPhoto,
  });

  final Uint8List? photoBytes;
  final String? existingPhotoSource;
  final bool isRequired;
  final bool showError;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Foto', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPickPhoto,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: showError ? const Color(0xFFD94841) : AppPalette.line,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: photoBytes == null
                        ? existingPhotoSource?.trim().isNotEmpty == true
                              ? Base64Avatar(
                                  size: 74,
                                  fallbackLabel: 'U',
                                  photoSource: existingPhotoSource,
                                  borderRadius: BorderRadius.circular(18),
                                )
                              : Container(
                                  color: AppPalette.orangeSoft,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.photo_camera_outlined,
                                    color: AppPalette.orange,
                                  ),
                                )
                        : Image.memory(photoBytes!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photoBytes == null
                            ? existingPhotoSource?.trim().isNotEmpty == true
                                  ? 'Foto actual del usuario'
                                  : 'Selecciona una foto'
                            : 'Foto cargada correctamente',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRequired
                            ? 'La foto es obligatoria para crear el usuario.'
                            : 'Selecciona una nueva foto solo si deseas reemplazarla.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          Text(
            'Debes seleccionar una foto.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFFD94841)),
          ),
        ],
      ],
    );
  }
}

class _OfficeSelectionSheet extends StatefulWidget {
  const _OfficeSelectionSheet({
    required this.offices,
    required this.selectedOffice,
    this.title = 'Selecciona la unidad',
    this.searchLabel = 'Buscar unidad',
    this.searchHint = 'Escribe nombre, codigo o nivel',
  });

  final List<OfficeOption> offices;
  final OfficeOption? selectedOffice;
  final String title;
  final String searchLabel;
  final String searchHint;

  @override
  State<_OfficeSelectionSheet> createState() => _OfficeSelectionSheetState();
}

class _OfficeSelectionSheetState extends State<_OfficeSelectionSheet> {
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
            heightFactor: 0.92,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: widget.searchLabel,
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredOffices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final office = filteredOffices[index];
                        final isSelected =
                            widget.selectedOffice?.id == office.id;

                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(office),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  office.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Codigo ${office.code} | Nivel ${office.level}',
                                  style: Theme.of(context).textTheme.bodySmall,
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

class _CargoSelectionSheet extends StatefulWidget {
  const _CargoSelectionSheet({
    required this.cargos,
    required this.selectedCargo,
  });

  final List<CargoOption> cargos;
  final CargoOption? selectedCargo;

  @override
  State<_CargoSelectionSheet> createState() => _CargoSelectionSheetState();
}

class _CargoSelectionSheetState extends State<_CargoSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredCargos = widget.cargos
        .where((cargo) {
          if (query.isEmpty) {
            return true;
          }

          return cargo.name.toLowerCase().contains(query) ||
              cargo.code.toLowerCase().contains(query);
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
            heightFactor: 0.92,
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
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar cargo',
                      hintText: 'Escribe cargo o codigo',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredCargos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final cargo = filteredCargos[index];
                        final isSelected =
                            widget.selectedCargo?.code == cargo.code;

                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(cargo),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cargo.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Codigo ${cargo.code}',
                                  style: Theme.of(context).textTheme.bodySmall,
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

List<AppUser> _sortUsers(List<AppUser> users) {
  final nextUsers = [...users];

  nextUsers.sort((left, right) {
    final roleComparison = _userRoleOrder(
      left.role,
    ).compareTo(_userRoleOrder(right.role));

    if (roleComparison != 0) {
      return roleComparison;
    }

    if (left.activo != right.activo) {
      return left.activo ? -1 : 1;
    }

    return left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase());
  });

  return nextUsers;
}

int _userRoleOrder(AppUserRole role) {
  switch (role) {
    case AppUserRole.admin:
      return 0;
    case AppUserRole.control:
      return 1;
    case AppUserRole.credentials:
      return 2;
    case AppUserRole.external:
      return 3;
  }
}

String _resolvedOfficeName(AppUser user) {
  final officeName = user.officeName?.trim();

  if (officeName != null && officeName.isNotEmpty) {
    return officeName;
  }

  final unidad = user.unidad.trim();
  return unidad.isNotEmpty ? unidad : 'Sin oficina';
}

bool _userBelongsToOffice(AppUser user, OfficeOption office) {
  final effectiveOfficeId = user.hasCommission
      ? user.commissionOfficeId ?? user.officeId
      : user.primaryOfficeId ?? user.officeId;

  if (effectiveOfficeId == office.id) {
    return true;
  }

  final expectedCode = _normalizeExactOfficeValue(office.code);
  final userCode = _normalizeExactOfficeValue(user.officeCode ?? '');

  if (expectedCode.isNotEmpty && userCode == expectedCode) {
    return true;
  }

  final expectedName = _normalizeExactOfficeValue(office.name);
  final userOfficeName = _normalizeExactOfficeValue(
    user.hasCommission
        ? user.commissionOfficeName ?? ''
        : user.primaryOfficeName ?? user.officeName ?? user.unidad,
  );

  return expectedName.isNotEmpty && userOfficeName == expectedName;
}

bool _userMatchesCargo(AppUser user, CargoOption cargo) {
  final expectedCode = cargo.code.trim().toUpperCase();
  final userCode = (user.cargoCodigo ?? '').trim().toUpperCase();

  if (expectedCode.isNotEmpty && userCode == expectedCode) {
    return true;
  }

  final expectedName = _normalizeSearchText(cargo.name);
  final userCargo = _normalizeSearchText(user.cargo);

  return expectedName.isNotEmpty && userCargo == expectedName;
}

bool _isPorteroCargo(CargoOption? cargo) {
  if (cargo == null) {
    return false;
  }

  const porteroCargoCodes = {'CA116', 'CA082', 'CA096', 'CA087'};
  final normalizedCode = cargo.code.trim().toUpperCase();

  return porteroCargoCodes.contains(normalizedCode) ||
      _normalizeSearchText(cargo.name).startsWith('portero');
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

String _normalizeExactOfficeValue(String value) {
  return _stripTextAccents(
    value.trim().toLowerCase(),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _tipoVinculoLabel(String value) {
  switch (value.trim().toUpperCase()) {
    case 'ITEM':
      return 'Item';
    case 'EVENTUAL':
      return 'Eventual';
    case 'CONSULTOR':
      return 'Consultor';
    default:
      return value.trim().isEmpty ? '-' : value;
  }
}

String _normalizeSearchText(String value) {
  return _stripTextAccents(
    value.trim().toLowerCase(),
  ).replaceAll(RegExp(r'\s+'), ' ');
}

String _normalizeOfficeSearchText(String value) {
  return _normalizeSearchText(value)
      .replaceAll(RegExp(r'\bcomision\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripTextAccents(String value) {
  return value
      .replaceAll(RegExp(r'[áàäâãÁÀÄÂÃÃ¡Ã Ã¤Ã¢Ã£]'), 'a')
      .replaceAll(RegExp(r'[éèëêÉÈËÊÃ©Ã¨Ã«Ãª]'), 'e')
      .replaceAll(RegExp(r'[íìïîÍÌÏÎÃ­Ã¬Ã¯Ã®]'), 'i')
      .replaceAll(RegExp(r'[óòöôõÓÒÖÔÕÃ³Ã²Ã¶Ã´Ãµ]'), 'o')
      .replaceAll(RegExp(r'[úùüûÚÙÜÛÃºÃ¹Ã¼Ã»]'), 'u')
      .replaceAll(RegExp(r'[ñÑÃ±]'), 'n');
}

String _buildInitialPassword({
  required String primerApellido,
  required String ci,
}) {
  final prefix = _stripTextAccents(
    primerApellido,
  ).trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z]'), '');
  final normalizedCi = ci.trim().replaceAll(RegExp(r'\s+'), '');
  final passwordPrefix = prefix.length > 3 ? prefix.substring(0, 3) : prefix;

  return '$passwordPrefix$normalizedCi';
}

class _RequiredFieldLabel extends StatelessWidget {
  const _RequiredFieldLabel({
    required this.label,
    required this.isRequired,
    this.style,
  });

  final String label;
  final bool isRequired;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle =
        style ?? Theme.of(context).inputDecorationTheme.labelStyle;

    if (!isRequired) {
      return Text(label, style: resolvedStyle);
    }

    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: resolvedStyle,
        children: [
          TextSpan(text: label),
          const TextSpan(
            text: '*',
            style: TextStyle(color: Color(0xFFD94841)),
          ),
        ],
      ),
    );
  }
}

String? Function(String?) _requiredValidator(String message) {
  return (value) {
    if ((value ?? '').trim().isEmpty) {
      return message;
    }

    return null;
  };
}
