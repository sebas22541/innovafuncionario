import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';

class AppPermissionsService {
  const AppPermissionsService._();

  static const _preflightVersion = 1;
  static const _preflightKey =
      'qr_asistencia.permissions_preflight_v$_preflightVersion';

  static Future<void> requestStartupPermissions(AppUser user) async {
    final preferences = await SharedPreferences.getInstance();
    final alreadyRequested = preferences.getBool(_preflightKey) ?? false;

    if (alreadyRequested) {
      return;
    }

    await _requestIfNeeded(Permission.locationWhenInUse);

    if (user.canUseEventScanner) {
      await _requestIfNeeded(Permission.camera);
    }

    await preferences.setBool(_preflightKey, true);
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
}
