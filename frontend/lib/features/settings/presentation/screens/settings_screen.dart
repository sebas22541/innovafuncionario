import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../auth/infrastructure/services/auth_api_service.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/infrastructure/location_permission_settings.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/base64_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.currentUser,
    required this.onUserUpdated,
    required this.onLogout,
  });

  final AppUser currentUser;
  final ValueChanged<AppUser> onUserUpdated;
  final VoidCallback onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSavingProfile = false;
  bool _isSavingPhoto = false;
  bool _isDownloadingCredential = false;
  bool _isChangingPassword = false;
  bool _isLoadingLocationPreference = true;
  bool _isUpdatingLocationPermission = false;
  bool _isLocationEnabled = false;
  bool _isLocationServiceEnabled = false;
  LocationPermission _locationPermission = LocationPermission.denied;

  @override
  void initState() {
    super.initState();
    _loadLocationSettings();
  }

  Future<void> _loadLocationSettings() async {
    try {
      final enabled = await LocationPermissionSettings.isEnabled();
      final serviceEnabled =
          await LocationPermissionSettings.isServiceEnabled();
      final permission = await LocationPermissionSettings.checkPermission();

      if (!mounted) {
        return;
      }

      setState(() {
        _isLocationEnabled = enabled;
        _isLocationServiceEnabled = serviceEnabled;
        _locationPermission = permission;
        _isLoadingLocationPreference = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingLocationPreference = false;
      });
    }
  }

  Future<void> _setLocationEnabled(bool enabled) async {
    if (_isUpdatingLocationPermission) {
      return;
    }

    setState(() {
      _isUpdatingLocationPermission = true;
    });

    try {
      var permission = await LocationPermissionSettings.checkPermission();
      final serviceEnabled =
          await LocationPermissionSettings.isServiceEnabled();

      if (enabled && permission == LocationPermission.denied) {
        permission = await LocationPermissionSettings.requestPermission();
      }

      await LocationPermissionSettings.setEnabled(enabled);

      if (!mounted) {
        return;
      }

      setState(() {
        _isLocationEnabled = enabled;
        _isLocationServiceEnabled = serviceEnabled;
        _locationPermission = permission;
      });

      if (!enabled) {
        AppAlert.showSuccess(context, 'Ubicacion deshabilitada en la app.');
      } else if (permission.isAllowed && serviceEnabled) {
        AppAlert.showSuccess(context, 'Ubicacion habilitada.');
      } else {
        AppAlert.showWarning(
          context,
          'No se concedio el permiso de ubicacion. Revisa los ajustes del dispositivo o navegador.',
        );
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(
          context,
          'No fue posible actualizar la configuracion de ubicacion.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingLocationPermission = false;
          _isLoadingLocationPreference = false;
        });
      }
    }
  }

  Future<void> _openLocationSettings() async {
    await LocationPermissionSettings.openLocationSettings();
    await _loadLocationSettings();
  }

  Future<void> _openAppSettings() async {
    await LocationPermissionSettings.openAppSettings();
    await _loadLocationSettings();
  }

  Future<AppUser> _updateProfile({
    required String nombreCompleto,
    required String primerApellido,
    required String segundoApellido,
    required String tercerApellido,
    String? fotoData,
  }) {
    return dependencies.authApiService.updateProfileNames(
      email: widget.currentUser.email,
      nombreCompleto: nombreCompleto,
      primerApellido: primerApellido,
      segundoApellido: segundoApellido,
      tercerApellido: tercerApellido,
      fotoData: fotoData,
    );
  }

  Future<void> _openEditProfileDialog() async {
    if (!widget.currentUser.isAdmin ||
        _isSavingProfile ||
        _isSavingPhoto) {
      return;
    }

    final draft = await showDialog<_ProfileNameDraft>(
      context: context,
      builder: (context) => _EditProfileDialog(currentUser: widget.currentUser),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _isSavingProfile = true;
    });

    try {
      final updatedUser = await _updateProfile(
        nombreCompleto: draft.nombreCompleto,
        primerApellido: draft.primerApellido,
        segundoApellido: draft.segundoApellido,
        tercerApellido: draft.tercerApellido,
      );

      if (!mounted) {
        return;
      }

      widget.onUserUpdated(updatedUser);
      AppAlert.showSuccess(context, 'Perfil actualizado.');
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible actualizar el perfil.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProfile = false;
        });
      }
    }
  }

  Future<void> _pickProfilePhoto() async {
    if (!widget.currentUser.isAdmin ||
        _isSavingProfile ||
        _isSavingPhoto) {
      return;
    }

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
      _isSavingPhoto = true;
    });

    try {
      final updatedUser = await _updateProfile(
        nombreCompleto: widget.currentUser.nombreCompleto,
        primerApellido: widget.currentUser.primerApellido,
        segundoApellido: widget.currentUser.segundoApellido,
        tercerApellido: widget.currentUser.tercerApellido,
        fotoData: base64Encode(bytes),
      );

      if (!mounted) {
        return;
      }

      widget.onUserUpdated(updatedUser);
      AppAlert.showSuccess(context, 'Foto de perfil actualizada.');
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
        'No fue posible actualizar la foto de perfil.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPhoto = false;
        });
      }
    }
  }

  Future<void> _openChangePasswordDialog() async {
    if (_isChangingPassword) {
      return;
    }

    final draft = await showDialog<_PasswordChangeDraft>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _isChangingPassword = true;
    });

    try {
      await dependencies.authApiService.updatePassword(
        currentPassword: draft.currentPassword,
        newPassword: draft.newPassword,
        confirmPassword: draft.confirmPassword,
      );

      if (!mounted) {
        return;
      }

      AppAlert.showSuccess(context, 'Contrasena actualizada.');
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible cambiar la contrasena.');
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _openMyQrDialog() async {
    if (!widget.currentUser.hasQr) {
      AppAlert.showWarning(
        context,
        'Tu QR todavia no esta disponible. Vuelve a iniciar sesion.',
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => MyQrDialog(currentUser: widget.currentUser),
    );
  }

  Future<void> _downloadCredentialDirectly() async {
    if (_isDownloadingCredential) {
      return;
    }

    setState(() {
      _isDownloadingCredential = true;
    });

    try {
      final pdfBytes = await dependencies.authApiService.downloadCredentialPdf(
        email: widget.currentUser.email,
      );

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: _buildCredentialFilename(widget.currentUser),
      );
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible descargar la credencial.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingCredential = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.currentUser;

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
                      Base64Avatar(
                        size: 88,
                        fallbackLabel: currentUser.initial,
                        photoSource: currentUser.fotoUrl,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mis datos',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              !currentUser.isAdmin
                                  ? 'Tus datos se mantienen de solo lectura.'
                                  : 'Puedes actualizar tu foto, nombres y apellidos. El resto de los datos se mantiene de solo lectura.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              currentUser.fullName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (currentUser.isAdmin) ...[
                        OutlinedButton.icon(
                          onPressed: _isSavingProfile || _isSavingPhoto
                              ? null
                              : _openEditProfileDialog,
                          icon: _isSavingProfile
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.edit_outlined),
                          label: Text(
                            _isSavingProfile
                                ? 'Guardando...'
                                : 'Editar nombres y apellidos',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSavingProfile || _isSavingPhoto
                              ? null
                              : _pickProfilePhoto,
                          icon: _isSavingPhoto
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.photo_camera_outlined),
                          label: Text(
                            _isSavingPhoto
                                ? 'Subiendo foto...'
                                : 'Cambiar foto',
                          ),
                        ),
                      ],
                      ElevatedButton.icon(
                        onPressed: _openMyQrDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('Mi QR'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isChangingPassword
                            ? null
                            : _openChangePasswordDialog,
                        icon: _isChangingPassword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_reset_rounded),
                        label: Text(
                          _isChangingPassword
                              ? 'Actualizando...'
                              : 'Cambiar contrasena',
                        ),
                      ),
                      if (currentUser.isAdmin)
                        ElevatedButton.icon(
                          onPressed: _isDownloadingCredential
                              ? null
                              : _downloadCredentialDirectly,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.night,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          icon: _isDownloadingCredential
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.download_rounded),
                          label: Text(
                            _isDownloadingCredential
                                ? 'Descargando...'
                                : 'Credencial',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _UserDataRow(
                    label: 'Tipo',
                    value: _tipoVinculoLabel(currentUser.tipoVinculo),
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Rol del sistema',
                    value: currentUser.roleLabel,
                    icon: Icons.admin_panel_settings_outlined,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'CI',
                    value: currentUser.ci,
                    icon: Icons.credit_card_rounded,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Nombres',
                    value: currentUser.nombreCompleto,
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Primer apellido',
                    value: currentUser.primerApellido,
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Segundo apellido',
                    value: currentUser.segundoApellido,
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Tercer apellido',
                    value: currentUser.tercerApellido,
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Oficina',
                    value: _resolvedOfficeName(currentUser),
                    icon: Icons.account_tree_outlined,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Cargo',
                    value: currentUser.cargo,
                    icon: Icons.work_outline_rounded,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Numero item',
                    value: currentUser.numeroItem,
                    icon: Icons.confirmation_number_outlined,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Estado',
                    value: currentUser.estadoLabel,
                    icon: Icons.toggle_on_outlined,
                  ),
                  const SizedBox(height: 14),
                  _UserDataRow(
                    label: 'Usuario de acceso',
                    value: currentUser.email,
                    icon: Icons.alternate_email_rounded,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _LocationSettingsCard(
            isLoading: _isLoadingLocationPreference,
            isUpdating: _isUpdatingLocationPermission,
            isEnabled: _isLocationEnabled,
            isServiceEnabled: _isLocationServiceEnabled,
            permission: _locationPermission,
            onChanged: _setLocationEnabled,
            onOpenLocationSettings: _openLocationSettings,
            onOpenAppSettings: _openAppSettings,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onLogout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesion'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationSettingsCard extends StatelessWidget {
  const _LocationSettingsCard({
    required this.isLoading,
    required this.isUpdating,
    required this.isEnabled,
    required this.isServiceEnabled,
    required this.permission,
    required this.onChanged,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final bool isLoading;
  final bool isUpdating;
  final bool isEnabled;
  final bool isServiceEnabled;
  final LocationPermission permission;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final canUseLocation = isEnabled && isServiceEnabled && permission.isAllowed;
    final status = isLoading
        ? 'Consultando configuracion...'
        : canUseLocation
        ? 'Ubicacion activa'
        : _locationStatusLabel(isEnabled, isServiceEnabled, permission);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppPalette.orangeSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppPalette.orange,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuracion de ubicacion',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Controla si la app puede pedir y usar tu ubicacion para QR dinamico, asistencias y mapas.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (isLoading || isUpdating)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: isEnabled,
                    activeThumbColor: AppPalette.orange,
                    onChanged: onChanged,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _UserDataRow(
              label: 'Estado',
              value: status,
              icon: canUseLocation
                  ? Icons.check_circle_outline_rounded
                  : Icons.location_off_rounded,
            ),
            if (!isLoading &&
                isEnabled &&
                (!isServiceEnabled || !permission.isAllowed)) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!isServiceEnabled)
                    OutlinedButton.icon(
                      onPressed: onOpenLocationSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Ajustes de ubicacion'),
                    ),
                  if (!permission.isAllowed)
                    OutlinedButton.icon(
                      onPressed: onOpenAppSettings,
                      icon: const Icon(Icons.app_settings_alt_rounded),
                      label: const Text('Permisos de la app'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MyQrDialog extends StatefulWidget {
  const MyQrDialog({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<MyQrDialog> createState() => _MyQrDialogState();
}

class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  UserCredential? _credential;
  bool _isGenerating = true;
  bool _isDownloading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _generateCredential();
  }

  Future<void> _generateCredential() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final credential = await dependencies.authApiService.generateCredential(
        email: widget.currentUser.email,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _credential = credential;
        _isGenerating = false;
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isGenerating = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isGenerating = false;
        _errorMessage = 'No fue posible generar tu credencial.';
      });
    }
  }

  Future<void> _downloadCredentialPdf() async {
    final credential = _credential;

    if (credential == null || _isDownloading) {
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      final pdfBytes = await dependencies.authApiService.downloadCredentialPdf(
        email: widget.currentUser.email,
      );

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: _buildCredentialFilename(widget.currentUser),
      );
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible descargar la credencial.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _copyCredentialLink() async {
    final link = _credential?.frontImageUrl;

    if (link == null || link.trim().isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: link));

    if (mounted) {
      AppAlert.showSuccess(context, 'Enlace de credencial copiado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final credential = _credential;

    return AlertDialog(
      title: const Text('Mi credencial'),
      content: SizedBox(
        width: 560,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _isGenerating
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 46),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _errorMessage != null
              ? _CredentialErrorView(
                  message: _errorMessage!,
                  onRetry: _generateCredential,
                )
              : _CredentialPreview(credential: credential!),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        if (credential != null) ...[
          OutlinedButton.icon(
            onPressed: _copyCredentialLink,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Copiar enlace'),
          ),
          ElevatedButton.icon(
            onPressed: _isDownloading ? null : _downloadCredentialPdf,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.orange,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_isDownloading ? 'Descargando...' : 'Descargar PDF'),
          ),
        ],
      ],
    );
  }
}

class _CredentialPreview extends StatelessWidget {
  const _CredentialPreview({required this.credential});

  final UserCredential credential;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 860 / 540,
            child: Image.network(
              credential.frontImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppPalette.surfaceSoft,
                  alignment: Alignment.center,
                  child: const Text('Vista previa no disponible.'),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        SelectableText(
          credential.frontImageUrl,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CredentialErrorView extends StatelessWidget {
  const _CredentialErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFD94841),
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFD94841)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _MyQrDialogState extends State<MyQrDialog> {
  static const Duration _minimumReusableQrTime = Duration(seconds: 15);

  Timer? _countdownTimer;
  DynamicQrSession? _dynamicQrSession;
  Duration _remaining = Duration.zero;
  bool _isGenerating = true;
  String? _generationError;

  @override
  void initState() {
    super.initState();
    _ensureDynamicQrAvailable();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool get _isExpired {
    final session = _dynamicQrSession;

    if (session == null) {
      return false;
    }

    return DateTime.now().isAfter(session.expiresAt) ||
        _remaining == Duration.zero;
  }

  Future<void> _ensureDynamicQrAvailable() async {
    _countdownTimer?.cancel();

    setState(() {
      _isGenerating = true;
      _generationError = null;
    });

    try {
      final activeDynamicQr = await dependencies.authApiService
          .fetchActiveDynamicQr(email: widget.currentUser.email);
      final dynamicQr = _hasEnoughTimeToScan(activeDynamicQr)
          ? activeDynamicQr!
          : await _generateFreshDynamicQr();

      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = dynamicQr;
        _remaining = _resolveRemaining(dynamicQr.expiresAt);
        _isGenerating = false;
        _generationError = null;
      });

      _startCountdown(dynamicQr.expiresAt);
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = null;
        _remaining = Duration.zero;
        _isGenerating = false;
        _generationError = error.message;
      });
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = null;
        _remaining = Duration.zero;
        _isGenerating = false;
        _generationError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = null;
        _remaining = Duration.zero;
        _isGenerating = false;
        _generationError = 'No fue posible generar tu QR dinamico.';
      });
    }
  }

  Future<void> _refreshDynamicQr() async {
    _countdownTimer?.cancel();

    setState(() {
      _isGenerating = true;
      _generationError = null;
    });

    try {
      final dynamicQr = await _generateFreshDynamicQr();

      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = dynamicQr;
        _remaining = _resolveRemaining(dynamicQr.expiresAt);
        _isGenerating = false;
        _generationError = null;
      });

      _startCountdown(dynamicQr.expiresAt);
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = null;
        _remaining = Duration.zero;
        _isGenerating = false;
        _generationError = error.message;
      });
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = null;
        _remaining = Duration.zero;
        _isGenerating = false;
        _generationError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dynamicQrSession = null;
        _remaining = Duration.zero;
        _isGenerating = false;
        _generationError = 'No fue posible generar tu QR dinamico.';
      });
    }
  }

  bool _hasEnoughTimeToScan(DynamicQrSession? session) {
    if (session == null) {
      return false;
    }

    return session.expiresAt.difference(DateTime.now()) >
        _minimumReusableQrTime;
  }

  Future<DynamicQrSession> _generateFreshDynamicQr() async {
    final location = await _resolveCurrentLocation();
    return dependencies.authApiService.generateDynamicQr(
      email: widget.currentUser.email,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
    );
  }

  Future<_QrGenerationLocationSnapshot> _resolveCurrentLocation() async {
    final isLocationEnabled = await LocationPermissionSettings.isEnabled();

    if (!isLocationEnabled) {
      throw StateError(
        'Habilita la ubicacion en Configuracion para generar el QR dinamico.',
      );
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw StateError('Activa tu ubicacion para generar el QR dinamico.');
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

    return _QrGenerationLocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }

  void _startCountdown(DateTime expiresAt) {
    _countdownTimer?.cancel();

    void tick() {
      if (!mounted) {
        return;
      }

      final remaining = _resolveRemaining(expiresAt);

      setState(() {
        _remaining = remaining;
      });

      if (remaining == Duration.zero) {
        _countdownTimer?.cancel();
      }
    }

    tick();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Duration _resolveRemaining(DateTime expiresAt) {
    final difference = expiresAt.difference(DateTime.now());

    if (difference.isNegative || difference == Duration.zero) {
      return Duration.zero;
    }

    return Duration(seconds: difference.inSeconds + 1);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.currentUser;
    final dynamicQrSession = _dynamicQrSession;

    return AlertDialog(
      backgroundColor: AppPalette.surface,
      title: const Text('Mi QR'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: _QrProfileCard(
            currentUser: currentUser,
            qrPayload: dynamicQrSession?.qrPayload,
            isGenerating: _isGenerating,
            isExpired: _isExpired,
            remaining: _remaining,
            errorMessage: _generationError,
            onRefresh: _isGenerating ? null : _refreshDynamicQr,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _QrProfileCard extends StatelessWidget {
  const _QrProfileCard({
    required this.currentUser,
    required this.qrPayload,
    required this.isGenerating,
    required this.isExpired,
    required this.remaining,
    required this.errorMessage,
    required this.onRefresh,
  });

  final AppUser currentUser;
  final String? qrPayload;
  final bool isGenerating;
  final bool isExpired;
  final Duration remaining;
  final String? errorMessage;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final resolvedQrPayload = qrPayload ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppPalette.nightDeep, AppPalette.night],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppPalette.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1854407E),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -12,
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Color(0x1DFFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -24,
            bottom: 88,
            child: Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: Color(0x18FFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credencial QR',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppPalette.onDarkMuted,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  currentUser.fullName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppPalette.line),
                  ),
                  child: Column(
                    children: [
                      _QrStatusBanner(
                        isGenerating: isGenerating,
                        isExpired: isExpired,
                        remaining: remaining,
                      ),
                      const SizedBox(height: 14),
                      if (isGenerating)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 52),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Generando QR...',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.location_off_rounded,
                                size: 42,
                                color: Color(0xFFD94841),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFFD94841)),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: onRefresh == null
                                    ? null
                                    : () => onRefresh!.call(),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      else
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: isExpired ? 0.20 : 1,
                              child: IgnorePointer(
                                ignoring: isExpired,
                                child: QrImageView(
                                  data: resolvedQrPayload,
                                  size: 236,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: AppPalette.ink,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: AppPalette.ink,
                                  ),
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                            if (isExpired)
                              Container(
                                width: 220,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: AppPalette.line),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.timer_off_rounded,
                                      color: Color(0xFFD94841),
                                      size: 32,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'QR caduco',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: const Color(0xFFD94841),
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Genera uno nuevo para volver a escanearlo.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: onRefresh == null
                                          ? null
                                          : () => onRefresh!.call(),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Refrescar QR'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Text(
                        isExpired
                            ? 'Este QR ya no se puede usar hasta que lo refresques.'
                            : 'Escanea este codigo para registrar tu asistencia.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppPalette.ink),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrStatusBanner extends StatelessWidget {
  const _QrStatusBanner({
    required this.isGenerating,
    required this.isExpired,
    required this.remaining,
  });

  final bool isGenerating;
  final bool isExpired;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isExpired
        ? const Color(0xFFFDECEC)
        : isGenerating
        ? AppPalette.surfaceSoft
        : const Color(0xFFEAF7EF);
    final foregroundColor = isExpired
        ? const Color(0xFFD94841)
        : isGenerating
        ? AppPalette.ink
        : const Color(0xFF18794E);
    final label = isExpired
        ? 'QR caduco'
        : isGenerating
        ? 'Generando QR'
        : 'Vence en ${_formatDuration(remaining)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isExpired
                ? Icons.timer_off_rounded
                : isGenerating
                ? Icons.autorenew_rounded
                : Icons.timer_outlined,
            color: foregroundColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds <= 0 ? 0 : duration.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');

  return '$minutes:$seconds';
}

class _QrGenerationLocationSnapshot {
  const _QrGenerationLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
}

String _buildCredentialFilename(AppUser currentUser) {
  final ci = currentUser.ci.trim();
  final fallbackName = currentUser.firstName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final safeId = ci.isNotEmpty
      ? ci
      : (fallbackName.isEmpty ? 'usuario' : fallbackName);

  return 'credencial-$safeId.pdf';
}

String _resolvedOfficeName(AppUser currentUser) {
  final officeName = (currentUser.officeName ?? '').trim().isNotEmpty
      ? currentUser.officeName!.trim()
      : currentUser.unidad.trim();
  return officeName.isEmpty ? 'Oficina no registrada' : officeName;
}

String _locationStatusLabel(
  bool isEnabled,
  bool isServiceEnabled,
  LocationPermission permission,
) {
  if (!isEnabled) {
    return 'Deshabilitada en la app';
  }

  if (!isServiceEnabled) {
    return 'El servicio de ubicacion esta apagado';
  }

  if (permission == LocationPermission.deniedForever) {
    return 'Permiso bloqueado en el dispositivo o navegador';
  }

  if (!permission.isAllowed) {
    return 'Permiso pendiente';
  }

  return 'Ubicacion activa';
}

class _ProfileNameDraft {
  const _ProfileNameDraft({
    required this.nombreCompleto,
    required this.primerApellido,
    required this.segundoApellido,
    required this.tercerApellido,
  });

  final String nombreCompleto;
  final String primerApellido;
  final String segundoApellido;
  final String tercerApellido;
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCompletoController;
  late final TextEditingController _primerApellidoController;
  late final TextEditingController _segundoApellidoController;
  late final TextEditingController _tercerApellidoController;

  @override
  void initState() {
    super.initState();
    _nombreCompletoController = TextEditingController(
      text: widget.currentUser.nombreCompleto,
    );
    _primerApellidoController = TextEditingController(
      text: widget.currentUser.primerApellido,
    );
    _segundoApellidoController = TextEditingController(
      text: widget.currentUser.segundoApellido,
    );
    _tercerApellidoController = TextEditingController(
      text: widget.currentUser.tercerApellido,
    );
  }

  @override
  void dispose() {
    _nombreCompletoController.dispose();
    _primerApellidoController.dispose();
    _segundoApellidoController.dispose();
    _tercerApellidoController.dispose();
    super.dispose();
  }

  void _submit() {
    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      return;
    }

    Navigator.of(context).pop(
      _ProfileNameDraft(
        nombreCompleto: _nombreCompletoController.text.trim(),
        primerApellido: _primerApellidoController.text.trim(),
        segundoApellido: _segundoApellidoController.text.trim(),
        tercerApellido: _tercerApellidoController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar perfil'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aqui solo puedes actualizar nombres y apellidos.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nombreCompletoController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nombres'),
                  validator: _requiredValidator('Ingresa tus nombres.'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _primerApellidoController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Primer apellido',
                  ),
                  validator: _requiredValidator('Ingresa tu primer apellido.'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _segundoApellidoController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Segundo apellido',
                  ),
                  validator: _requiredValidator('Ingresa tu segundo apellido.'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tercerApellidoController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Tercer apellido',
                    hintText: 'Opcional',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().length > 80) {
                      return 'El tercer apellido es demasiado largo.';
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.orange,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PasswordChangeDraft {
  const _PasswordChangeDraft({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  final String currentPassword;
  final String newPassword;
  final String confirmPassword;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _hideCurrentPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      return;
    }

    Navigator.of(context).pop(
      _PasswordChangeDraft(
        currentPassword: _currentPasswordController.text.trim(),
        newPassword: _newPasswordController.text.trim(),
        confirmPassword: _confirmPasswordController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contrasena'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _hideCurrentPassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Contrasena actual',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _hideCurrentPassword = !_hideCurrentPassword;
                      });
                    },
                    icon: Icon(
                      _hideCurrentPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: _passwordValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _hideNewPassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Nueva contrasena',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _hideNewPassword = !_hideNewPassword;
                      });
                    },
                    icon: Icon(
                      _hideNewPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  final message = _passwordValidator(value);

                  if (message != null) {
                    return message;
                  }

                  if ((value ?? '').trim() ==
                      _currentPasswordController.text.trim()) {
                    return 'La nueva contrasena debe ser diferente.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _hideConfirmPassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Confirmar nueva contrasena',
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
                ),
                validator: (value) {
                  if ((value ?? '').trim() !=
                      _newPasswordController.text.trim()) {
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.orange,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _UserDataRow extends StatelessWidget {
  const _UserDataRow({
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
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
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
            child: Icon(icon, color: AppPalette.orange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _tipoVinculoLabel(String value) {
  switch (value) {
    case 'EVENTUAL':
      return 'Eventual';
    case 'CONSULTOR':
      return 'Consultor';
    default:
      return 'Item';
  }
}

String? Function(String?) _requiredValidator(String message) {
  return (value) {
    if ((value ?? '').trim().length < 2) {
      return message;
    }

    return null;
  };
}

String? _passwordValidator(String? value) {
  if ((value ?? '').trim().length < 6) {
    return 'La contrasena debe tener al menos 6 caracteres.';
  }

  return null;
}
