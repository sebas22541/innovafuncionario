import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../injection_container.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!_supportsFirebaseMessaging) {
    return;
  }

  await Firebase.initializeApp();
}

class FirebaseNotificationsService {
  FirebaseNotificationsService._();

  static StreamSubscription<String>? _tokenRefreshSubscription;
  static String? _registeredToken;
  static String? _registeredPlatform;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!_supportsFirebaseMessaging || _initialized) {
      return;
    }

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  static Future<void> registerCurrentDevice() async {
    if (!_supportsFirebaseMessaging) {
      return;
    }

    await initialize();

    if (!_initialized) {
      return;
    }

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    final token = await messaging.getToken();
    final platform = _currentPlatform;

    if (token == null || platform == null) {
      return;
    }

    await dependencies.notificationsApiService.registerDeviceToken(
      token: token,
      platform: platform,
    );
    _registeredToken = token;
    _registeredPlatform = platform;

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((nextToken) {
      dependencies.notificationsApiService.registerDeviceToken(
        token: nextToken,
        platform: platform,
      );
      _registeredToken = nextToken;
      _registeredPlatform = platform;
    });
  }

  static Future<void> unregisterCurrentDevice() async {
    final token = _registeredToken;
    final platform = _registeredPlatform;

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _registeredToken = null;
    _registeredPlatform = null;

    if (token == null || platform == null) {
      return;
    }

    try {
      await dependencies.notificationsApiService.deleteDeviceToken(
        token: token,
        platform: platform,
      );
    } catch (_) {
      // El cierre de sesion no debe quedar bloqueado por la baja del token.
    }
  }
}

bool get _supportsFirebaseMessaging {
  if (kIsWeb) {
    return false;
  }

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String? get _currentPlatform {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'ANDROID';
  }

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return 'IOS';
  }

  return null;
}
