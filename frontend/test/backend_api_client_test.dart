import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_asistencia_app/shared/infrastructure/backend_api_client.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'login sends ordinary JSON and reads the server response without a key',
    () async {
      final client = BackendApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Content-Type'], 'application/json');
          expect(jsonDecode(request.body), {
            'email': '123456',
            'password': 'test-password',
          });
          return http.Response(
            jsonEncode({
              'data': {'id': 1},
            }),
            200,
          );
        }),
      );
      expect(
        await client.postJson('/api/auth/login', {
          'email': '123456',
          'password': 'test-password',
        }),
        {
          'data': {'id': 1},
        },
      );
    },
  );

  test('server errors preserve their message and status', () async {
    final client = BackendApiClient(
      baseUrl: 'https://example.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'Credenciales incorrectas'}),
          401,
        ),
      ),
    );
    await expectLater(
      client.postJson('/api/auth/login', {}),
      throwsA(
        isA<BackendApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having(
              (error) => error.message,
              'message',
              'Credenciales incorrectas',
            ),
      ),
    );
  });
}
