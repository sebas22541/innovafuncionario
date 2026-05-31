import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../core/config/app_environment.dart';

class LocalPreferenceCipher {
  const LocalPreferenceCipher._();

  static const prefix = 'lp1.';
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static final AesGcm _cipher = AesGcm.with256bits();
  static final Random _secureRandom = Random.secure();
  static Future<SecretKey?>? _secretKey;

  static bool isEncrypted(String? value) {
    return value?.startsWith(prefix) == true;
  }

  static Future<String> encryptString(String value) async {
    final secretKey = await _readSecretKey();

    if (secretKey == null) {
      return value;
    }

    final nonce = List<int>.generate(
      _nonceLength,
      (_) => _secureRandom.nextInt(256),
    );
    final secretBox = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: secretKey,
      nonce: nonce,
    );

    return '$prefix${base64UrlEncode([...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes])}';
  }

  static Future<String?> decryptString(String? value) async {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    if (!isEncrypted(value)) {
      return value;
    }

    final secretKey = await _readSecretKey();

    if (secretKey == null) {
      return null;
    }

    try {
      final encryptedEnvelope = base64Url.decode(
        value.substring(prefix.length),
      );

      if (encryptedEnvelope.length <= _nonceLength + _tagLength) {
        return null;
      }

      final nonce = encryptedEnvelope.sublist(0, _nonceLength);
      final cipherText = encryptedEnvelope.sublist(
        _nonceLength,
        encryptedEnvelope.length - _tagLength,
      );
      final tag = encryptedEnvelope.sublist(
        encryptedEnvelope.length - _tagLength,
      );
      final clearBytes = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: secretKey,
      );

      return utf8.decode(clearBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<SecretKey?> _readSecretKey() {
    return _secretKey ??= _buildSecretKey();
  }

  static Future<SecretKey?> _buildSecretKey() async {
    final configuredKey = AppEnvironment.payloadEncryptionKey.trim();

    if (configuredKey.isEmpty) {
      return null;
    }

    final hash = await Sha256().hash(utf8.encode(configuredKey));

    return SecretKey(hash.bytes);
  }
}
