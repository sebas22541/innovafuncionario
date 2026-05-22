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
  List<AppUser> _users = const [];
  List<OfficeOption> _offices = const [];
  List<CargoOption> _cargos = const [];
  bool _isLoading = true;
  bool _isCreating = false;
  final Set<int> _updatingUserIds = <int>{};
  String? _errorMessage;

  int get _adminCount => _users.where((user) => user.isAdmin).length;
  int get _controlCount => _users.where((user) => user.isControl).length;
  int get _externalCount =>
      _users.where((user) => user.isExternalUser).length;
  int get _activeUsersCount => _users.where((user) => user.activo).length;

  @override
  void initState() {
    super.initState();
    _loadData();
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
        _users = _sortUsers(results[0] as List<AppUser>);
        _offices = results[1] as List<OfficeOption>;
        _cargos = results[2] as List<CargoOption>;
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
    if (_offices.isEmpty || _cargos.isEmpty || _isCreating) {
      return;
    }

    final draft = await showDialog<_ManagedUserDraft>(
      context: context,
      builder: (context) =>
          _CreateManagedUserDialog(offices: _offices, cargos: _cargos),
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
        password: draft.password,
        nombreCompleto: draft.nombreCompleto,
        primerApellido: draft.primerApellido,
        segundoApellido: draft.segundoApellido,
        tercerApellido: draft.tercerApellido,
        ci: draft.ci,
        tipoVinculo: draft.tipoVinculo,
        oficinaId: draft.office.id,
        cargoCodigo: draft.cargo.code,
        unidad: draft.office.name,
        cargo: draft.cargo.name,
        numeroItem: draft.numeroItem,
        activo: draft.activo,
        fotoData: draft.fotoData,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = _sortUsers([createdUser, ..._users]);
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

  @override
  Widget build(BuildContext context) {
    final visibleUsers = _users;

    if (_isLoading && visibleUsers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && visibleUsers.isEmpty) {
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
                              'Aqui el administrador puede gestionar las cuentas con rol administrador, control y usuario externo.',
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _UserStatCard(
                        label: 'Administradores',
                        value: '$_adminCount',
                        icon: Icons.verified_user_outlined,
                      ),
                      _UserStatCard(
                        label: 'Control',
                        value: '$_controlCount',
                        icon: Icons.fact_check_outlined,
                      ),
                      _UserStatCard(
                        label: 'Externos',
                        value: '$_externalCount',
                        icon: Icons.person_outline_rounded,
                      ),
                      _UserStatCard(
                        label: 'Activos',
                        value: '$_activeUsersCount',
                        icon: Icons.verified_user_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _isCreating ? null : _openCreateDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    icon: _isCreating
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
                      _isCreating ? 'Creando usuario...' : 'Crear usuario',
                    ),
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
          if (visibleUsers.isEmpty)
            const _EmptyUsersState()
          else
            Column(
              children: [
                for (final user in visibleUsers) ...[
                  _UserListCard(
                    user: user,
                    isUpdating:
                        user.id != null && _updatingUserIds.contains(user.id),
                    onToggleActive: () => _toggleUserActive(user),
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

class _UserStatCard extends StatelessWidget {
  const _UserStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 185,
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
                Text(label, style: Theme.of(context).textTheme.bodySmall),
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
    required this.onToggleActive,
  });

  final AppUser user;
  final bool isUpdating;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Base64Avatar(
              size: 72,
              fallbackLabel: user.initial,
              photoSource: user.fotoUrl,
              borderRadius: BorderRadius.circular(18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        user.fullName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      _RoleChip(role: user.role),
                      _StatusChip(isActive: user.activo),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                      _UserMeta(label: 'Correo', value: user.email),
                      _UserMeta(
                        label: 'Oficina',
                        value: _resolvedOfficeName(user),
                      ),
                      _UserMeta(label: 'Cargo', value: user.cargo),
                      _UserMeta(
                        label: 'Tipo',
                        value: _tipoVinculoLabel(user.tipoVinculo),
                      ),
                      if (user.numeroItem.trim().isNotEmpty)
                        _UserMeta(label: 'Item', value: user.numeroItem),
                    ],
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

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final AppUserRole role;

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (role) {
      AppUserRole.admin => AppPalette.orange,
      AppUserRole.control => AppPalette.night,
      AppUserRole.external => AppPalette.muted,
    };
    final backgroundColor = switch (role) {
      AppUserRole.admin => AppPalette.orangeSoft,
      AppUserRole.control => AppPalette.blueSoftStrong,
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

class _CreateManagedUserDialog extends StatefulWidget {
  const _CreateManagedUserDialog({required this.offices, required this.cargos});

  final List<OfficeOption> offices;
  final List<CargoOption> cargos;

  @override
  State<_CreateManagedUserDialog> createState() =>
      _CreateManagedUserDialogState();
}

class _CreateManagedUserDialogState extends State<_CreateManagedUserDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _nombreCompletoController =
      TextEditingController();
  final TextEditingController _primerApellidoController =
      TextEditingController();
  final TextEditingController _segundoApellidoController =
      TextEditingController();
  final TextEditingController _tercerApellidoController =
      TextEditingController();
  final TextEditingController _unidadController = TextEditingController();
  final TextEditingController _cargoController = TextEditingController();
  final TextEditingController _numeroItemController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  AppUserRole _selectedRole = AppUserRole.control;
  String _selectedTipoVinculo = 'ITEM';
  bool _selectedActivo = true;
  OfficeOption? _selectedOffice;
  CargoOption? _selectedCargo;
  Uint8List? _photoBytes;
  bool _showPhotoError = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  @override
  void dispose() {
    _ciController.dispose();
    _nombreCompletoController.dispose();
    _primerApellidoController.dispose();
    _segundoApellidoController.dispose();
    _tercerApellidoController.dispose();
    _unidadController.dispose();
    _cargoController.dispose();
    _numeroItemController.dispose();
    _emailController.dispose();
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
    });
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

    if (_photoBytes == null) {
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
        nombreCompleto: _nombreCompletoController.text.trim(),
        primerApellido: _primerApellidoController.text.trim(),
        segundoApellido: _segundoApellidoController.text.trim(),
        tercerApellido: _tercerApellidoController.text.trim(),
        office: _selectedOffice!,
        cargo: _selectedCargo!,
        numeroItem: _numeroItemController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        fotoData: base64Encode(_photoBytes!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = _selectedRole.label.toLowerCase();

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
                      'Crear $roleLabel',
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
                        'Completa los mismos datos del registro principal y define si la cuenta sera de administrador, control o usuario externo.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      _DropdownField<AppUserRole>(
                        label: 'Rol del sistema',
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
                            value: AppUserRole.external,
                            child: Text('Usuario externo'),
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
                        validator: _requiredValidator('Ingresa el CI.'),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _nombreCompletoController,
                        label: 'Nombre completo',
                        hint: 'Ingresa los nombres',
                        validator: _requiredValidator('Ingresa los nombres.'),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _primerApellidoController,
                        label: 'Primer apellido',
                        hint: 'Ingresa el primer apellido',
                        validator: _requiredValidator(
                          'Ingresa el primer apellido.',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _segundoApellidoController,
                        label: 'Segundo apellido',
                        hint: 'Ingresa el segundo apellido',
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
                      const SizedBox(height: 14),
                      _PickerField(
                        controller: _cargoController,
                        label: 'Cargo',
                        hint: 'Selecciona un cargo registrado',
                        icon: Icons.badge_outlined,
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
                      if (_selectedTipoVinculo == 'ITEM') ...[
                        const SizedBox(height: 14),
                        _FormField(
                          controller: _numeroItemController,
                          label: 'Numero item',
                          hint: 'Ingresa el numero item',
                          validator: _requiredValidator(
                            'Ingresa el numero item.',
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _DropdownField<bool>(
                        label: 'Estado',
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
                        showError: _showPhotoError,
                        onPickPhoto: _pickPhoto,
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _emailController,
                        label: 'Correo',
                        hint: _selectedRole == AppUserRole.admin
                            ? 'usuario@admin.com'
                            : 'usuario@correo.com',
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          final email = value?.trim().toLowerCase() ?? '';

                          if (email.isEmpty || !email.contains('@')) {
                            return 'Ingresa un correo valido.';
                          }

                          if (_selectedRole == AppUserRole.admin &&
                              !email.contains('@admin')) {
                            return 'El administrador debe usar un correo con @admin.';
                          }

                          if (_selectedRole != AppUserRole.admin &&
                              email.contains('@admin')) {
                            return 'Solo el administrador puede usar un correo con @admin.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _passwordController,
                        label: 'Contrasena',
                        hint: 'Minimo 6 caracteres',
                        obscureText: _hidePassword,
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
                          if ((value ?? '').trim().length < 6) {
                            return 'La contrasena debe tener al menos 6 caracteres.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _FormField(
                        controller: _confirmPasswordController,
                        label: 'Confirmar contrasena',
                        hint: 'Repite la contrasena',
                        obscureText: _hideConfirmPassword,
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
                          if ((value ?? '').trim() !=
                              _passwordController.text.trim()) {
                            return 'Las contrasenas no coinciden.';
                          }

                          return null;
                        },
                        onFieldSubmitted: (_) => _submit(),
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
                    child: const Text('Crear usuario'),
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
    required this.nombreCompleto,
    required this.primerApellido,
    required this.segundoApellido,
    required this.tercerApellido,
    required this.office,
    required this.cargo,
    required this.numeroItem,
    required this.email,
    required this.password,
    required this.fotoData,
  });

  final AppUserRole role;
  final String tipoVinculo;
  final bool activo;
  final String ci;
  final String nombreCompleto;
  final String primerApellido;
  final String segundoApellido;
  final String tercerApellido;
  final OfficeOption office;
  final CargoOption cargo;
  final String numeroItem;
  final String email;
  final String password;
  final String fotoData;
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
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
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
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
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Future<void> Function() onTap;
  final String? Function(String?) validator;

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
            Text(label, style: Theme.of(context).textTheme.bodySmall),
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
                      child: Text(
                        hasValue ? controller.text.trim() : hint,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: hasValue ? AppPalette.night : AppPalette.muted,
                        ),
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
    required this.showError,
    required this.onPickPhoto,
  });

  final Uint8List? photoBytes;
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
                        ? Container(
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
                            ? 'Selecciona una foto'
                            : 'Foto cargada correctamente',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'La foto es obligatoria para crear el usuario.',
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
  });

  final List<OfficeOption> offices;
  final OfficeOption? selectedOffice;

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
    final query = _searchController.text.trim().toLowerCase();
    final filteredOffices = widget.offices
        .where((office) {
          if (query.isEmpty) {
            return true;
          }

          return office.name.toLowerCase().contains(query) ||
              office.code.toLowerCase().contains(query) ||
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
                          'Selecciona la unidad',
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
                      labelText: 'Buscar unidad',
                      hintText: 'Escribe nombre, codigo o nivel',
                      prefixIcon: Icon(Icons.search_rounded),
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
    case AppUserRole.external:
      return 2;
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

String? Function(String?) _requiredValidator(String message) {
  return (value) {
    if ((value ?? '').trim().isEmpty) {
      return message;
    }

    return null;
  };
}
