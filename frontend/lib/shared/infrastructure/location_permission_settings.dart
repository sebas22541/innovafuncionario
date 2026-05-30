import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationPermissionSettings {
  const LocationPermissionSettings._();

  static const _enabledKey = 'qr_asistencia.location_enabled';

  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
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
