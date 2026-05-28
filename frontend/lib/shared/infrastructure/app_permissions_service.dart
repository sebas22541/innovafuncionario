import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'location_permission_settings.dart';

class AppPermissionsService {
  const AppPermissionsService._();

  static Future<void> requestStartupPermissions() async {
    if (!_shouldRequestAtStartup) {
      return;
    }

    await _requestIfNeeded(Permission.camera);
    await _requestLocationIfNeeded();
  }

  static Future<void> _requestIfNeeded(Permission permission) async {
    try {
      final status = await permission.status;

      if (status.isGranted || status.isLimited || status.isPermanentlyDenied) {
        return;
      }

      await permission.request();
    } catch (_) {
      // Some platforms or browsers do not expose every permission upfront.
      // The feature-level code still requests the permission when it is used.
    }
  }

  static Future<void> _requestLocationIfNeeded() async {
    try {
      var permission = await LocationPermissionSettings.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await LocationPermissionSettings.requestPermission();
      }

      await LocationPermissionSettings.setEnabled(permission.isAllowed);
    } catch (_) {
      // Location permission can be unavailable until the browser/device allows it.
      // The feature-level code still requests the permission when it is used.
    }
  }

  static bool get _shouldRequestAtStartup {
    if (kIsWeb) {
      return true;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
