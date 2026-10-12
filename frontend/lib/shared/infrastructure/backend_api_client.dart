import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/config/app_environment.dart';
import 'session_store.dart';

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
      _baseUrls = _resolveBaseUrls(baseUrl);

  final http.Client _client;
  final List<String> _baseUrls;
  static Future<void> Function()? onUnauthorizedSession;

  Future<Map<String, dynamic>> getJson(String path) async {
    return _sendJsonRequest(
      path,
      (uri, headers) => _client.get(uri, headers: headers),
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final encodedBody = await _encodeJsonBody(body);

    return _sendJsonRequest(
      path,
      (uri, headers) => _client.post(uri, headers: headers, body: encodedBody),
      contentTypeJson: true,
    );
  }

  Future<Uint8List> postBytes(String path, Map<String, dynamic> body) async {
    final encodedBody = await _encodeJsonBody(body);

    return _sendBytesRequest(
      path,
      (uri, headers) => _client.post(uri, headers: headers, body: encodedBody),
      contentTypeJson: true,
    );
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final encodedBody = await _encodeJsonBody(body);

    return _sendJsonRequest(
      path,
      (uri, headers) => _client.put(uri, headers: headers, body: encodedBody),
      contentTypeJson: true,
    );
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    return _sendJsonRequest(
      path,
      (uri, headers) => _client.delete(uri, headers: headers),
    );
  }

  Future<Map<String, dynamic>> deleteJsonWithBody(
    String path,
    Map<String, dynamic> body,
  ) async {
    final encodedBody = await _encodeJsonBody(body);

    return _sendJsonRequest(path, (uri, headers) async {
      final request = http.Request('DELETE', uri)
        ..headers.addAll(headers)
        ..body = encodedBody;
      final streamedResponse = await _client.send(request);

      return http.Response.fromStream(streamedResponse);
    }, contentTypeJson: true);
  }

  Uri _buildUri(String path, [String? baseUrl]) {
    return Uri.parse('${baseUrl ?? _baseUrls.first}$path');
  }

  Future<Map<String, dynamic>> _sendJsonRequest(
    String path,
    Future<http.Response> Function(Uri uri, Map<String, String> headers) send, {
    bool contentTypeJson = false,
  }) async {
    try {
      final response = await _sendWithFallback(path, send, contentTypeJson);

      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<Uint8List> _sendBytesRequest(
    String path,
    Future<http.Response> Function(Uri uri, Map<String, String> headers) send, {
    bool contentTypeJson = false,
  }) async {
    try {
      final response = await _sendWithFallback(path, send, contentTypeJson);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }

      await _decodeResponse(response);
      throw const BackendApiException(
        message: 'No fue posible completar la solicitud.',
        statusCode: 0,
      );
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<http.Response> _sendWithFallback(
    String path,
    Future<http.Response> Function(Uri uri, Map<String, String> headers) send,
    bool contentTypeJson,
  ) async {
    Object? lastError;

    for (final baseUrl in _baseUrls) {
      try {
        final response = await send(
          _buildUri(path, baseUrl),
          await _buildHeaders(contentTypeJson: contentTypeJson),
        );

        if (!_shouldTryFallback(response)) {
          return response;
        }

        lastError = BackendApiException(
          message: 'El backend respondio con error ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is BackendApiException) {
      throw lastError;
    }

    throw lastError ??
        const BackendApiException(
          message: 'No fue posible completar la solicitud.',
          statusCode: 0,
        );
  }

  bool _shouldTryFallback(http.Response response) {
    return _baseUrls.length > 1 && response.statusCode >= 500;
  }

  Future<String> _encodeJsonBody(Map<String, dynamic> body) async {
    return jsonEncode(body);
  }

  Future<Map<String, String>> _buildHeaders({
    bool contentTypeJson = false,
  }) async {
    final token = await SessionStore.readAuthToken();

    return {
      if (contentTypeJson) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  BackendApiException _mapRequestError(Object error) {
    if (error is BackendApiException) {
      return error;
    }

    return BackendApiException(
      message:
          'No fue posible conectar con el backend en ${_baseUrls.join(' o ')}. Verifica que el servidor este levantado.',
      statusCode: 0,
    );
  }

  Future<Map<String, dynamic>> _decodeResponse(http.Response response) async {
    final rawBody = response.body.trim();
    final payload = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;
    final resolvedPayload = payload;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return resolvedPayload;
    }

    final errorMessage =
        resolvedPayload['error'] as String? ??
        resolvedPayload['details'] as String? ??
        'No fue posible completar la solicitud.';

    if (response.statusCode == 401) {
      final token = await SessionStore.readAuthToken();

      if (token != null) {
        await SessionStore.clearSession();
        await onUnauthorizedSession?.call();
      }
    }

    throw BackendApiException(
      message: errorMessage,
      statusCode: response.statusCode,
    );
  }

  static List<String> _resolveBaseUrls(String? baseUrl) {
    final primaryBaseUrl = (baseUrl ?? AppEnvironment.resolveBackendBaseUrl())
        .replaceFirst(RegExp(r'/$'), '');

    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      return [primaryBaseUrl];
    }

    const fallbackBaseUrl = AppEnvironment.productionBackendBaseUrl;

    if (AppEnvironment.production &&
        primaryBaseUrl != fallbackBaseUrl.replaceFirst(RegExp(r'/$'), '')) {
      return [primaryBaseUrl, fallbackBaseUrl];
    }

    return [primaryBaseUrl];
  }
}
