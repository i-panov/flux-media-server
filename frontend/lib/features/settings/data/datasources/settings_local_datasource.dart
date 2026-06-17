import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  SettingsLocalDataSource(this._prefs);

  final SharedPreferences _prefs;

  static const _keyServerUrl = 'server_url';
  static const _keyAuthToken = 'auth_token';

  String? getServerUrl() => _prefs.getString(_keyServerUrl);

  Future<void> setServerUrl(String url) => _prefs.setString(_keyServerUrl, url);

  String? getAuthToken() => _prefs.getString(_keyAuthToken);

  Future<void> setAuthToken(String token) => _prefs.setString(_keyAuthToken, token);

  Future<void> clearAuthToken() => _prefs.remove(_keyAuthToken);
}
