import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceStatusService {
  const DeviceStatusService._();

  static const MethodChannel _channel = MethodChannel(
    'com.innova.funcionario.cochabamba.bo/device_status',
  );
  static const _deviceIdKey = 'qr_asistencia.device_id';
  static final Random _random = Random.secure();

  static Future<Map<String, dynamic>> readStatus() async {
    final deviceId = await readDeviceId();
    final platform = defaultTargetPlatform.name.toUpperCase();

    try {
      final nativeStatus = await _channel.invokeMapMethod<String, dynamic>(
        'readDeviceStatus',
      );

      return {'deviceId': deviceId, 'platform': platform, ...?nativeStatus};
    } on MissingPluginException {
      return {'deviceId': deviceId, 'platform': platform};
    } on PlatformException {
      return {'deviceId': deviceId, 'platform': platform};
    }
  }

  static Future<String> readDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey)?.trim();

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = _generateDeviceId();
    await preferences.setString(_deviceIdKey, generated);

    return generated;
  }

  static String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix = List<int>.generate(
      18,
      (_) => _random.nextInt(36),
    ).map((value) => value.toRadixString(36)).join();

    return 'dev_$timestamp$suffix';
  }
}
