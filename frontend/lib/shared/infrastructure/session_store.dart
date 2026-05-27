import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_section.dart';
import '../models/app_user.dart';

class SessionStore {
  const SessionStore._();

  static const _userKey = 'qr_asistencia.current_user';
  static const _sectionKey = 'qr_asistencia.current_section';
  static AppUser? _cachedUser;

  static Future<AppUser?> readUser() async {
    final cachedUser = _cachedUser;

    if (cachedUser != null) {
      return cachedUser;
    }

    final preferences = await SharedPreferences.getInstance();
    final rawUser = preferences.getString(_userKey);

    if (rawUser == null || rawUser.trim().isEmpty) {
      return null;
    }

    try {
      final parsedUser = jsonDecode(rawUser);

      if (parsedUser is! Map<String, dynamic>) {
        await clearSession();
        return null;
      }

      final user = AppUser.fromJson(parsedUser);
      _cachedUser = user;
      return user;
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  static Future<void> saveUser(AppUser user) async {
    _cachedUser = user;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_userKey, jsonEncode(user.toJson()));
  }

  static Future<String?> readAuthToken() async {
    final user = await readUser();
    final token = user?.authToken?.trim();

    return token == null || token.isEmpty ? null : token;
  }

  static Future<AppSection?> readSection() async {
    final preferences = await SharedPreferences.getInstance();
    return parseAppSection(preferences.getString(_sectionKey));
  }

  static Future<void> saveSection(AppSection section) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sectionKey, section.storageKey);
  }

  static Future<void> clearSession() async {
    _cachedUser = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_userKey);
    await preferences.remove(_sectionKey);
  }
}
