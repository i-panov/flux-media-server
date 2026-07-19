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

  String? getServerUrl() => _prefs.getString(_keyServerUrl);

  Future<void> setServerUrl(String url) => _prefs.setString(_keyServerUrl, url);

  Future<String?> getAuthToken() async {
    try {
      return await _secureStorage.read(key: _keyAuthToken);
    } catch (e) {
      // Fallback to SharedPreferences if secure storage unavailable (e.g. WSL2).
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
}
