import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';

/// Repository for application settings and authentication token storage.
abstract class SettingsRepository {
  /// Returns current app settings.
  Future<AppSettings> getSettings();

  /// Saves the server URL.
  Future<void> setServerUrl(String url);

  /// Saves the authentication token securely.
  Future<void> setAuthToken(String token);

  /// Clears the authentication token.
  Future<void> clearAuthToken();
}
