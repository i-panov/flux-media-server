import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flux_media_server/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:flux_media_server/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';

part 'settings_provider.freezed.dart';

/// Provider for SharedPreferences instance.
/// Overridden in main() with pre-initialized instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

final settingsLocalDataSourceProvider = Provider<SettingsLocalDataSource>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsLocalDataSource(prefs);
});

final settingsRepositoryProvider = Provider<SettingsRepositoryImpl>((ref) {
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

  final SettingsRepositoryImpl _repository;

  void init() {
    final settings = _repository.getSettings();
    state = SettingsState(settings: settings);
  }

  Future<void> setServerUrl(String url) async {
    await _repository.setServerUrl(url);
    final settings = _repository.getSettings();
    state = SettingsState(settings: settings);
  }

  Future<void> logout() async {
    await _repository.clearAuthToken();
    final settings = _repository.getSettings();
    state = SettingsState(settings: settings);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final notifier = SettingsNotifier(ref.watch(settingsRepositoryProvider));
  notifier.init();
  return notifier;
});
