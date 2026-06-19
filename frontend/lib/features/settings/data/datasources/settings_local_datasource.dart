import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  SettingsLocalDataSource(this._prefs, this._secureStorage);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  static const _keyServerUrl = 'server_url';
  static const _keyAuthToken = 'auth_token';

  String? getServerUrl() => _prefs.getString(_keyServerUrl);

  Future<void> setServerUrl(String url) => _prefs.setString(_keyServerUrl, url);

  Future<String?> getAuthToken() => _secureStorage.read(key: _keyAuthToken);

  Future<void> setAuthToken(String token) =>
      _secureStorage.write(key: _keyAuthToken, value: token);

  Future<void> clearAuthToken() => _secureStorage.delete(key: _keyAuthToken);
}
