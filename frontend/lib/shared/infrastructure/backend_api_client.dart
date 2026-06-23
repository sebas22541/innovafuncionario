import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
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
      _baseUrl = (baseUrl ?? _resolveBaseUrl()).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;
  static final AesGcm _payloadCipher = AesGcm.with256bits();
  static final Random _secureRandom = Random.secure();
  static Future<SecretKey>? _payloadSecretKey;
  static const int _encryptedNonceLength = 12;
  static const int _encryptedTagLength = 16;

  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final response = await _client.get(
        _buildUri(path),
        headers: await _buildHeaders(),
      );
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
        headers: await _buildHeaders(contentTypeJson: true),
        body: await _encodeJsonBody(body),
      );

      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<Uint8List> postBytes(String path, Map<String, dynamic> body) async {
    try {
      final response = await _client.post(
        _buildUri(path),
        headers: await _buildHeaders(contentTypeJson: true),
        body: await _encodeJsonBody(body),
      );

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

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.put(
        _buildUri(path),
        headers: await _buildHeaders(contentTypeJson: true),
        body: await _encodeJsonBody(body),
      );

      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    try {
      final response = await _client.delete(
        _buildUri(path),
        headers: await _buildHeaders(),
      );
      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Future<Map<String, dynamic>> deleteJsonWithBody(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final request = http.Request('DELETE', _buildUri(path))
        ..headers.addAll(await _buildHeaders(contentTypeJson: true))
        ..body = await _encodeJsonBody(body);
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      return _decodeResponse(response);
    } catch (error) {
      throw _mapRequestError(error);
    }
  }

  Uri _buildUri(String path) => Uri.parse('$_baseUrl$path');

  Future<String> _encodeJsonBody(Map<String, dynamic> body) async {
    final envelope = await _encryptJsonPayload(body);

    return jsonEncode(envelope ?? body);
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
          'No fue posible conectar con el backend en $_baseUrl. Verifica que el servidor este levantado.',
      statusCode: 0,
    );
  }

  Future<Map<String, dynamic>> _decodeResponse(http.Response response) async {
    final rawBody = response.body.trim();
    final payload = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;
    final Map<String, dynamic> resolvedPayload = _isEncryptedEnvelope(payload)
        ? await _decryptJsonPayload(payload)
        : payload;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return resolvedPayload;
    }

    final errorMessage =
        resolvedPayload['error'] as String? ??
        resolvedPayload['details'] as String? ??
        'No fue posible completar la solicitud.';

    throw BackendApiException(
      message: errorMessage,
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, dynamic>?> _encryptJsonPayload(
    Map<String, dynamic> payload,
  ) async {
    final secretKey = await _readPayloadSecretKey();

    if (secretKey == null) {
      return null;
    }

    final nonce = List<int>.generate(12, (_) => _secureRandom.nextInt(256));
    final secretBox = await _payloadCipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: secretKey,
      nonce: nonce,
    );

    return {
      'd': base64Encode([
        ...secretBox.nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]),
    };
  }

  Future<Map<String, dynamic>> _decryptJsonPayload(
    Map<String, dynamic> envelope,
  ) async {
    final secretKey = await _readPayloadSecretKey();

    if (secretKey == null) {
      throw const BackendApiException(
        message: 'La respuesta cifrada no esta configurada en el cliente.',
        statusCode: 0,
      );
    }

    final compactEnvelope = envelope['d'];

    if (compactEnvelope is String && compactEnvelope.trim().isNotEmpty) {
      final encryptedEnvelope = base64Decode(compactEnvelope);

      if (encryptedEnvelope.length <=
          _encryptedNonceLength + _encryptedTagLength) {
        throw const BackendApiException(
          message: 'La respuesta cifrada no tiene un formato valido.',
          statusCode: 0,
        );
      }

      final nonce = encryptedEnvelope.sublist(0, _encryptedNonceLength);
      final cipherText = encryptedEnvelope.sublist(
        _encryptedNonceLength,
        encryptedEnvelope.length - _encryptedTagLength,
      );
      final tag = encryptedEnvelope.sublist(
        encryptedEnvelope.length - _encryptedTagLength,
      );

      final clearBytes = await _payloadCipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: secretKey,
      );

      return jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;
    }

    final clearBytes = await _payloadCipher.decrypt(
      SecretBox(
        base64Decode(envelope['payload'] as String),
        nonce: base64Decode(envelope['iv'] as String),
        mac: Mac(base64Decode(envelope['tag'] as String)),
      ),
      secretKey: secretKey,
    );

    return jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;
  }

  bool _isEncryptedEnvelope(Map<String, dynamic> payload) {
    return payload['d'] is String ||
        payload['encrypted'] == true &&
            payload['alg'] == 'AES-256-GCM' &&
            payload['iv'] is String &&
            payload['payload'] is String &&
            payload['tag'] is String;
  }

  Future<SecretKey?> _readPayloadSecretKey() {
    final configuredKey = AppEnvironment.payloadEncryptionKey.trim();

    if (configuredKey.isEmpty) {
      return Future.value(null);
    }

    return _payloadSecretKey ??= Sha256()
        .hash(utf8.encode(configuredKey))
        .then((hash) => SecretKey(hash.bytes));
  }

  static String _resolveBaseUrl() {
    return AppEnvironment.resolveBackendBaseUrl();
  }
}
