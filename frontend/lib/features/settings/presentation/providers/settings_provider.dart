import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flux_media_server/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:flux_media_server/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';
import 'package:flux_media_server/features/settings/domain/repositories/settings_repository.dart';

part 'settings_provider.freezed.dart';

/// Provider for SharedPreferences instance.
/// Overridden in main() with pre-initialized instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

const _secureStorage = FlutterSecureStorage();

final settingsLocalDataSourceProvider = Provider<SettingsLocalDataSource>((ref) {
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

  Future<void> init() async {
    final settings = await _repository.getSettings();
    state = SettingsState(settings: settings);
  }

  Future<void> setServerUrl(String url) async {
    await _repository.setServerUrl(url);
    final settings = await _repository.getSettings();
    state = SettingsState(settings: settings);
  }

  Future<void> setAuthToken(String token) async {
    await _repository.setAuthToken(token);
    final settings = await _repository.getSettings();
    state = SettingsState(settings: settings);
  }

  Future<void> logout() async {
    await _repository.clearAuthToken();
    final settings = await _repository.getSettings();
    state = SettingsState(settings: settings);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final notifier = SettingsNotifier(ref.watch(settingsRepositoryProvider));
  notifier.init();
  return notifier;
});
