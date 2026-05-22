import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'injection_container.dart';
import 'shared/models/app_user.dart';
import 'shared/widgets/app_navigation_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  void _handleAuthenticated(AppUser user) {
    setState(() {
      _currentUser = user;
    });
  }

  void _handleLogout() {
    setState(() {
      _currentUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Asistencia',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('es', 'BO'),
      supportedLocales: const [
        Locale('es'),
        Locale('es', 'BO'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _currentUser == null
            ? AuthScreen(
                key: const ValueKey('auth-screen'),
                onAuthenticated: _handleAuthenticated,
              )
            : AppNavigationShell(
                key: const ValueKey('app-shell'),
                currentUser: _currentUser!,
                onLogout: _handleLogout,
              ),
      ),
    );
  }
}
