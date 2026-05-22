import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../domain/entities/cargo_option.dart';
import '../../domain/entities/office_option.dart';

enum _AuthStage { welcome, login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});

  final ValueChanged<AppUser> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _formScrollController = ScrollController();
  final TextEditingController _nombreCompletoController =
      TextEditingController();
  final TextEditingController _primerApellidoController =
      TextEditingController();
  final TextEditingController _segundoApellidoController =
      TextEditingController();
  final TextEditingController _tercerApellidoController =
      TextEditingController();
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _unidadController = TextEditingController();
  final TextEditingController _cargoController = TextEditingController();
  final TextEditingController _numeroItemController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  _AuthStage _stage = _AuthStage.welcome;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _isSubmitting = false;
  bool _showPhotoError = false;
  bool _acceptedTerms = false;
  bool _showTermsError = false;
  String _selectedTipoVinculo = 'ITEM';
  final bool _selectedActivo = true;
  Uint8List? _photoBytes;
  List<OfficeOption> _availableOffices = const [];
  OfficeOption? _selectedOffice;
  bool _isLoadingOffices = false;
  String? _officeLoadError;
  List<CargoOption> _availableCargos = const [];
  CargoOption? _selectedCargo;
  bool _isLoadingCargos = false;
  String? _cargoLoadError;

  @override
  void initState() {
    super.initState();
    _loadOffices();
    _loadCargos();
  }

  @override
  void dispose() {
    _formScrollController.dispose();
    _nombreCompletoController.dispose();
    _primerApellidoController.dispose();
    _segundoApellidoController.dispose();
    _tercerApellidoController.dispose();
    _ciController.dispose();
    _unidadController.dispose();
    _cargoController.dispose();
    _numeroItemController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isRegisterMode => _stage == _AuthStage.register;

  void _setStage(_AuthStage stage) {
    if (_stage == stage) {
      return;
    }

    setState(() {
      _stage = stage;
      _showPhotoError = false;
      _showTermsError = false;
    });

    if (stage == _AuthStage.register) {
      if (_availableOffices.isEmpty && !_isLoadingOffices) {
        _loadOffices();
      }

      if (_availableCargos.isEmpty && !_isLoadingCargos) {
        _loadCargos();
      }
    }
  }

  Future<void> _loadOffices() async {
    if (mounted) {
      setState(() {
        _isLoadingOffices = true;
        _officeLoadError = null;
      });
    }

    try {
      final offices = await dependencies.authApiService.fetchOffices();

      if (!mounted) {
        return;
      }

      OfficeOption? selectedOffice;
      if (_selectedOffice != null) {
        for (final office in offices) {
          if (office.id == _selectedOffice!.id) {
            selectedOffice = office;
            break;
          }
        }
      }

      setState(() {
        _availableOffices = offices;
        _selectedOffice = selectedOffice;
        _unidadController.text = selectedOffice?.name ?? '';
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _officeLoadError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _officeLoadError =
            'No fue posible cargar las unidades desde la base de datos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOffices = false;
        });
      }
    }
  }

  Future<void> _loadCargos() async {
    if (mounted) {
      setState(() {
        _isLoadingCargos = true;
        _cargoLoadError = null;
      });
    }

    try {
      final cargos = await dependencies.authApiService.fetchCargos();

      if (!mounted) {
        return;
      }

      CargoOption? selectedCargo;
      if (_selectedCargo != null) {
        for (final cargo in cargos) {
          if (cargo.code == _selectedCargo!.code) {
            selectedCargo = cargo;
            break;
          }
        }
      }

      setState(() {
        _availableCargos = cargos;
        _selectedCargo = selectedCargo;
        _cargoController.text = selectedCargo?.name ?? '';
      });
    } on BackendApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _cargoLoadError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _cargoLoadError =
            'No fue posible cargar los cargos desde la base de datos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCargos = false;
        });
      }
    }
  }

  Future<void> _pickOffice() async {
    if (_isLoadingOffices) {
      return;
    }

    if (_availableOffices.isEmpty) {
      AppAlert.showWarning(
        context,
        _officeLoadError ?? 'No hay unidades disponibles en la base de datos.',
      );
      return;
    }

    final office = await showModalBottomSheet<OfficeOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OfficeSelectionSheet(
        offices: _availableOffices,
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
    if (_isLoadingCargos) {
      return;
    }

    if (_availableCargos.isEmpty) {
      AppAlert.showWarning(
        context,
        _cargoLoadError ?? 'No hay cargos disponibles en la base de datos.',
      );
      return;
    }

    final cargo = await showModalBottomSheet<CargoOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CargoSelectionSheet(
        cargos: _availableCargos,
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

  Future<void> _submit() async {
    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      return;
    }

    if (_isRegisterMode && _photoBytes == null) {
      setState(() {
        _showPhotoError = true;
      });
      return;
    }

    if (_isRegisterMode && !_acceptedTerms) {
      setState(() {
        _showTermsError = true;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = _isRegisterMode
          ? await dependencies.authApiService.register(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
              nombreCompleto: _nombreCompletoController.text.trim(),
              primerApellido: _primerApellidoController.text.trim(),
              segundoApellido: _segundoApellidoController.text.trim(),
              tercerApellido: _tercerApellidoController.text.trim(),
              ci: _ciController.text.trim(),
              tipoVinculo: _selectedTipoVinculo,
              oficinaId: _selectedOffice?.id,
              cargoCodigo: _selectedCargo?.code,
              unidad: _unidadController.text.trim(),
              cargo: _cargoController.text.trim(),
              numeroItem: _numeroItemController.text.trim(),
              activo: _selectedActivo,
              fotoData: base64Encode(_photoBytes!),
            )
          : await dependencies.authApiService.login(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

      if (!mounted) {
        return;
      }

      widget.onAuthenticated(user);

      AppAlert.showSuccess(
        context,
        _isRegisterMode
            ? 'Registro completado. Ingresando al panel.'
            : 'Sesion iniciada.',
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

      AppAlert.showError(context, 'No fue posible completar la autenticacion.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSocialLoginMessage(String provider) {
    AppAlert.showWarning(
      context,
      'El ingreso con $provider todavia no esta disponible.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: _AuthBackdrop())),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 720
                    ? 28.0
                    : 18.0;
                final stageMinHeight = constraints.maxHeight -
                    20 -
                    viewInsets.bottom;
                final resolvedStageMinHeight = stageMinHeight > 0
                    ? stageMinHeight
                    : 0.0;
                final stageContent = switch (_stage) {
                  _AuthStage.welcome => _AuthWelcomeScreen(
                    onRegister: () => _setStage(_AuthStage.register),
                    onLogin: () => _setStage(_AuthStage.login),
                    onGoogleLogin: () => _showSocialLoginMessage('Google'),
                    onInnovaLogin: () => _showSocialLoginMessage('Innova'),
                  ),
                  _AuthStage.login || _AuthStage.register => _AuthFormCard(
                    formKey: _formKey,
                    isRegisterMode: _isRegisterMode,
                    isSubmitting: _isSubmitting,
                    acceptedTerms: _acceptedTerms,
                    showTermsError: _showTermsError,
                    nombreCompletoController: _nombreCompletoController,
                    primerApellidoController: _primerApellidoController,
                    segundoApellidoController: _segundoApellidoController,
                    tercerApellidoController: _tercerApellidoController,
                    ciController: _ciController,
                    unidadController: _unidadController,
                    cargoController: _cargoController,
                    numeroItemController: _numeroItemController,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    confirmPasswordController: _confirmPasswordController,
                    hidePassword: _hidePassword,
                    hideConfirmPassword: _hideConfirmPassword,
                    selectedTipoVinculo: _selectedTipoVinculo,
                    isLoadingOffices: _isLoadingOffices,
                    officeLoadError: _officeLoadError,
                    isLoadingCargos: _isLoadingCargos,
                    cargoLoadError: _cargoLoadError,
                    photoBytes: _photoBytes,
                    showPhotoError: _showPhotoError,
                    onBack: () => _setStage(_AuthStage.welcome),
                    onTogglePasswordVisibility: () => setState(() {
                      _hidePassword = !_hidePassword;
                    }),
                    onToggleConfirmPasswordVisibility: () => setState(() {
                      _hideConfirmPassword = !_hideConfirmPassword;
                    }),
                    onTipoVinculoChanged: (value) => setState(() {
                      _selectedTipoVinculo = value;
                      if (value != 'ITEM') {
                        _numeroItemController.clear();
                      }
                    }),
                    onAcceptedTermsChanged: (value) => setState(() {
                      _acceptedTerms = value;
                      _showTermsError = false;
                    }),
                    onPickOffice: _pickOffice,
                    onRetryLoadOffices: _loadOffices,
                    onPickCargo: _pickCargo,
                    onRetryLoadCargos: _loadCargos,
                    onPickPhoto: _pickPhoto,
                    onSubmit: _submit,
                    minHeight: resolvedStageMinHeight,
                  ),
                };

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: SingleChildScrollView(
                    key: ValueKey(_stage),
                    controller: _formScrollController,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      6,
                      horizontalPadding,
                      14 + viewInsets.bottom,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _stage == _AuthStage.register ? 620 : 390,
                          minHeight: _stage == _AuthStage.register
                              ? 0
                              : resolvedStageMinHeight,
                        ),
                        child: stageContent,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthWelcomeScreen extends StatelessWidget {
  const _AuthWelcomeScreen({
    required this.onRegister,
    required this.onLogin,
    required this.onGoogleLogin,
    required this.onInnovaLogin,
  });

  final VoidCallback onRegister;
  final VoidCallback onLogin;
  final VoidCallback onGoogleLogin;
  final VoidCallback onInnovaLogin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : constraints.minHeight;

        return SizedBox(
          height: availableHeight > 0 ? availableHeight : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _AuthBrandLogo(
                  height: constraints.maxWidth >= 420 ? 104 : 86,
                ),
              ),
              const SizedBox(height: 32),
              /*
              _AuthPrimaryButton(
                label: 'Registrarse',
                color: AppPalette.night,
                onTap: onRegister,
              ),
              const SizedBox(height: 12),
              */
              _AuthPrimaryButton(
                label: 'Ingresar',
                color: AppPalette.night,
                onTap: onLogin,
              ),
              const SizedBox(height: 18),
              const _AuthDividerLabel(label: 'Ingresar con:'),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SocialLoginButton.google(onTap: onGoogleLogin),
                  const SizedBox(width: 14),
                  _SocialLoginButton.innova(onTap: onInnovaLogin),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AuthFormCard extends StatelessWidget {
  const _AuthFormCard({
    required this.formKey,
    required this.isRegisterMode,
    required this.isSubmitting,
    required this.acceptedTerms,
    required this.showTermsError,
    required this.nombreCompletoController,
    required this.primerApellidoController,
    required this.segundoApellidoController,
    required this.tercerApellidoController,
    required this.ciController,
    required this.unidadController,
    required this.cargoController,
    required this.numeroItemController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.hidePassword,
    required this.hideConfirmPassword,
    required this.selectedTipoVinculo,
    required this.isLoadingOffices,
    required this.officeLoadError,
    required this.isLoadingCargos,
    required this.cargoLoadError,
    required this.photoBytes,
    required this.showPhotoError,
    required this.onBack,
    required this.onTogglePasswordVisibility,
    required this.onToggleConfirmPasswordVisibility,
    required this.onTipoVinculoChanged,
    required this.onAcceptedTermsChanged,
    required this.onPickOffice,
    required this.onRetryLoadOffices,
    required this.onPickCargo,
    required this.onRetryLoadCargos,
    required this.onPickPhoto,
    required this.onSubmit,
    required this.minHeight,
  });

  final GlobalKey<FormState> formKey;
  final bool isRegisterMode;
  final bool isSubmitting;
  final bool acceptedTerms;
  final bool showTermsError;
  final TextEditingController nombreCompletoController;
  final TextEditingController primerApellidoController;
  final TextEditingController segundoApellidoController;
  final TextEditingController tercerApellidoController;
  final TextEditingController ciController;
  final TextEditingController unidadController;
  final TextEditingController cargoController;
  final TextEditingController numeroItemController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool hidePassword;
  final bool hideConfirmPassword;
  final String selectedTipoVinculo;
  final bool isLoadingOffices;
  final String? officeLoadError;
  final bool isLoadingCargos;
  final String? cargoLoadError;
  final Uint8List? photoBytes;
  final bool showPhotoError;
  final VoidCallback onBack;
  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback onToggleConfirmPasswordVisibility;
  final ValueChanged<String> onTipoVinculoChanged;
  final ValueChanged<bool> onAcceptedTermsChanged;
  final Future<void> Function() onPickOffice;
  final VoidCallback onRetryLoadOffices;
  final Future<void> Function() onPickCargo;
  final VoidCallback onRetryLoadCargos;
  final VoidCallback onPickPhoto;
  final VoidCallback onSubmit;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Form(
        key: formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : constraints.minHeight;

            if (!isRegisterMode) {
              return SizedBox(
                height: availableHeight > 0 ? availableHeight : minHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuthBackButton(onTap: onBack),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(child: _buildLoginView(context)),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthBackButton(onTap: onBack),
                const SizedBox(height: 12),
                _buildRegisterView(context, constraints),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _AuthBrandLogo(height: 94)),
        const SizedBox(height: 26),
        _AuthField(
          controller: emailController,
          label: 'Correo',
          hint: 'Correo',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          validator: (value) {
            final email = value?.trim() ?? '';

            if (email.isEmpty || !email.contains('@')) {
              return 'Ingresa un correo valido.';
            }

            return null;
          },
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: passwordController,
          label: 'Contrasena',
          hint: 'Contrasena',
          obscureText: hidePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          suffixIcon: IconButton(
            onPressed: onTogglePasswordVisibility,
            icon: Icon(
              hidePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFF585364),
            ),
          ),
          validator: (value) {
            if ((value ?? '').trim().length < 6) {
              return 'La contrasena debe tener al menos 6 caracteres.';
            }

            return null;
          },
          onFieldSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        _AuthPrimaryButton(
          label: 'Ingresar',
          color: const Color(0xFFE95182),
          onTap: isSubmitting ? null : onSubmit,
          isLoading: isSubmitting,
        ),
      ],
    );
  }

  Widget _buildRegisterView(BuildContext context, BoxConstraints constraints) {
    final useColumnHeader = constraints.maxWidth < 360;
    final rightFields = Column(
      children: [
        _AuthField(
          controller: ciController,
          label: 'Nro. Documento *',
          hint: 'Nro. Documento *',
          textInputAction: TextInputAction.next,
          validator: _requiredValidator('Ingresa tu CI.'),
        ),
        const SizedBox(height: 12),
        _DropdownField<String>(
          label: 'Tipo de vinculacion *',
          value: selectedTipoVinculo,
          items: const [
            DropdownMenuItem(value: 'ITEM', child: Text('Item')),
            DropdownMenuItem(value: 'EVENTUAL', child: Text('Eventual')),
            DropdownMenuItem(value: 'CONSULTOR', child: Text('Consultor')),
          ],
          onChanged: (value) {
            if (value != null) {
              onTipoVinculoChanged(value);
            }
          },
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (useColumnHeader) ...[
          Center(
            child: _PhotoPickerField(
              photoBytes: photoBytes,
              showError: showPhotoError,
              onPickPhoto: onPickPhoto,
            ),
          ),
          const SizedBox(height: 14),
          rightFields,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PhotoPickerField(
                photoBytes: photoBytes,
                showError: showPhotoError,
                onPickPhoto: onPickPhoto,
              ),
              const SizedBox(width: 14),
              Expanded(child: rightFields),
            ],
          ),
        const SizedBox(height: 14),
        _AuthField(
          controller: nombreCompletoController,
          label: 'Nombres *',
          hint: 'Nombres *',
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          validator: _requiredValidator('Ingresa tu nombre completo.'),
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: primerApellidoController,
          label: 'Primer Apellido *',
          hint: 'Primer Apellido *',
          textInputAction: TextInputAction.next,
          validator: _requiredValidator('Ingresa tu primer apellido.'),
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: segundoApellidoController,
          label: 'Segundo Apellido *',
          hint: 'Segundo Apellido *',
          textInputAction: TextInputAction.next,
          validator: _requiredValidator('Ingresa tu segundo apellido.'),
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: tercerApellidoController,
          label: 'Tercer Apellido',
          hint: 'Tercer Apellido',
          textInputAction: TextInputAction.next,
          validator: (_) => null,
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: emailController,
          label: 'Correo Electronico *',
          hint: 'Correo Electronico *',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          validator: (value) {
            final email = value?.trim() ?? '';

            if (email.isEmpty || !email.contains('@')) {
              return 'Ingresa un correo valido.';
            }

            if (email.toLowerCase().contains('@admin')) {
              return 'Solo un administrador puede crear cuentas con @admin.';
            }

            return null;
          },
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: passwordController,
          label: 'Contrasena *',
          hint: 'Contrasena *',
          obscureText: hidePassword,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: IconButton(
            onPressed: onTogglePasswordVisibility,
            icon: Icon(
              hidePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: Colors.black87,
            ),
          ),
          validator: (value) {
            if ((value ?? '').trim().length < 6) {
              return 'La contrasena debe tener al menos 6 caracteres.';
            }

            return null;
          },
        ),
        const SizedBox(height: 12),
        _AuthField(
          controller: confirmPasswordController,
          label: 'Confirmar Contrasena *',
          hint: 'Confirmar Contrasena *',
          obscureText: hideConfirmPassword,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            onPressed: onToggleConfirmPasswordVisibility,
            icon: Icon(
              hideConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: Colors.black87,
            ),
          ),
          validator: (value) {
            if ((value ?? '').trim() != passwordController.text.trim()) {
              return 'Las contrasenas no coinciden.';
            }

            return null;
          },
        ),
        const SizedBox(height: 12),
        _SelectionField(
          controller: unidadController,
          label: 'Unidad / Oficina *',
          hint: isLoadingOffices
              ? 'Cargando unidades...'
              : 'Unidad / Oficina *',
          icon: Icons.apartment_rounded,
          isLoading: isLoadingOffices,
          onTap: onPickOffice,
          validator: _requiredValidator('Selecciona tu unidad.'),
        ),
        if (officeLoadError != null) ...[
          const SizedBox(height: 8),
          _InlineRetryMessage(
            message: officeLoadError!,
            onRetry: onRetryLoadOffices,
          ),
        ],
        const SizedBox(height: 12),
        _SelectionField(
          controller: cargoController,
          label: 'Cargo *',
          hint: isLoadingCargos ? 'Cargando cargos...' : 'Cargo *',
          icon: Icons.badge_outlined,
          isLoading: isLoadingCargos,
          onTap: onPickCargo,
          validator: _requiredValidator('Selecciona tu cargo.'),
        ),
        if (cargoLoadError != null) ...[
          const SizedBox(height: 8),
          _InlineRetryMessage(
            message: cargoLoadError!,
            onRetry: onRetryLoadCargos,
          ),
        ],
        if (selectedTipoVinculo == 'ITEM') ...[
          const SizedBox(height: 12),
          _AuthField(
            controller: numeroItemController,
            label: 'Nro. Item *',
            hint: 'Nro. Item *',
            textInputAction: TextInputAction.done,
            validator: _requiredValidator('Ingresa tu numero item.'),
          ),
        ],
        const SizedBox(height: 16),
        _AuthTermsCard(
          accepted: acceptedTerms,
          showError: showTermsError,
          onChanged: onAcceptedTermsChanged,
        ),
        const SizedBox(height: 16),
        _AuthPrimaryButton(
          label: 'Registrarme',
          color: AppPalette.night,
          onTap: isSubmitting ? null : onSubmit,
          isLoading: isSubmitting,
          icon: Icons.login_rounded,
        ),
        const SizedBox(height: 20),
      ],
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
    return SizedBox(
      width: 122,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              GestureDetector(
                onTap: onPickPhoto,
                child: Container(
                  width: 116,
                  height: 116,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF05E8A),
                    border: Border.all(
                      color: showError
                          ? const Color(0xFFD94841)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFF9218),
                    ),
                    child: ClipOval(
                      child: photoBytes == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 70,
                              color: Colors.black87,
                            )
                          : Image.memory(photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -8,
                child: _PhotoUpdateButton(onTap: onPickPhoto),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (showError)
            const Text(
              'Debes seleccionar una foto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFD94841), fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffixIcon,
    this.autofillHints,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF0EEF6),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        hintStyle: const TextStyle(color: Color(0xFF585364), fontSize: 14),
        labelStyle: const TextStyle(color: Color(0xFF585364), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppPalette.night, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD94841), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD94841), width: 1.2),
        ),
      ),
    );
  }
}

class _SelectionField extends StatelessWidget {
  const _SelectionField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validator,
    required this.onTap,
    this.isLoading = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?) validator;
  final Future<void> Function() onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasValue = controller.text.trim().isNotEmpty;

    return FormField<String>(
      validator: (_) => validator(controller.text),
      builder: (state) {
        final hasError = state.hasError;
        final borderColor = hasError
            ? const Color(0xFFD94841)
            : AppPalette.line;
        final labelColor = hasError
            ? const Color(0xFFD94841)
            : AppPalette.muted;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: label,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: isLoading
                      ? null
                      : () async {
                          await onTap();
                          state.didChange(controller.text);
                          if (state.hasError) {
                            state.validate();
                          }
                        },
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EEF6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: borderColor,
                        width: hasError ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            hasValue ? controller.text.trim() : hint,
                            style:
                                (hasValue
                                    ? textTheme.bodyLarge?.copyWith(
                                        color: const Color(0xFF2E2D36),
                                        fontWeight: FontWeight.w500,
                                      )
                                    : textTheme.bodyLarge?.copyWith(
                                        color: labelColor,
                                      )) ??
                                const TextStyle(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(icon, color: const Color(0xFF585364), size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 8),
                child: Text(
                  state.errorText!,
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFD94841),
                  ),
                ),
              ),
          ],
        );
      },
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
      key: ValueKey<Object?>(value),
      initialValue: value,
      items: items,
      onChanged: onChanged,
      icon: const Icon(Icons.expand_more_rounded, color: Color(0xFF585364)),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF0EEF6),
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelStyle: const TextStyle(color: Color(0xFF585364), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppPalette.night, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD94841), width: 1.2),
        ),
      ),
    );
  }
}

