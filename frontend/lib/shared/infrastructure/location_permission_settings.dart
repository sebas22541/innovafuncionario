import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_preference_cipher.dart';

class LocationPermissionSettings {
  const LocationPermissionSettings._();

  static const _enabledKey = 'qr_asistencia.location_enabled';

  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    String? rawValue;

    try {
      rawValue = preferences.getString(_enabledKey);
    } catch (_) {
      rawValue = null;
    }

    final storedValue = await LocalPreferenceCipher.decryptString(rawValue);

    if (storedValue != null) {
      final enabled = storedValue == 'true';

      if (!LocalPreferenceCipher.isEncrypted(rawValue)) {
        await setEnabled(enabled);
      }

      return enabled;
    }

    bool? legacyValue;

    try {
      legacyValue = preferences.getBool(_enabledKey);
    } catch (_) {
      legacyValue = null;
    }

    if (legacyValue != null) {
      await setEnabled(legacyValue);
    }

    return legacyValue ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _enabledKey,
      await LocalPreferenceCipher.encryptString(enabled.toString()),
    );
  }

  static Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  static Future<bool> isServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  static Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }

  static Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  static Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }
}

extension LocationPermissionX on LocationPermission {
  bool get isAllowed {
    return this == LocationPermission.always ||
        this == LocationPermission.whileInUse;
  }
}
