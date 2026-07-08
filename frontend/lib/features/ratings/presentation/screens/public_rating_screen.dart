import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../infrastructure/services/ratings_api_service.dart';

class PublicRatingScreen extends StatefulWidget {
  const PublicRatingScreen({super.key, required this.token});

  final String token;

  @override
  State<PublicRatingScreen> createState() => _PublicRatingScreenState();
}

class _PublicRatingScreenState extends State<PublicRatingScreen> {
  final TextEditingController _commentController = TextEditingController();
  RatingFuncionario? _funcionario;
  String? _selectedRating;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFuncionario();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadFuncionario() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final funcionario = await dependencies.ratingsApiService
          .fetchPublicFuncionario(widget.token);
      if (!mounted) {
        return;
      }
      setState(() {
        _funcionario = funcionario;
      });
    } on BackendApiException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'No fue posible cargar el QR.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    final rating = _selectedRating;

    if (rating == null || _isSubmitting) {
      AppAlert.showWarning(context, 'Selecciona una calificacion.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final deviceId = await _readOrCreateRatingDeviceId();
      await dependencies.ratingsApiService.submitPublicRating(
        token: widget.token,
        calificacion: rating,
        comentario: _commentController.text.trim(),
        deviceId: deviceId,
        deviceLabel: _deviceLabel(),
      );

      if (!mounted) {
        return;
      }

      setState(() => _submitted = true);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible enviar la calificacion.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final funcionario = _funcionario;

    return Scaffold(
      backgroundColor: AppPalette.cream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                      ? _RatingError(
                          message: _errorMessage!,
                          onRetry: _loadFuncionario,
                        )
                      : _submitted
                      ? const _SubmittedState()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Califica la atencion',
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              funcionario?.nombreCompleto ?? '',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            if ((funcionario?.cargo ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                funcionario!.cargo,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _RatingButton(
                                    label: 'Feliz',
                                    icon: Icons.sentiment_satisfied_alt_rounded,
                                    color: const Color(0xFF2E7D32),
                                    selected: _selectedRating == 'feliz',
                                    onTap: () => setState(
                                      () => _selectedRating = 'feliz',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _RatingButton(
                                    label: 'Neutral',
                                    icon: Icons.sentiment_neutral_rounded,
                                    color: const Color(0xFFF9A825),
                                    selected: _selectedRating == 'neutral',
                                    onTap: () => setState(
                                      () => _selectedRating = 'neutral',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _RatingButton(
                                    label: 'Enojada',
                                    icon: Icons
                                        .sentiment_very_dissatisfied_rounded,
                                    color: const Color(0xFFC62828),
                                    selected: _selectedRating == 'enojada',
                                    onTap: () => setState(
                                      () => _selectedRating = 'enojada',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _commentController,
                              minLines: 3,
                              maxLines: 5,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                labelText: 'Comentario opcional',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _isSubmitting ? null : _submit,
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: const Text('Enviar calificacion'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        height: 100,
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : AppPalette.surfaceSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : AppPalette.line,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SubmittedState extends StatelessWidget {
  const _SubmittedState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 64),
          SizedBox(height: 12),
          Text(
            'Gracias, tu calificacion fue registrada.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _RatingError extends StatelessWidget {
  const _RatingError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFC62828),
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}

Future<String> _readOrCreateRatingDeviceId() async {
  final preferences = await SharedPreferences.getInstance();
  final existing = preferences.getString('rating_device_id');

  if (existing != null && existing.length >= 8) {
    return existing;
  }

  final random = Random.secure();
  final value =
      '${DateTime.now().millisecondsSinceEpoch}-${List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join()}';
  await preferences.setString('rating_device_id', value);
  return value;
}

String _deviceLabel() {
  if (kIsWeb) {
    return 'Web';
  }

  return defaultTargetPlatform.name;
}