class _PhotoUpdateButton extends StatelessWidget {
  const _PhotoUpdateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF05E8A),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Actualizar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineRetryMessage extends StatelessWidget {
  const _InlineRetryMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFFD94841)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    );
  }
}

class _AuthPrimaryButton extends StatelessWidget {
  const _AuthPrimaryButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: onTap == null ? color.withValues(alpha: 0.55) : color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1E000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _AuthBackButton extends StatelessWidget {
  const _AuthBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.night,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        ),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
        label: const Text(
          'Atras',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _AuthBrandLogo extends StatelessWidget {
  const _AuthBrandLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/inlogplo.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}

class _AuthDividerLabel extends StatelessWidget {
  const _AuthDividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppPalette.line, thickness: 1.2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        const Expanded(child: Divider(color: AppPalette.line, thickness: 1.2)),
      ],
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton._({required this.child, required this.onTap});

  factory _SocialLoginButton.google({required VoidCallback onTap}) {
    return _SocialLoginButton._(
      onTap: onTap,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }

  factory _SocialLoginButton.innova({required VoidCallback onTap}) {
    return _SocialLoginButton._(
      onTap: onTap,
      child: const Icon(
        Icons.fingerprint_rounded,
        color: AppPalette.night,
        size: 28,
      ),
    );
  }

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x16000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _AuthTermsCard extends StatelessWidget {
  const _AuthTermsCard({
    required this.accepted,
    required this.showError,
    required this.onChanged,
  });

  final bool accepted;
  final bool showError;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFD4F0FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: showError ? const Color(0xFFD94841) : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Checkbox(
                  value: accepted,
                  onChanged: (value) => onChanged(value ?? false),
                  activeColor: AppPalette.night,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: Color(0xFF4F5170),
                      fontSize: 13,
                      height: 1.35,
                    ),
                    children: [
                      TextSpan(
                        text:
                            'Al aceptar a continuacion, confirmo que he leido y comprendido los ',
                      ),
                      TextSpan(
                        text: 'terminos y condiciones',
                        style: TextStyle(
                          color: AppPalette.night,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: ', asi como la '),
                      TextSpan(
                        text: 'politica de privacidad',
                        style: TextStyle(
                          color: AppPalette.night,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: ' de Innova Cochabamba.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          const Text(
            'Debes aceptar los terminos para continuar.',
            style: TextStyle(color: Color(0xFFD94841), fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: 190,
        width: double.infinity,
        child: CustomPaint(painter: _AuthWavePainter()),
      ),
    );
  }
}

class _AuthWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x14000000);

    for (var i = 0; i < 18; i++) {
      final y = size.height * 0.56 + (i * 8);
      final amplitude = 12.0 + (i * 1.1);
      final path = Path()
        ..moveTo(-30, y)
        ..cubicTo(
          size.width * 0.18,
          y - amplitude,
          size.width * 0.34,
          y + amplitude,
          size.width * 0.5,
          y,
        )
        ..cubicTo(
          size.width * 0.66,
          y - amplitude,
          size.width * 0.82,
          y + amplitude,
          size.width + 30,
          y,
        );
      paint.color = const Color(
        0x14000000,
      ).withValues(alpha: 0.06 + (i * 0.004));
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  final ScrollController _resultsScrollController = ScrollController();

  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filteredOffices = widget.offices
        .where((office) {
          if (normalizedQuery.isEmpty) {
            return true;
          }

          return office.name.toLowerCase().contains(normalizedQuery) ||
              office.code.toLowerCase().contains(normalizedQuery) ||
              office.level.toString().contains(normalizedQuery);
        })
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 20, 12, 12 + bottomInset),
        child: Material(
          color: AppPalette.surface,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selecciona la unidad',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Estos datos llegan directamente desde la tabla de oficinas.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Buscar unidad',
                      hintText: 'Escribe nombre, codigo o nivel',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    filteredOffices.length == 1
                        ? '1 resultado'
                        : '${filteredOffices.length} resultados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppPalette.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppPalette.line),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: filteredOffices.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    'No hay coincidencias para tu busqueda.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : Scrollbar(
                                controller: _resultsScrollController,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: _resultsScrollController,
                                  physics: const ClampingScrollPhysics(),
                                  padding: const EdgeInsets.all(12),
                                  itemCount: filteredOffices.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final office = filteredOffices[index];
                                    final isSelected =
                                        widget.selectedOffice?.id == office.id;

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () =>
                                          Navigator.of(context).pop(office),
                                      child: Ink(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppPalette.orangeSoft
                                              : AppPalette.surfaceSoft,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppPalette.orange
                                                : AppPalette.line,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
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
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  left: 12,
                                                ),
                                                child: Icon(
                                                  Icons.check_circle_rounded,
                                                  color: AppPalette.orange,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
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
  final ScrollController _resultsScrollController = ScrollController();

  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filteredCargos = widget.cargos
        .where((cargo) {
          if (normalizedQuery.isEmpty) {
            return true;
          }

          return cargo.name.toLowerCase().contains(normalizedQuery) ||
              cargo.code.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 20, 12, 12 + bottomInset),
        child: Material(
          color: AppPalette.surface,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selecciona el cargo',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Estos datos llegan directamente desde la tabla de cargos.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Buscar cargo',
                      hintText: 'Escribe cargo o codigo',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    filteredCargos.length == 1
                        ? '1 resultado'
                        : '${filteredCargos.length} resultados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppPalette.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppPalette.line),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: filteredCargos.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    'No hay coincidencias para tu busqueda.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : Scrollbar(
                                controller: _resultsScrollController,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: _resultsScrollController,
                                  physics: const ClampingScrollPhysics(),
                                  padding: const EdgeInsets.all(12),
                                  itemCount: filteredCargos.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final cargo = filteredCargos[index];
                                    final isSelected =
                                        widget.selectedCargo?.code ==
                                        cargo.code;

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () =>
                                          Navigator.of(context).pop(cargo),
                                      child: Ink(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppPalette.orangeSoft
                                              : AppPalette.surfaceSoft,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppPalette.orange
                                                : AppPalette.line,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
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
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  left: 12,
                                                ),
                                                child: Icon(
                                                  Icons.check_circle_rounded,
                                                  color: AppPalette.orange,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
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

String? Function(String?) _requiredValidator(String message) {
  return (value) {
    if ((value ?? '').trim().isEmpty) {
      return message;
    }

    return null;
  };
}
