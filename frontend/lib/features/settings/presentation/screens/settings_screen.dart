import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart' as qr;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../auth/infrastructure/services/auth_api_service.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
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
    if (_isSavingProfile || _isSavingPhoto) {
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
    if (_isSavingProfile || _isSavingPhoto) {
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
      builder: (context) => _MyQrDialog(currentUser: widget.currentUser),
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
                              'Puedes actualizar tu foto, nombres y apellidos. El resto de los datos se mantiene de solo lectura.',
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
                          _isSavingPhoto ? 'Subiendo foto...' : 'Cambiar foto',
                        ),
                      ),
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
                    label: 'Correo electronico',
                    value: currentUser.email,
                    icon: Icons.alternate_email_rounded,
                  ),
                ],
              ),
            ),
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

class _MyQrDialog extends StatefulWidget {
  const _MyQrDialog({required this.currentUser});

  final AppUser currentUser;

  @override
  State<_MyQrDialog> createState() => _MyQrDialogState();
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
  const _CredentialErrorView({
    required this.message,
    required this.onRetry,
  });

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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFD94841),
            ),
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

class _MyQrDialogState extends State<_MyQrDialog> {
  Timer? _countdownTimer;
  DynamicQrSession? _dynamicQrSession;
  Duration _remaining = Duration.zero;
  bool _isGenerating = true;
  bool _isExporting = false;
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
      final dynamicQr = activeDynamicQr ?? await _generateFreshDynamicQr();

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

  Future<void> _downloadQrPdf(BuildContext context) async {
    final session = _dynamicQrSession;
    final qrPayload = session?.qrPayload;

    if (session == null || qrPayload == null || qrPayload.trim().isEmpty) {
      return;
    }

    if (_isExpired) {
      AppAlert.showWarning(
        context,
        'El QR ya caduco. Refrescalo antes de descargarlo.',
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final bytes = await _buildProfileQrPdf(
        widget.currentUser,
        qrPayload: qrPayload,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: _buildProfileQrFilename(widget.currentUser),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      AppAlert.showError(context, 'No fue posible descargar tu QR.');
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
            externalId: dynamicQrSession?.qrCode ?? currentUser.qrCode,
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
        ElevatedButton.icon(
          onPressed: _isExporting || _isGenerating || _isExpired
              ? null
              : () => _downloadQrPdf(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.orange,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          icon: _isExporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_isExporting ? 'Descargando...' : 'Descargar PDF'),
        ),
      ],
    );
  }
}

class _QrProfileCard extends StatelessWidget {
  const _QrProfileCard({
    required this.currentUser,
    required this.qrPayload,
    required this.externalId,
    required this.isGenerating,
    required this.isExpired,
    required this.remaining,
    required this.errorMessage,
    required this.onRefresh,
  });

