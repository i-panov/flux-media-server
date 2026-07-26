import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';

/// Repository for application settings and authentication token storage.
abstract class SettingsRepository {
  Future<AppSettings> getSettings();
  Future<void> setServerUrl(String url);
  Future<void> setAuthToken(String token);
  Future<void> clearAuthToken();
  String getLocale();
  Future<void> setLocale(String locale);
}
