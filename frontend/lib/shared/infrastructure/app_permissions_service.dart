import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionsService {
  const AppPermissionsService._();

  static Future<void> requestStartupPermissions() async {
    if (!_isMobilePlatform) {
      return;
    }

    await _requestIfNeeded(Permission.camera);
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

  static bool get _isMobilePlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
