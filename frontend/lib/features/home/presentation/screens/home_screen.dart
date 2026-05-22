import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _eventsCount = 0;
  int _registeredUsersCount = 0;
  int _officesCount = 0;
  bool _hasLoadedSummary = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summary = await dependencies.authApiService.fetchDashboardSummary();

      if (!mounted) {
        return;
      }

      setState(() {
        _eventsCount = summary.events;
        _registeredUsersCount = summary.registeredUsers;
        _officesCount = summary.offices;
        _hasLoadedSummary = true;
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
        _errorMessage = 'No fue posible cargar el resumen de eventos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && !_hasLoadedSummary && _eventsCount == 0) {
      return _HomeErrorState(message: _errorMessage!, onRetry: _loadMetrics);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final columnGap = isWide ? 14.0 : 0.0;
        final statWidth = isWide
            ? math.max((constraints.maxWidth - 28) / 3, 180).toDouble()
            : constraints.maxWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resumen de eventos', style: textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: columnGap,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: statWidth,
                    child: _SummaryCard(
                      title: 'Eventos guardados',
                      value: '$_eventsCount',
                      detail: 'Persistidos en la base de datos',
                      icon: Icons.calendar_month_rounded,
                    ),
                  ),
                  SizedBox(
                    width: statWidth,
                    child: _SummaryCard(
                      title: 'Usuarios registrados',
                      value: '$_registeredUsersCount',
                      detail: 'Creados en la plataforma',
                      icon: Icons.people_alt_outlined,
                    ),
                  ),
                  SizedBox(
                    width: statWidth,
                    child: _SummaryCard(
                      title: 'Oficinas',
                      value: '$_officesCount',
                      detail: 'Disponibles para asignar',
                      icon: Icons.apartment_rounded,
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFD94841),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppPalette.orangeSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppPalette.orange),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontSize: 32),
            ),
            const SizedBox(height: 6),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HomeErrorState extends StatelessWidget {
  const _HomeErrorState({required this.message, required this.onRetry});

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
                  'No fue posible cargar inicio',
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
