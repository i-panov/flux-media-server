import 'package:flux_media_server/core/session/app_settings.dart';

/// Repository for application settings and authentication token storage.
abstract class SettingsRepository {
  Future<AppSettings> getSettings();
  Future<void> setServerUrl(String url);
  Future<void> setAuthToken(String token);
  Future<void> clearAuthToken();
  Future<void> setRefreshToken(String token);
  Future<void> clearRefreshToken();
  String getLocale();
  Future<void> setLocale(String locale);
}
