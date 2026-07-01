import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../injection_container.dart';

class ForegroundPushNotification {
  const ForegroundPushNotification({
    required this.title,
    required this.body,
    required this.targetSection,
    required this.exitPermitId,
  });

  final String title;
  final String body;
  final String? targetSection;
  final int? exitPermitId;
}

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
  static StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  static String? _registeredToken;
  static String? _registeredPlatform;
  static ValueChanged<ForegroundPushNotification>? _openNotification;
  static VoidCallback? _notificationsChanged;
  static VoidCallback? _deviceLoginRequested;
  static ValueChanged<ForegroundPushNotification>?
  _foregroundNotificationReceived;
  static bool _initialized = false;
  static bool _initialMessageChecked = false;
  static ForegroundPushNotification? _pendingNotificationOpen;
  static bool _pendingDeviceLogin = false;

  static void configureNavigation({
    required ValueChanged<ForegroundPushNotification> onOpenNotification,
    required VoidCallback onNotificationsChanged,
    required VoidCallback onDeviceLoginRequested,
    required ValueChanged<ForegroundPushNotification>
    onForegroundNotificationReceived,
  }) {
    _openNotification = onOpenNotification;
    _notificationsChanged = onNotificationsChanged;
    _deviceLoginRequested = onDeviceLoginRequested;
    _foregroundNotificationReceived = onForegroundNotificationReceived;

    final pendingNotification = _pendingNotificationOpen;
    if (pendingNotification != null) {
      _pendingNotificationOpen = null;
      onOpenNotification(pendingNotification);
    }

    if (_pendingDeviceLogin) {
      _pendingDeviceLogin = false;
      onDeviceLoginRequested();
    }

    if (_initialized) {
      _listenNotificationTaps();
    }
  }

  static Future<void> initialize() async {
    if (!_supportsFirebaseMessaging || _initialized) {
      return;
    }

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _initialized = true;
      _listenNotificationTaps();
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

  static void _listenNotificationTaps() {
    if (!_supportsFirebaseMessaging || !_initialized) {
      return;
    }

    _messageOpenedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
    );
    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen((
      message,
    ) {
      if (_isDeviceLoginMessage(message)) {
        _handleDeviceLoginRequest();
        return;
      }

      if (message.data['source'] == 'innovafuncionario') {
        _notificationsChanged?.call();
        _foregroundNotificationReceived?.call(_parseNotification(message));
      }
    });

    if (_initialMessageChecked) {
      return;
    }

    _initialMessageChecked = true;
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationTap(message);
      }
    });
  }

  static void _handleNotificationTap(RemoteMessage message) {
    if (_isDeviceLoginMessage(message)) {
      _handleDeviceLoginRequest();
      return;
    }

    if (message.data['source'] != 'innovafuncionario') {
      return;
    }

    _notificationsChanged?.call();
    final notification = _parseNotification(message);
    final notificationCallback = _openNotification;

    if (notificationCallback == null) {
      _pendingNotificationOpen = notification;
      return;
    }

    notificationCallback(notification);
  }

  static ForegroundPushNotification _parseNotification(RemoteMessage message) {
    return ForegroundPushNotification(
      title: message.notification?.title?.trim().isNotEmpty == true
          ? message.notification!.title!.trim()
          : 'Nueva notificación',
      body: message.notification?.body?.trim() ?? '',
      targetSection: _readOptionalText(message.data['targetSection']),
      exitPermitId: int.tryParse(message.data['salidaId'] ?? ''),
    );
  }

  static bool _isDeviceLoginMessage(RemoteMessage message) {
    return message.data['source'] == 'innovafuncionario' &&
        message.data['type'] == 'device_login' &&
        message.data['action'] == 'open_app';
  }

  static void _handleDeviceLoginRequest() {
    final callback = _deviceLoginRequested;

    if (callback == null) {
      _pendingDeviceLogin = true;
      return;
    }

    callback();
  }
}

String? _readOptionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
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
