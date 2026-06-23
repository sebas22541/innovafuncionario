import 'package:flutter/services.dart';

class KioskModeService {
  const KioskModeService._();

  static const MethodChannel _channel = MethodChannel(
    'com.innova.funcionario.cochabamba.bo/kiosk',
  );

  static Future<bool> enableLunchKiosk() async {
    try {
      return await _channel.invokeMethod<bool>('enableLunchKiosk') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> disableLunchKiosk() async {
    try {
      await _channel.invokeMethod<void>('disableLunchKiosk');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> setLunchKioskEnabled(bool enabled) {
    return enabled ? enableLunchKiosk() : disableLunchKiosk();
  }
}
