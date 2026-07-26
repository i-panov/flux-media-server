import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String? getServerUrl() => _prefs.getString(_keyServerUrl);

  Future<void> setServerUrl(String url) => _prefs.setString(_keyServerUrl, url);

  String getLocale() => _prefs.getString(_keyLocale) ?? 'en';

  Future<void> setLocale(String locale) => _prefs.setString(_keyLocale, locale);

  Future<String?> getAuthToken() async {
    try {
      return await _secureStorage.read(key: _keyAuthToken);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      return _prefs.getString(_keyAuthTokenFallback);
    }
  }

  Future<void> setAuthToken(String token) async {
    try {
      await _secureStorage.write(key: _keyAuthToken, value: token);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.setString(_keyAuthTokenFallback, token);
    }
  }

  Future<void> clearAuthToken() async {
    try {
      await _secureStorage.delete(key: _keyAuthToken);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.remove(_keyAuthTokenFallback);
    }
  }

  Future<String?> getRefreshToken() async {
    try {
      return await _secureStorage.read(key: _keyRefreshToken);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      return _prefs.getString(_keyRefreshTokenFallback);
    }
  }

  Future<void> setRefreshToken(String token) async {
    try {
      await _secureStorage.write(key: _keyRefreshToken, value: token);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.setString(_keyRefreshTokenFallback, token);
    }
  }

  Future<void> clearRefreshToken() async {
    try {
      await _secureStorage.delete(key: _keyRefreshToken);
    } catch (e) {
      developer.log('Secure storage unavailable, using fallback: $e');
      await _prefs.remove(_keyRefreshTokenFallback);
    }
  }
}
