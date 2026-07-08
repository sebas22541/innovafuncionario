import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../injection_container.dart';
import '../../../../shared/infrastructure/backend_api_client.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../infrastructure/services/ratings_api_service.dart';

class RatingsScreen extends StatefulWidget {
  const RatingsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  List<AppUser> _users = const [];
  List<ActiveRatingQr> _activeQrs = const [];
  List<RatingSummary> _report = const [];
  RatingQr? _ratingQr;
  bool _isLoadingUsers = true;
  bool _isLoadingActiveQrs = true;
  bool _isGenerating = false;
  bool _isLoadingReport = true;
  String _query = '';
  String _selectedDate = _todayText();
  Timer? _searchDebounce;

  List<AppUser> get _filteredUsers {
    final query = _normalize(_query);

    if (query.length < 2) {
      return const [];
    }

    final users = _users.where((user) => user.activo).toList(growable: false);

    return users
        .where(
          (user) => _normalize(
            '${user.fullName} ${user.ci} ${user.cargoEfectivo} ${user.officeName} ${user.unidad}',
          ).contains(query),
        )
        .take(30)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _dateController.text = _selectedDate;
    _loadUsers();
    _loadActiveQrs();
    _loadReport();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);

    try {
      final users = await dependencies.authApiService.fetchUsers(
        requesterEmail: widget.currentUser.email,
      );
      if (!mounted) {
        return;
      }
      setState(() => _users = users);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar funcionarios.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  Future<void> _loadActiveQrs() async {
    setState(() => _isLoadingActiveQrs = true);

    try {
      final qrs = await dependencies.ratingsApiService.fetchActiveQrs();
      if (!mounted) {
        return;
      }
      setState(() => _activeQrs = qrs);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar QR activos.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingActiveQrs = false);
      }
    }
  }

  Future<void> _loadReport() async {
    setState(() => _isLoadingReport = true);

    try {
      final report = await dependencies.ratingsApiService.fetchReport(
        fecha: _selectedDate,
      );
      if (!mounted) {
        return;
      }
      setState(() => _report = report.funcionarios);
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible cargar el reporte.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingReport = false);
      }
    }
  }

  Future<void> _generateQr(AppUser user) async {
    final userId = user.id;

    if (userId == null || _isGenerating) {
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final qr = await dependencies.ratingsApiService.generateQr(
        funcionarioId: userId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _ratingQr = qr);
      await _loadActiveQrs();
    } on BackendApiException catch (error) {
      if (mounted) {
        AppAlert.showError(context, error.message);
      }
    } catch (_) {
      if (mounted) {
        AppAlert.showError(context, 'No fue posible generar el QR.');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _showActiveQr(ActiveRatingQr qr) {
    setState(() {
      _ratingQr = RatingQr(
        funcionario: RatingFuncionario(
          id: qr.funcionarioId,
          nombreCompleto: qr.nombreCompleto,
          ci: qr.ci,
          cargo: qr.cargo,
          oficina: qr.oficina,
        ),
        token: qr.token,
        url: qr.url,
      );
    });
  }

  Future<void> _copyQrUrl() async {
    final url = _ratingQr?.url;

    if (url == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));

    if (mounted) {
      AppAlert.showSuccess(context, 'Enlace copiado.');
    }
  }

  Future<void> _pickDate() async {
    final initialDate = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('es', 'BO'),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = _formatDate(selected);
      _dateController.text = _selectedDate;
    });
    _loadReport();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() => _query = value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final qr = _ratingQr;

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
                  Text(
                    'Generar QR de calificacion',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      labelText: 'Buscar funcionario',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_isLoadingUsers && _query.trim().length >= 2)
                    const Center(child: CircularProgressIndicator())
                  else if (_query.trim().length >= 2 &&
                      _filteredUsers.isNotEmpty)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _filteredUsers
                          .map(
                            (user) => ActionChip(
                              avatar: const Icon(Icons.person_outline_rounded),
                              label: Text(user.fullName),
                              onPressed: _isGenerating
                                  ? null
                                  : () => _generateQr(user),
                            ),
                          )
                          .toList(growable: false),
                    )
                  else if (_query.trim().length >= 2)
                    const _SearchHint(
                      icon: Icons.search_off_rounded,
                      text: 'No se encontraron funcionarios.',
                    )
                  else
                    const _SearchHint(
                      icon: Icons.manage_search_rounded,
                      text: 'Escribe al menos 2 letras para buscar.',
                    ),
                  if (qr != null) ...[
                    const SizedBox(height: 22),
                    Center(
                      child: Column(
                        children: [
                          QrImageView(
                            data: qr.url,
                            version: QrVersions.auto,
                            size: 260,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            qr.funcionario.nombreCompleto,
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          SelectableText(qr.url, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _copyQrUrl,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copiar enlace'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'QR activos para calificacion',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: _loadActiveQrs,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingActiveQrs)
                    const Center(child: CircularProgressIndicator())
                  else if (_activeQrs.isEmpty)
                    const _SearchHint(
                      icon: Icons.qr_code_2_rounded,
                      text: 'Todavia no hay QR activos de calificacion.',
                    )
                  else
                    Column(
                      children: _activeQrs
                          .map(
                            (qr) => _ActiveQrTile(
                              qr: qr,
                              onTap: () => _showActiveQr(qr),
                            ),
                          )
                          .toList(growable: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Reporte diario',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: TextField(
                          controller: _dateController,
                          readOnly: true,
                          onTap: _pickDate,
                          decoration: const InputDecoration(
                            labelText: 'Fecha',
                            prefixIcon: Icon(Icons.today_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        onPressed: _loadReport,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingReport)
                    const Center(child: CircularProgressIndicator())
                  else if (_report.isEmpty)
                    const _EmptyReport()
                  else
                    Column(
                      children: _report
                          .map((row) => _RatingSummaryTile(summary: row))
                          .toList(growable: false),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingSummaryTile extends StatelessWidget {
  const _RatingSummaryTile({required this.summary});

  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final comments = summary.comentarios
        .where((comment) => comment.comentario.trim().isNotEmpty)
        .toList(growable: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.nombreCompleto,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        summary.cargo,
                        summary.oficina,
                      ].where((value) => value.trim().isNotEmpty).join(' | '),
                    ),
                  ],
                ),
              ),
              _CountPill(
                icon: Icons.sentiment_satisfied_alt_rounded,
                value: summary.feliz,
              ),
              const SizedBox(width: 8),
              _CountPill(
                icon: Icons.sentiment_neutral_rounded,
                value: summary.neutral,
              ),
              const SizedBox(width: 8),
              _CountPill(
                icon: Icons.sentiment_very_dissatisfied_rounded,
                value: summary.enojada,
              ),
            ],
          ),
          if (comments.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final comment in comments.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('- ${comment.comentario}'),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActiveQrTile extends StatelessWidget {
  const _ActiveQrTile({required this.qr, required this.onTap});

  final ActiveRatingQr qr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.qr_code_2_rounded),
        title: Text(
          qr.nombreCompleto,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            qr.cargo,
            qr.oficina,
          ].where((value) => value.trim().isNotEmpty).join(' | '),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: AppPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppPalette.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 4),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text('No hay calificaciones registradas en la fecha.'),
      ),
    );
  }
}

String _normalize(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _todayText() => _formatDate(DateTime.now());

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
