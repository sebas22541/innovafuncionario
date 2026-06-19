import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../infrastructure/services/devices_api_service.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<ManagedDevice> _devices = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final devices = await dependencies.devicesApiService.fetchDevices();

      if (!mounted) {
        return;
      }

      setState(() {
        _devices = devices;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _devices = const [];
        _errorMessage = 'No fue posible cargar los celulares.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestLogout(ManagedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesion del celular'),
        content: Text(
          'Se cerrara la sesion de ${device.userName} cuando el celular vuelva a conectarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar sesion'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await dependencies.devicesApiService.requestLogout(device.deviceId);
      if (!mounted) {
        return;
      }

      AppAlert.showSuccess(context, 'Orden de cierre enviada.');
      await _load();
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible enviar la orden.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _devices.where((device) => device.isOnline).length;
    final lowBatteryCount = _devices.where((device) {
      final batteryLevel = device.batteryLevel;
      return batteryLevel != null && batteryLevel <= 20;
    }).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Celulares',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  _SummaryChip(
                    label: 'Registrados',
                    value: '${_devices.length}',
                  ),
                  _SummaryChip(label: 'En linea', value: '$onlineCount'),
                  _SummaryChip(
                    label: 'Bateria baja',
                    value: '$lowBatteryCount',
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_isLoading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_errorMessage != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(_errorMessage!),
              ),
            )
          else if (_devices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Todavia no hay celulares registrados.'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;

                if (isWide) {
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final device in _devices)
                        SizedBox(
                          width: (constraints.maxWidth - 14) / 2,
                          child: _DeviceCard(
                            device: device,
                            onLogout: () => _requestLogout(device),
                          ),
                        ),
                    ],
                  );
                }

                return Column(
                  children: [
                    for (final device in _devices) ...[
                      _DeviceCard(
                        device: device,
                        onLogout: () => _requestLogout(device),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onLogout});

  final ManagedDevice device;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final batteryLevel = device.batteryLevel;
    final brightness = device.brightness;
    final statusColor = device.isOnline
        ? Colors.green.shade700
        : Colors.red.shade700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_android_rounded, color: statusColor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.userName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.userCi.isEmpty
                            ? device.deviceId
                            : 'CI ${device.userCi}',
                        style: const TextStyle(color: AppPalette.muted),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: device.isOnline ? 'En linea' : 'Sin conexion',
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DeviceInfoRow(label: 'Equipo', value: _deviceName(device)),
            _DeviceInfoRow(
              label: 'Bateria',
              value: batteryLevel == null
                  ? 'Sin dato'
                  : '$batteryLevel%${device.isCharging == true ? ' cargando' : ''}',
            ),
            _DeviceInfoRow(
              label: 'Brillo',
              value: brightness == null ? 'Sin dato' : '$brightness%',
            ),
            _DeviceInfoRow(
              label: 'Kiosk',
              value: device.kioskEnabled ? 'Activo' : 'No activo',
            ),
            _DeviceInfoRow(
              label: 'Ultimo contacto',
              value: _formatDateTime(device.lastSeenAt),
            ),
            if (device.logoutRequestedAt != null)
              _DeviceInfoRow(
                label: 'Cierre solicitado',
                value: _formatDateTime(device.logoutRequestedAt),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesion'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deviceName(ManagedDevice device) {
    final parts = [
      device.manufacturer,
      device.model,
      if (device.androidSdk != null) 'SDK ${device.androidSdk}',
    ].where((part) => part.toString().trim().isNotEmpty).join(' ');

    return parts.isEmpty ? device.platform : parts;
  }
}

class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label, style: const TextStyle(color: AppPalette.muted)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.phone_android_rounded, size: 18),
      label: Text('$label: $value'),
    );
  }
}

String _formatDateTime(DateTime? date) {
  if (date == null) {
    return 'Sin dato';
  }

  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
