import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

enum AppAlertType { success, error, info, warning }

class AppAlert {
  AppAlert._();

  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void showSuccess(
    BuildContext context,
    String message, {
    String title = 'Correcto',
  }) {
    _show(context, type: AppAlertType.success, title: title, message: message);
  }

  static void showError(
    BuildContext context,
    String message, {
    String title = 'Error',
  }) {
    _show(context, type: AppAlertType.error, title: title, message: message);
  }

  static void showInfo(
    BuildContext context,
    String message, {
    String title = 'Aviso',
  }) {
    _show(context, type: AppAlertType.info, title: title, message: message);
  }

  static void showWarning(
    BuildContext context,
    String message, {
    String title = 'Atencion',
  }) {
    _show(context, type: AppAlertType.warning, title: title, message: message);
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Aceptar',
    String cancelLabel = 'Cancelar',
    AppAlertType type = AppAlertType.warning,
  }) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Confirmacion',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 28,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AlertBadge(type: type, size: 58),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text(cancelLabel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: _accentColor(type),
                              ),
                              child: Text(confirmLabel),
                            ),
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
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );

    return result == true;
  }

  static void _show(
    BuildContext context, {
    required AppAlertType type,
    required String title,
    required String message,
  }) {
    _dismissTimer?.cancel();
    _activeEntry?.remove();
    _activeEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (context) => _AlertToast(
        type: type,
        title: title,
        message: message,
      ),
    );

    overlay.insert(entry);
    _activeEntry = entry;
    _dismissTimer = Timer(const Duration(milliseconds: 2200), _dismiss);
  }

  static void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }

  static Color _accentColor(AppAlertType type) {
    switch (type) {
      case AppAlertType.success:
        return const Color(0xFF16A34A);
      case AppAlertType.error:
        return const Color(0xFFD94841);
      case AppAlertType.info:
        return AppPalette.orange;
      case AppAlertType.warning:
        return const Color(0xFFF59E0B);
    }
  }

  static Color _softColor(AppAlertType type) {
    switch (type) {
      case AppAlertType.success:
        return const Color(0xFFEAF8EF);
      case AppAlertType.error:
        return Colors.white;
      case AppAlertType.info:
        return Colors.white;
      case AppAlertType.warning:
        return const Color(0xFFFFF5DF);
    }
  }

  static IconData _iconForType(AppAlertType type) {
    switch (type) {
      case AppAlertType.success:
        return Icons.check_rounded;
      case AppAlertType.error:
        return Icons.close_rounded;
      case AppAlertType.info:
        return Icons.info_outline_rounded;
      case AppAlertType.warning:
        return Icons.warning_amber_rounded;
    }
  }
}

class _AlertToast extends StatefulWidget {
  const _AlertToast({
    required this.type,
    required this.title,
    required this.message,
  });

  final AppAlertType type;
  final String title;
  final String message;

  @override
  State<_AlertToast> createState() => _AlertToastState();
}

class _AlertToastState extends State<_AlertToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();
  late final Animation<Offset> _offsetAnimation =
      Tween<Offset>(
        begin: const Offset(0, -0.16),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = AppAlert._accentColor(widget.type);
    final softColor = AppAlert._softColor(widget.type);

    return Positioned(
      top: 24,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SlideTransition(
                position: _offsetAnimation,
                child: FadeTransition(
                  opacity: _controller,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: softColor),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x16000000),
                          blurRadius: 24,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AlertBadge(type: widget.type, size: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.message,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          AppAlert._iconForType(widget.type),
                          color: accentColor,
                        ),
                      ],
                    ),
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

class _AlertBadge extends StatelessWidget {
  const _AlertBadge({required this.type, required this.size});

  final AppAlertType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppAlert._accentColor(type);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppAlert._softColor(type),
        borderRadius: BorderRadius.circular(size * 0.35),
      ),
      child: Icon(
        AppAlert._iconForType(type),
        color: accentColor,
        size: size * 0.55,
      ),
    );
  }
}
