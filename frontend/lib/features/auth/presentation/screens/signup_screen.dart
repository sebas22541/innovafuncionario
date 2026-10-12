import 'package:flutter/material.dart';

import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/privacy_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _names = TextEditingController();
  final _surname = TextEditingController();
  final _ci = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _accepted = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _names,
      _surname,
      _ci,
      _password,
      _confirmation,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (!_accepted) {
      setState(
        () => _error = 'Lee y acepta la política de privacidad para continuar.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await dependencies.authApiService.signup(
        names: _names.text.trim(),
        surname: _surname.text.trim(),
        ci: _ci.text.trim(),
        password: _password.text,
      );
      if (mounted) Navigator.of(context).pop<AppUser>(user);
    } on BackendApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo crear la cuenta. Intenta nuevamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Regístrate con tus datos. Tu CI será tu usuario de acceso. '
                    'La administración verificará tu información laboral.',
                  ),
                  const SizedBox(height: 20),
                  _field(
                    _names,
                    'Nombres',
                    min: 2,
                    max: 150,
                    autofill: const [AutofillHints.givenName],
                  ),
                  _field(
                    _surname,
                    'Primer apellido',
                    min: 2,
                    max: 80,
                    autofill: const [AutofillHints.familyName],
                  ),
                  _field(
                    _ci,
                    'CI',
                    min: 3,
                    max: 30,
                    autofill: const [AutofillHints.username],
                  ),
                  _field(
                    _password,
                    'Contraseña (mínimo 8 caracteres)',
                    min: 8,
                    max: 200,
                    secret: true,
                    autofill: const [AutofillHints.newPassword],
                  ),
                  _field(
                    _confirmation,
                    'Confirmar contraseña',
                    min: 8,
                    max: 200,
                    secret: true,
                  ),
                  TextButton(
                    onPressed: () => PrivacyScreen.open(context),
                    child: const Text('Leer privacidad y condiciones de uso'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _accepted,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _accepted = value ?? false),
                    title: const Text(
                      'He leído y acepto la política de privacidad y las condiciones de uso.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? 'Creando cuenta…' : 'Crear cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    required int min,
    required int max,
    bool secret = false,
    List<String>? autofill,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      obscureText: secret && _hidePassword,
      autocorrect: !secret,
      enableSuggestions: !secret,
      autofillHints: autofill,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: secret
            ? IconButton(
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                tooltip: _hidePassword
                    ? 'Mostrar contraseña'
                    : 'Ocultar contraseña',
                icon: Icon(
                  _hidePassword ? Icons.visibility : Icons.visibility_off,
                ),
              )
            : null,
      ),
      validator: (value) {
        final text = secret ? (value ?? '') : (value ?? '').trim();
        if (secret && text != text.trim()) {
          return 'La contraseña no puede empezar ni terminar con espacios.';
        }
        if (text.length < min || text.length > max) {
          return 'Ingresa entre $min y $max caracteres.';
        }
        if (controller == _confirmation && text != _password.text) {
          return 'Las contraseñas no coinciden.';
        }
        return null;
      },
    ),
  );
}
