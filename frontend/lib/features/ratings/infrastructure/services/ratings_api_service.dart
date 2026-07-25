import '../../../../shared/infrastructure/backend_api_client.dart';

class RatingsApiService {
  RatingsApiService(this._apiClient);

  final BackendApiClient _apiClient;

  Future<RatingQr> generateQr({required int funcionarioId}) async {
    final payload = await _apiClient.postJson('/api/calificaciones/qr', {
      'funcionarioId': funcionarioId,
    });
    return RatingQr.fromJson(_readMap(payload['data'], 'data'));
  }

  Future<List<RatingQr>> generateOfficeQrs({required int oficinaId}) async {
    final payload = await _apiClient.postJson(
      '/api/calificaciones/qr/oficina',
      {'oficinaId': oficinaId},
    );
    final data = _readMap(payload['data'], 'data');
    final rows = data['qrs'];

    if (rows is! List) {
      throw StateError('Los QR generados no tienen un formato valido.');
    }

    return rows
        .map((item) => RatingQr.fromJson(_readMap(item, 'qr')))
        .toList(growable: false);
  }

  Future<void> deleteQr({required int funcionarioId}) async {
    await _apiClient.deleteJson('/api/calificaciones/qr/$funcionarioId');
  }

  Future<RatingReport> fetchReport({
    String? fechaInicio,
    String? fechaFin,
    String? cargoCodigo,
    int? oficinaId,
    String? query,
  }) async {
    final queryParameters = <String, String>{
      if (fechaInicio != null && fechaInicio.trim().isNotEmpty)
        'fechaInicio': fechaInicio,
      if (fechaFin != null && fechaFin.trim().isNotEmpty) 'fechaFin': fechaFin,
      if (cargoCodigo != null && cargoCodigo.trim().isNotEmpty)
        'cargoCodigo': cargoCodigo,
      if (oficinaId != null) 'oficinaId': '$oficinaId',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };
    final payload = await _apiClient.getJson(
      '/api/calificaciones?${Uri(queryParameters: queryParameters).query}',
    );
    return RatingReport.fromJson(_readMap(payload['data'], 'data'));
  }

  Future<List<ActiveRatingQr>> fetchActiveQrs() async {
    final payload = await _apiClient.getJson('/api/calificaciones/qrs');
    final data = _readMap(payload['data'], 'data');
    final rows = data['qrs'];

    if (rows is! List) {
      throw StateError('Los QR activos no tienen un formato valido.');
    }

    return rows
        .map((item) => ActiveRatingQr.fromJson(_readMap(item, 'qr')))
        .toList(growable: false);
  }

  Future<RatingFuncionario> fetchPublicFuncionario(String token) async {
    final payload = await _apiClient.getJson(
      '/api/calificaciones/publica/${Uri.encodeComponent(token)}',
    );
    final data = _readMap(payload['data'], 'data');
    return RatingFuncionario.fromJson(
      _readMap(data['funcionario'], 'funcionario'),
    );
  }

  Future<void> submitPublicRating({
    required String token,
    required String calificacion,
    required String deviceId,
    required String deviceLabel,
    String comentario = '',
    String calificadorNombre = '',
    String calificadorCelular = '',
  }) async {
    await _apiClient
        .postJson('/api/calificaciones/publica/${Uri.encodeComponent(token)}', {
          'calificacion': calificacion,
          'comentario': comentario,
          'calificadorNombre': calificadorNombre,
          'calificadorCelular': calificadorCelular,
          'deviceId': deviceId,
          'deviceLabel': deviceLabel,
        });
  }
}

class ActiveRatingQr {
  const ActiveRatingQr({
    required this.funcionarioId,
    required this.nombreCompleto,
    required this.ci,
    required this.cargo,
    required this.oficina,
    required this.token,
    required this.url,
    required this.updatedAt,
  });

  final int funcionarioId;
  final String nombreCompleto;
  final String ci;
  final String cargo;
  final String oficina;
  final String token;
  final String url;
  final DateTime updatedAt;

  factory ActiveRatingQr.fromJson(Map<String, dynamic> source) {
    return ActiveRatingQr(
      funcionarioId: _readInt(source['funcionarioId'], 'funcionarioId'),
      nombreCompleto: _readString(source['nombreCompleto'], 'nombreCompleto'),
      ci: _readString(source['ci'], 'ci'),
      cargo: _readString(source['cargo'], 'cargo'),
      oficina: _readString(source['oficina'], 'oficina'),
      token: _readString(source['token'], 'token'),
      url: _readString(source['url'], 'url'),
      updatedAt: DateTime.parse(
        _readString(source['updatedAt'], 'updatedAt'),
      ).toLocal(),
    );
  }
}

class RatingQr {
  const RatingQr({
    required this.funcionario,
    required this.token,
    required this.url,
  });

  final RatingFuncionario funcionario;
  final String token;
  final String url;