  final AppUser currentUser;
  final String? qrPayload;
  final String? externalId;
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUser.fullName,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(color: Colors.white, fontSize: 28),
                          ),
                          if (currentUser.ci.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Text(
                                'CI: ${currentUser.ci}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _QrProfileInfoTile(
                            icon: Icons.work_outline_rounded,
                            label: 'Cargo',
                            value: _resolvedJobTitle(currentUser),
                          ),
                          const SizedBox(height: 10),
                          _QrProfileInfoTile(
                            icon: Icons.apartment_rounded,
                            label: 'Oficina',
                            value: _resolvedOfficeName(currentUser),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Base64Avatar(
                        size: 92,
                        fallbackLabel: currentUser.fullName,
                        photoSource: currentUser.fotoUrl,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
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
                      if ((externalId ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          'ID externo: $externalId',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
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

class _QrProfileInfoTile extends StatelessWidget {
  const _QrProfileInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.onDarkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<Uint8List> _buildProfileQrPdf(
  AppUser currentUser, {
  required String qrPayload,
}) async {
  final document = pw.Document();
  final photoBytes = await _resolvePhotoBytes(currentUser.fotoUrl);
  final photoImage = photoBytes == null ? null : pw.MemoryImage(photoBytes);
  // En PDF se vuelve a construir la matriz QR a partir del mismo payload del backend.
  final qrImage = _buildPdfQrImage(qrPayload);
  final pageFormat = PdfPageFormat(
    86 * PdfPageFormat.mm,
    150 * PdfPageFormat.mm,
    marginAll: 0,
  );

  document.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Container(
          width: pageFormat.width,
          height: pageFormat.height,
          color: const PdfColor.fromInt(0xFFF7F4FC),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(20),
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFFE6DFF2),
                width: 1.2,
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 10),
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFF6D56A0),
                    borderRadius: pw.BorderRadius.vertical(
                      top: pw.Radius.circular(19),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  currentUser.fullName,
                                  style: pw.TextStyle(
                                    color: PdfColors.white,
                                    fontSize: 15,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                if (currentUser.ci.trim().isNotEmpty) ...[
                                  pw.SizedBox(height: 6),
                                  pw.Text(
                                    'CI: ${currentUser.ci}',
                                    style: pw.TextStyle(
                                      color: const PdfColor.fromInt(0xFFF2EDFB),
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 10),
                          _buildPdfAvatar(
                            currentUser: currentUser,
                            photoImage: photoImage,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Container(
                        width: 216,
                        padding: const pw.EdgeInsets.all(5),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(16),
                          border: pw.Border.all(
                            color: const PdfColor.fromInt(0xFFE6DFF2),
                          ),
                        ),
                        child: qrImage != null
                            ? _buildPdfQrWidget(qrImage, 206)
                            : pw.Container(
                                width: 206,
                                height: 206,
                                alignment: pw.Alignment.center,
                                color: const PdfColor.fromInt(0xFFF8F6FC),
                                child: pw.Text(
                                  'QR no disponible',
                                  style: pw.TextStyle(
                                    color: const PdfColor.fromInt(0xFF4A396F),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Credencial personal QR',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          color: const PdfColor.fromInt(0xFF7C6E9E),
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  return document.save();
}

pw.Widget _buildPdfAvatar({
  required AppUser currentUser,
  required pw.MemoryImage? photoImage,
}) {
  return pw.Container(
    width: 58,
    height: 58,
    decoration: pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFEDE7F8),
      borderRadius: pw.BorderRadius.circular(14),
      image: photoImage == null
          ? null
          : pw.DecorationImage(image: photoImage, fit: pw.BoxFit.cover),
    ),
    alignment: pw.Alignment.center,
    child: photoImage == null
        ? pw.Text(
            currentUser.initial,
            style: pw.TextStyle(
              color: const PdfColor.fromInt(0xFF7D67B1),
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          )
        : null,
  );
}

qr.QrImage? _buildPdfQrImage(String payload) {
  if (payload.trim().isEmpty) {
    return null;
  }

  try {
    // Aqui no se interpreta el payload; solo se convierte a modulos QR para imprimirlo.
    final code = qr.QrCode.fromData(
      data: payload,
      errorCorrectLevel: qr.QrErrorCorrectLevel.L,
    );
    return qr.QrImage(code);
  } catch (_) {
    return null;
  }
}

pw.Widget _buildPdfQrWidget(qr.QrImage image, double size) {
  const quietZoneModules = 4;
  final totalModules = image.moduleCount + (quietZoneModules * 2);
  final cellSize = size / totalModules;

  // El PDF pinta manualmente cada modulo oscuro del QR para mantener control visual.
  return pw.CustomPaint(
    size: PdfPoint(size, size),
    painter: (canvas, canvasSize) {
      canvas.setFillColor(PdfColors.white);
      canvas.drawRect(0, 0, canvasSize.x, canvasSize.y);
      canvas.fillPath();

      canvas.setFillColor(const PdfColor.fromInt(0xFF4A396F));

      for (var row = 0; row < image.moduleCount; row++) {
        for (var col = 0; col < image.moduleCount; col++) {
          if (!image.isDark(row, col)) {
            continue;
          }

          final x = (col + quietZoneModules) * cellSize;
          final y = canvasSize.y - ((row + quietZoneModules + 1) * cellSize);

          canvas.drawRect(x, y, cellSize, cellSize);
          canvas.fillPath();
        }
      }
    },
  );
}

String _buildProfileQrFilename(AppUser currentUser) {
  final ci = currentUser.ci.trim();
  final fallbackName = currentUser.firstName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  final safeId = ci.isNotEmpty
      ? ci
      : (fallbackName.isEmpty ? 'usuario' : fallbackName);
  return 'qr-perfil-$safeId.pdf';
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

Future<Uint8List?> _resolvePhotoBytes(String? photoSource) async {
  if (photoSource == null || photoSource.trim().isEmpty) {
    return null;
  }

  final normalizedPhotoSource = photoSource.trim();
  final parsedUri = Uri.tryParse(normalizedPhotoSource);

  if (parsedUri != null &&
      (parsedUri.scheme == 'http' || parsedUri.scheme == 'https')) {
    try {
      final response = await http.get(parsedUri);

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        return Uint8List.fromList(response.bodyBytes);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  try {
    return base64Decode(normalizedPhotoSource);
  } catch (_) {
    return null;
  }
}

String _resolvedJobTitle(AppUser currentUser) {
  final jobTitle = currentUser.cargo.trim();
  return jobTitle.isEmpty ? 'Cargo no registrado' : jobTitle;
}

String _resolvedOfficeName(AppUser currentUser) {
  final officeName = (currentUser.officeName ?? '').trim().isNotEmpty
      ? currentUser.officeName!.trim()
      : currentUser.unidad.trim();
  return officeName.isEmpty ? 'Oficina no registrada' : officeName;
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
