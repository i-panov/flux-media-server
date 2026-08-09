import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  SettingsLocalDataSource(this._prefs, this._secureStorage);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  /// Prefix all storage keys so debug and release builds don't share data.
  static const String _prefix = kDebugMode ? 'debug_' : 'release_';

  static const _keyServerUrl = 'server_url';
  static const _keyAuthToken = 'auth_token';
  static const _keyAuthTokenFallback = 'auth_token_insecure';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyRefreshTokenFallback = 'refresh_token_insecure';
  static const _keyLocale = 'locale';

  String _p(String key) => '$_prefix$key';

  String? getServerUrl() => _prefs.getString(_p(_keyServerUrl));

  Future<void> setServerUrl(String url) async {
    final success = await _prefs.setString(_p(_keyServerUrl), url);
    if (!success) {
      throw Exception('Failed to save server URL to SharedPreferences');
    }
  }

  String getLocale() => _prefs.getString(_p(_keyLocale)) ?? 'en';

  Future<void> setLocale(String locale) =>
      _prefs.setString(_p(_keyLocale), locale);

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

  Future<String?> getRefreshToken() async {
    try {
      return await _secureStorage.read(key: _p(_keyRefreshToken));
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      return _prefs.getString(_p(_keyRefreshTokenFallback));
    }
  }

  Future<void> setRefreshToken(String token) async {
    try {
      await _secureStorage.write(key: _p(_keyRefreshToken), value: token);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.setString(_p(_keyRefreshTokenFallback), token);
    }
  }

  Future<void> clearRefreshToken() async {
    try {
      await _secureStorage.delete(key: _p(_keyRefreshToken));
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.remove(_p(_keyRefreshTokenFallback));
    }
  }
}
