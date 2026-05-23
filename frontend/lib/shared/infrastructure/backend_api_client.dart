import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_environment.dart';

class BackendApiException implements Exception {
  const BackendApiException({required this.message, required this.statusCode});

  final String message;
  final int statusCode;

  @override
  String toString() => 'BackendApiException($statusCode): $message';
}

class BackendApiClient {
  BackendApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? _resolveBaseUrl()).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final response = await _client.get(_buildUri(path));
      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.post(
        _buildUri(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.put(
        _buildUri(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    try {
      final response = await _client.delete(_buildUri(path));
      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Uri _buildUri(String path) => Uri.parse('$_baseUrl$path');

  BackendApiException _mapRequestError(Object error) {
    if (error is BackendApiException) {
      return error;
    }

    return BackendApiException(
      message:
          'No fue posible conectar con el backend en $_baseUrl. Verifica que el servidor este levantado.',
      statusCode: 0,
    );
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final rawBody = response.body.trim();
    final payload = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    final errorMessage =
        payload['error'] as String? ??
        payload['details'] as String? ??
        'No fue posible completar la solicitud.';

    throw BackendApiException(
      message: errorMessage,
      statusCode: response.statusCode,
    );
  }

  static String _resolveBaseUrl() {
    return AppEnvironment.resolveBackendBaseUrl();
  }
}
