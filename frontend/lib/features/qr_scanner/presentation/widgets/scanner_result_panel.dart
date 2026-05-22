import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../domain/entities/qr_scan_result.dart';

class ScannerResultPanel extends StatelessWidget {
  const ScannerResultPanel({
    super.key,
    required this.lastScan,
    required this.onRestart,
  });

  final QrScanResult? lastScan;
  final VoidCallback onRestart;

  String _formatDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Lectura actual', style: textTheme.titleLarge),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: lastScan == null
                        ? AppPalette.blueSoft.withValues(alpha: 0.35)
                        : AppPalette.orangeSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    lastScan == null ? 'En espera' : 'Detectado',
                    style: TextStyle(
                      color: lastScan == null
                          ? AppPalette.night
                          : AppPalette.orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lastScan == null
                  ? 'La camara esta buscando un codigo QR.'
                  : 'El ultimo QR se abre en una pantalla aparte con sus datos.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.surfaceSoft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppPalette.line),
              ),
              child: lastScan == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Esperando QR', style: textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Enfoca el codigo dentro del marco para capturarlo.',
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Formato: ${lastScan!.format}',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tipo: ${lastScan!.payloadType}',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Contenido detectado',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          lastScan!.value,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Detectado: ${_formatDate(lastScan!.scannedAt)}',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRestart,
                child: Text(
                  lastScan == null ? 'Reiniciar camara' : 'Volver a escanear',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
