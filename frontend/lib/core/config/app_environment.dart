import 'package:flutter/foundation.dart';

class AppEnvironment {
  const AppEnvironment._();

  static const production = bool.fromEnvironment('dart.vm.product');
  static const productionBackendBaseUrl =
      'https://innovafuncionarioapi.cochabamba.bo';
  static const payloadEncryptionKey = String.fromEnvironment(
    'PAYLOAD_ENCRYPTION_KEY',
  );

  static String resolveBackendBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (production) {
      return productionBackendBaseUrl;
    }

    if (!kIsWeb) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return 'http://10.0.2.2:3000';
      }

      return 'http://localhost:4000';
    }

    final currentUri = Uri.base;
    final host = currentUri.host.isEmpty ? 'localhost' : currentUri.host;
    final scheme = currentUri.scheme == 'https' ? 'https' : 'http';

    return '$scheme://$host:3000';
  }
}
