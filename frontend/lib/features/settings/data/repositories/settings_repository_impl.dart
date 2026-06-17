import 'package:flux_media_server/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';

class SettingsRepositoryImpl {
  SettingsRepositoryImpl(this._localDataSource);

  final SettingsLocalDataSource _localDataSource;

  AppSettings getSettings() {
    return AppSettings(
      serverUrl: _localDataSource.getServerUrl(),
      authToken: _localDataSource.getAuthToken(),
    );
  }

  Future<void> setServerUrl(String url) => _localDataSource.setServerUrl(url);

  Future<void> clearAuthToken() => _localDataSource.clearAuthToken();
}
