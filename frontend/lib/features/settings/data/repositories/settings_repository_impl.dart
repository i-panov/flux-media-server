import 'package:flux_media_server/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';
import 'package:flux_media_server/features/settings/domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._localDataSource);

  final SettingsLocalDataSource _localDataSource;

  @override
  Future<AppSettings> getSettings() async {
    final token = await _localDataSource.getAuthToken();
    return AppSettings(
      serverUrl: _localDataSource.getServerUrl(),
      authToken: token,
    );
  }

  @override
  Future<void> setServerUrl(String url) => _localDataSource.setServerUrl(url);

  @override
  Future<void> setAuthToken(String token) =>
      _localDataSource.setAuthToken(token);

  @override
  Future<void> clearAuthToken() => _localDataSource.clearAuthToken();
}
