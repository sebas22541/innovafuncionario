import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_section.dart';
import '../models/app_user.dart';
import 'local_preference_cipher.dart';

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
    final storedUser = await LocalPreferenceCipher.decryptString(rawUser);

    if (storedUser == null || storedUser.trim().isEmpty) {
      return null;
    }

    try {
      final parsedUser = jsonDecode(storedUser);

      if (parsedUser is! Map<String, dynamic>) {
        await clearSession();
        return null;
      }

      final user = AppUser.fromJson(parsedUser);
      _cachedUser = user;
      if (!LocalPreferenceCipher.isEncrypted(rawUser)) {
        await _writeEncryptedString(
          preferences,
          _userKey,
          jsonEncode(user.toJson()),
        );
      }

      return user;
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  static Future<void> saveUser(AppUser user) async {
    final userToSave = await _withPersistableAuthToken(user);
    _cachedUser = userToSave;
    final preferences = await SharedPreferences.getInstance();
    await _writeEncryptedString(
      preferences,
      _userKey,
      jsonEncode(userToSave.toJson()),
    );
  }

  static Future<String?> readAuthToken() async {
    final user = await readUser();
    final token = user?.authToken?.trim();

    return token == null || token.isEmpty ? null : token;
  }

  static Future<AppSection?> readSection() async {
    final preferences = await SharedPreferences.getInstance();
    final rawSection = preferences.getString(_sectionKey);
    final storedSection = await LocalPreferenceCipher.decryptString(rawSection);
    final section = parseAppSection(storedSection);

    if (section != null && !LocalPreferenceCipher.isEncrypted(rawSection)) {
      await saveSection(section);
    }

    return section;
  }

  static Future<void> saveSection(AppSection section) async {
    final preferences = await SharedPreferences.getInstance();
    await _writeEncryptedString(preferences, _sectionKey, section.storageKey);
  }

  static Future<void> clearSession() async {
    _cachedUser = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_userKey);
    await preferences.remove(_sectionKey);
  }

  static Future<AppUser> _withPersistableAuthToken(AppUser user) async {
    final token = user.authToken?.trim();

    if (token != null && token.isNotEmpty) {
      return user;
    }

    final persistedToken = await _readPersistedAuthToken();

    if (persistedToken == null || persistedToken.isEmpty) {
      return user;
    }

    return user.withAuthToken(persistedToken);
  }

  static Future<String?> _readPersistedAuthToken() async {
    final cachedToken = _cachedUser?.authToken?.trim();

    if (cachedToken != null && cachedToken.isNotEmpty) {
      return cachedToken;
    }

    final preferences = await SharedPreferences.getInstance();
    final rawUser = preferences.getString(_userKey);
    final storedUser = await LocalPreferenceCipher.decryptString(rawUser);

    if (storedUser == null || storedUser.trim().isEmpty) {
      return null;
    }

    try {
      final parsedUser = jsonDecode(storedUser);

      if (parsedUser is! Map<String, dynamic>) {
        return null;
      }

      final token = parsedUser['authToken'] as String?;
      final normalizedToken = token?.trim();

      return normalizedToken == null || normalizedToken.isEmpty
          ? null
          : normalizedToken;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeEncryptedString(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    await preferences.setString(
      key,
      await LocalPreferenceCipher.encryptString(value),
    );
  }
}
