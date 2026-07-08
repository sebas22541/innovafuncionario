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

  Future<RatingReport> fetchReport({required String fecha}) async {
    final payload = await _apiClient.getJson(
      '/api/calificaciones?fecha=${Uri.encodeQueryComponent(fecha)}',
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
  }) async {
    await _apiClient
        .postJson('/api/calificaciones/publica/${Uri.encodeComponent(token)}', {
          'calificacion': calificacion,
          'comentario': comentario,
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
  const RatingReport({required this.fecha, required this.funcionarios});

  final String fecha;
  final List<RatingSummary> funcionarios;

  factory RatingReport.fromJson(Map<String, dynamic> source) {
    final rows = source['funcionarios'];
    if (rows is! List) {
      throw StateError('El reporte no tiene un formato valido.');
    }

    return RatingReport(
      fecha: _readString(source['fecha'], 'fecha'),
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
    required this.cargo,
    required this.oficina,
    required this.total,
    required this.feliz,
    required this.neutral,
    required this.enojada,
    required this.comentarios,
  });

  final int funcionarioId;
  final String nombreCompleto;
  final String cargo;
  final String oficina;
  final int total;
  final int feliz;
  final int neutral;
  final int enojada;
  final List<RatingComment> comentarios;

  factory RatingSummary.fromJson(Map<String, dynamic> source) {
    final comments = source['comentarios'];
    return RatingSummary(
      funcionarioId: _readInt(source['funcionarioId'], 'funcionarioId'),
      nombreCompleto: _readString(source['nombreCompleto'], 'nombreCompleto'),
      cargo: _readString(source['cargo'], 'cargo'),
      oficina: _readString(source['oficina'], 'oficina'),
      total: _readInt(source['total'], 'total'),
      feliz: _readInt(source['feliz'], 'feliz'),
      neutral: _readInt(source['neutral'], 'neutral'),
      enojada: _readInt(source['enojada'], 'enojada'),
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
    required this.createdAt,
  });

  final String calificacion;
  final String comentario;
  final DateTime createdAt;

  factory RatingComment.fromJson(Map<String, dynamic> source) {
    return RatingComment(
      calificacion: _readString(source['calificacion'], 'calificacion'),
      comentario: _readString(source['comentario'], 'comentario'),
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
  });

  final int id;
  final String nombreCompleto;
  final String ci;
  final String cargo;
  final String oficina;

  factory RatingFuncionario.fromJson(Map<String, dynamic> source) {
    return RatingFuncionario(
      id: _readInt(source['id'], 'id'),
      nombreCompleto: _readString(source['nombreCompleto'], 'nombreCompleto'),
      ci: _readString(source['ci'], 'ci'),
      cargo: _readString(source['cargo'], 'cargo'),
      oficina: _readString(source['oficina'], 'oficina'),
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
