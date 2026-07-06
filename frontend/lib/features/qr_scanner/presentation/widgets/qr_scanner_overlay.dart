import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';

Rect buildQrScanWindow(Size size) {
  final scanSize = math
      .min(size.width * 0.62, size.height * 0.62)
      .clamp(220.0, 340.0);

  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2 - 8),
    width: scanSize,
    height: scanSize,
  );
}

class QrScannerOverlay extends StatefulWidget {
  const QrScannerOverlay({super.key, required this.isActive});

  final bool isActive;

  @override
  State<QrScannerOverlay> createState() => _QrScannerOverlayState();
}

class _QrScannerOverlayState extends State<QrScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanRect = buildQrScanWindow(
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ScannerMaskPainter(
                  scanRect: scanRect,
                  isActive: widget.isActive,
                ),
              ),
            ),
            if (widget.isActive)
              Positioned(
                left: scanRect.left + 18,
                top: scanRect.top,
                child: SizedBox(
                  width: scanRect.width - 36,
                  height: scanRect.height,
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      final top =
                          (scanRect.height - 4) * _animationController.value;

                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: top,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppPalette.orange,
                                    Colors.transparent,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x667D67B1),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScannerMaskPainter extends CustomPainter {
  const _ScannerMaskPainter({required this.scanRect, required this.isActive});

  final Rect scanRect;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(28)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(backgroundPath, Paint()..color = const Color(0x8A23183B));

    final framePaint = Paint()
      ..color = Colors.white.withValues(alpha: isActive ? 0.92 : 0.68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(28)),
      framePaint,
    );

    const cornerLength = 26.0;
    const cornerWidth = 4.0;
    final cornerPaint = Paint()
      ..color = AppPalette.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = cornerWidth
      ..strokeCap = StrokeCap.round;

    final corners = [
      (
        Offset(scanRect.left, scanRect.top + cornerLength),
        Offset(scanRect.left, scanRect.top),
        Offset(scanRect.left + cornerLength, scanRect.top),
      ),
      (
        Offset(scanRect.right - cornerLength, scanRect.top),
        Offset(scanRect.right, scanRect.top),
        Offset(scanRect.right, scanRect.top + cornerLength),
      ),
      (
        Offset(scanRect.left, scanRect.bottom - cornerLength),
        Offset(scanRect.left, scanRect.bottom),
        Offset(scanRect.left + cornerLength, scanRect.bottom),
      ),
      (
        Offset(scanRect.right - cornerLength, scanRect.bottom),
        Offset(scanRect.right, scanRect.bottom),
        Offset(scanRect.right, scanRect.bottom - cornerLength),
      ),
    ];

    for (final corner in corners) {
      canvas.drawLine(corner.$1, corner.$2, cornerPaint);
      canvas.drawLine(corner.$2, corner.$3, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerMaskPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect || oldDelegate.isActive != isActive;
  }
}
