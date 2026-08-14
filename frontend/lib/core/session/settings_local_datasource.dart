import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flux_media_server/core/utils/url_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Префикс ключей хранилища: debug- и release-сборки не делят данные.
/// Единая константа для SharedPreferences и FlutterSecureStorage.
const String storageKeyPrefix = kDebugMode ? 'debug_' : 'release_';

/// Local data source for application settings.
///
/// Token storage strategy:
/// - Auth tokens are stored in FlutterSecureStorage (encrypted).
/// - On platforms where secure storage is unavailable (e.g. iOS simulator),
///   tokens fall back to SharedPreferences (insecure, for development only).
/// - Server URL and locale are always stored in SharedPreferences.
class SettingsLocalDataSource {
  SettingsLocalDataSource(this._prefs, this._secureStorage);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  static const _keyServerUrl = 'server_url';
  static const _keyAuthToken = 'auth_token';
  static const _keyAuthTokenFallback = 'auth_token_insecure';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyRefreshTokenFallback = 'refresh_token_insecure';
  static const _keyLocale = 'locale';

  String _p(String key) => '$storageKeyPrefix$key';

  String? getServerUrl() => _prefs.getString(_p(_keyServerUrl));

  Future<void> setServerUrl(String url) async {
    // Нормализуем при сохранении, чтобы в хранилище всегда был
    // единый формат (полный baseUrl API с сегментом /api).
    final success =
        await _prefs.setString(_p(_keyServerUrl), normalizeServerUrl(url));
    if (!success) {
      throw Exception('Failed to save server URL to SharedPreferences');
    }
  }

  String getLocale() => _prefs.getString(_p(_keyLocale)) ?? 'en';

  Future<void> setLocale(String locale) =>
      _prefs.setString(_p(_keyLocale), locale);

  /// Reads the auth token from secure storage. Falls back to SharedPreferences
  /// only when secure storage is unavailable (e.g. iOS simulator).
  Future<String?> getAuthToken() async {
    try {
      return await _secureStorage.read(key: _p(_keyAuthToken));
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      return _prefs.getString(_p(_keyAuthTokenFallback));
    }
  }

  Future<void> setAuthToken(String token) async {
    try {
      await _secureStorage.write(key: _p(_keyAuthToken), value: token);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.setString(_p(_keyAuthTokenFallback), token);
    }
  }

  Future<void> clearAuthToken() async {
    try {
      await _secureStorage.delete(key: _p(_keyAuthToken));
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.remove(_p(_keyAuthTokenFallback));
    }
  }

  /// Reads the refresh token from secure storage. Falls back to
  /// SharedPreferences only when secure storage is unavailable (e.g. iOS
  /// simulator).
  ///
  /// NOTE: In production builds the fallback path should never be hit. If it
  /// is, tokens are stored insecurely — log a warning so developers catch
  /// this during testing.
  Future<String?> getRefreshToken() async {
    try {
      return await _secureStorage.read(key: _p(_keyRefreshToken));
    } catch (e) {
      developer.log(
          'WARNING: refresh token stored in insecure SharedPreferences: $e',
      );
      return _prefs.getString(_p(_keyRefreshTokenFallback));
    }
  }

  Future<void> setRefreshToken(String token) async {
    try {
      await _secureStorage.write(key: _p(_keyRefreshToken), value: token);
    } catch (e) {
      developer.log(
          'WARNING: refresh token stored in insecure SharedPreferences: $e',
      );
      await _prefs.setString(_p(_keyRefreshTokenFallback), token);
    }
  }

  Future<void> clearRefreshToken() async {
    try {
      await _secureStorage.delete(key: _p(_keyRefreshToken));
    } catch (e) {
      developer.log(
          'WARNING: refresh token stored in insecure SharedPreferences: $e',
      );
      await _prefs.remove(_p(_keyRefreshTokenFallback));
    }
  }
}