  factory RatingQr.fromJson(Map<String, dynamic> source) {
    return RatingQr(
      funcionario: RatingFuncionario.fromJson(
        _readMap(source['funcionario'], 'funcionario'),
      ),
      token: _readString(source['token'], 'token'),
      url: _readString(source['url'], 'url'),
    );
  }
}

class RatingReport {
  const RatingReport({
    required this.fechaInicio,
    required this.fechaFin,
    required this.funcionarios,
  });

  final String fechaInicio;
  final String fechaFin;
  final List<RatingSummary> funcionarios;

  factory RatingReport.fromJson(Map<String, dynamic> source) {
    final rows = source['funcionarios'];
    if (rows is! List) {
      throw StateError('El reporte no tiene un formato valido.');
    }

    return RatingReport(
      fechaInicio: source['fechaInicio'] as String? ?? '',
      fechaFin: source['fechaFin'] as String? ?? '',
      funcionarios: rows
          .map((item) => RatingSummary.fromJson(_readMap(item, 'funcionario')))
          .toList(growable: false),
    );
  }
}

class RatingSummary {
  const RatingSummary({
    required this.funcionarioId,
    required this.nombreCompleto,
    required this.ci,
    required this.cargo,
    required this.oficina,
    required this.total,
    required this.muyMalo,
    required this.malo,
    required this.regular,
    required this.bueno,
    required this.muyBueno,
    required this.comentarios,
  });

  final int funcionarioId;
  final String nombreCompleto;
  final String ci;
  final String cargo;
  final String oficina;
  final int total;
  final int muyMalo;
  final int malo;
  final int regular;
  final int bueno;
  final int muyBueno;
  final List<RatingComment> comentarios;

  factory RatingSummary.fromJson(Map<String, dynamic> source) {
    final comments = source['comentarios'];
    return RatingSummary(
      funcionarioId: _readInt(source['funcionarioId'], 'funcionarioId'),
      nombreCompleto: _readString(source['nombreCompleto'], 'nombreCompleto'),
      ci: _readString(source['ci'], 'ci'),
      cargo: _readString(source['cargo'], 'cargo'),
      oficina: _readString(source['oficina'], 'oficina'),
      total: _readInt(source['total'], 'total'),
      muyMalo: _readInt(source['muyMalo'], 'muyMalo'),
      malo: _readInt(source['malo'], 'malo'),
      regular: _readInt(source['regular'], 'regular'),
      bueno: _readInt(source['bueno'], 'bueno'),
      muyBueno: _readInt(source['muyBueno'], 'muyBueno'),
      comentarios: comments is List
          ? comments
                .map(
                  (item) =>
                      RatingComment.fromJson(_readMap(item, 'comentario')),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class RatingComment {
  const RatingComment({
    required this.calificacion,
    required this.comentario,
    required this.calificadorNombre,
    required this.calificadorCelular,
    required this.createdAt,
  });

  final String calificacion;
  final String comentario;
  final String calificadorNombre;
  final String calificadorCelular;
  final DateTime createdAt;

  factory RatingComment.fromJson(Map<String, dynamic> source) {
    return RatingComment(
      calificacion: _readString(source['calificacion'], 'calificacion'),
      comentario: _readString(source['comentario'], 'comentario'),
      calificadorNombre: source['calificadorNombre'] as String? ?? '',
      calificadorCelular: source['calificadorCelular'] as String? ?? '',
      createdAt: DateTime.parse(
        _readString(source['createdAt'], 'createdAt'),
      ).toLocal(),
    );
  }
}

class RatingFuncionario {
  const RatingFuncionario({
    required this.id,
    required this.nombreCompleto,
    required this.ci,
    required this.cargo,
    required this.oficina,
    required this.fotoUrl,
  });

  final int id;
  final String nombreCompleto;
  final String ci;
  final String cargo;
  final String oficina;
  final String fotoUrl;

  factory RatingFuncionario.fromJson(Map<String, dynamic> source) {
    return RatingFuncionario(
      id: _readInt(source['id'], 'id'),
      nombreCompleto: _readString(source['nombreCompleto'], 'nombreCompleto'),
      ci: _readString(source['ci'], 'ci'),
      cargo: _readString(source['cargo'], 'cargo'),
      oficina: _readString(source['oficina'], 'oficina'),
      fotoUrl: source['fotoUrl'] as String? ?? '',
    );
  }
}

Map<String, dynamic> _readMap(dynamic source, String fieldName) {
  if (source is! Map<String, dynamic>) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return source;
}

String _readString(dynamic value, String fieldName) {
  if (value is! String) {
    throw StateError('El campo $fieldName no tiene un formato valido.');
  }

  return value;
}

int _readInt(dynamic value, String fieldName) {
  if (value is int) {
    return value;
  }

  throw StateError('El campo $fieldName no tiene un formato valido.');
}
