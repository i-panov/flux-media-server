import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_local_datasource.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';
import 'package:flux_media_server/core/session/settings_repository_impl.dart';
import 'package:flux_media_server/core/utils/url_utils.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_provider.freezed.dart';

/// Provider for SharedPreferences instance.
/// Overridden in main() with pre-initialized instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

const _secureStorage = FlutterSecureStorage();

final settingsLocalDataSourceProvider =
    Provider<SettingsLocalDataSource>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsLocalDataSource(prefs, _secureStorage);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final ds = ref.watch(settingsLocalDataSourceProvider);
  return SettingsRepositoryImpl(ds);
});

@freezed
class SettingsState with _$SettingsState {
  const factory SettingsState({
    required AppSettings settings,
  }) = _SettingsState;
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._repository)
      : super(const SettingsState(settings: AppSettings()));

  final SettingsRepository _repository;

  /// Loads settings from the repository. Called at app startup.
  Future<void> init() async {
    final settings = await _repository.getSettings();
    state = SettingsState(settings: settings);
  }

  Future<void> setServerUrl(String url) async {
    // Нормализуем один раз при сохранении — храним полный baseUrl API.
    final normalized = normalizeServerUrl(url);
    await _repository.setServerUrl(normalized);
    state = SettingsState(
      settings: state.settings.copyWith(serverUrl: normalized),
    );
  }

  Future<void> setAuthToken(String token) async {
    await _repository.setAuthToken(token);
    state = SettingsState(
      settings: state.settings.copyWith(authToken: token),
    );
  }

  Future<void> setRefreshToken(String token) async {
    await _repository.setRefreshToken(token);
    state = SettingsState(
      settings: state.settings.copyWith(refreshToken: token),
    );
  }

  Future<void> setTokens(String accessToken, String refreshToken) async {
    await _repository.setAuthToken(accessToken);
    await _repository.setRefreshToken(refreshToken);
    state = SettingsState(
      settings: state.settings.copyWith(
        authToken: accessToken,
        refreshToken: refreshToken,
      ),
    );
  }

  Future<void> logout() async {
    await _repository.clearAuthToken();
    await _repository.clearRefreshToken();
    state = SettingsState(
      settings: state.settings.copyWith(
        authToken: null,
        refreshToken: null,
      ),
    );
  }

  Future<void> setLocale(String locale) async {
    await _repository.setLocale(locale);
    state = SettingsState(
      settings: state.settings.copyWith(locale: locale),
    );
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.watch(settingsRepositoryProvider));
});
