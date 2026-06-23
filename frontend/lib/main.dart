import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'injection_container.dart';
import 'shared/infrastructure/app_image_cache.dart';
import 'shared/infrastructure/backend_api_client.dart';
import 'shared/infrastructure/firebase_notifications_service.dart';
import 'shared/infrastructure/session_store.dart';
import 'shared/models/app_section.dart';
import 'shared/models/app_user.dart';
import 'shared/widgets/app_navigation_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppImageCache.configure();
  await FirebaseNotificationsService.initialize();
  await initDependencies();
  runApp(const QrWebApp());
}

class QrWebApp extends StatefulWidget {
  const QrWebApp({super.key});

  @override
  State<QrWebApp> createState() => _QrWebAppState();
}

class _QrWebAppState extends State<QrWebApp> {
  AppUser? _currentUser;
  AppSection? _initialSection;
  final int _sectionRequestToken = 0;
  int _notificationsRefreshToken = 0;
  int _notificationsOpenToken = 0;
  bool _isRestoringSession = true;

  @override
  void initState() {
    super.initState();
    FirebaseNotificationsService.configureNavigation(
      onOpenNotifications: _openNotificationsFromNotification,
      onNotificationsChanged: _handleNotificationsChanged,
    );
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final section = await SessionStore.readSection();
    final storedUser = await SessionStore.readUser();
    AppUser? user;

    if (storedUser != null) {
      try {
        user = await dependencies.authApiService.fetchCurrentUser();
        await SessionStore.saveUser(user);
        await FirebaseNotificationsService.registerCurrentDevice();
      } on BackendApiException catch (error) {
        if (error.statusCode == 401) {
          await SessionStore.clearSession();
        } else {
          user = storedUser;
        }
      } catch (_) {
        user = storedUser;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = user;
      _initialSection = section;
      _isRestoringSession = false;
    });
  }

  void _handleAuthenticated(AppUser user) async {
    await SessionStore.saveUser(user);
    await FirebaseNotificationsService.registerCurrentDevice();

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = user;
      _initialSection = null;
    });
  }

  void _handleLogout() async {
    await FirebaseNotificationsService.unregisterCurrentDevice();

    try {
      await dependencies.authApiService.logout();
    } catch (_) {
      // Si el backend no responde, igual se limpia la sesion local.
    }

    await SessionStore.clearSession();

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = null;
      _initialSection = null;
    });
  }

  void _handleCurrentUserChanged(AppUser user) async {
    await SessionStore.saveUser(user);

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = user;
    });
  }

  void _handleNotificationsChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _notificationsRefreshToken++;
    });
  }

  void _openNotificationsFromNotification() {
    if (!mounted) {
      return;
    }

    setState(() {
      _notificationsOpenToken++;
      _notificationsRefreshToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Asistencia',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('es', 'BO'),
      supportedLocales: const [Locale('es'), Locale('es', 'BO')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _isRestoringSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _currentUser == null
                  ? AuthScreen(
                      key: const ValueKey('auth-screen'),
                      onAuthenticated: _handleAuthenticated,
                    )
                  : AppNavigationShell(
                      key: const ValueKey('app-shell'),
                      currentUser: _currentUser!,
                      initialSection: _initialSection,
                      sectionRequestToken: _sectionRequestToken,
                      notificationsRefreshToken: _notificationsRefreshToken,
                      notificationsOpenToken: _notificationsOpenToken,
                      onCurrentUserChanged: _handleCurrentUserChanged,
                      onSectionChanged: SessionStore.saveSection,
                      onLogout: _handleLogout,
                    ),
            ),
    );
  }
}
