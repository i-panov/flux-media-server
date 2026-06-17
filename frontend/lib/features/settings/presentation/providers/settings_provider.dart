import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flux_media_server/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:flux_media_server/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';

part 'settings_provider.freezed.dart';

@freezed
class SettingsState with _$SettingsState {
  const factory SettingsState({
    required AppSettings settings,
  }) = _SettingsState;
}

final settingsLocalDataSourceProvider = FutureProvider<SettingsLocalDataSource>(
  (ref) async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsLocalDataSource(prefs);
  },
);

final settingsRepositoryProvider = FutureProvider<SettingsRepositoryImpl>(
  (ref) async {
    final ds = await ref.watch(settingsLocalDataSourceProvider.future);
    return SettingsRepositoryImpl(ds);
  },
);

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._repository)
      : super(
          const SettingsState(settings: AppSettings()),
        );

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
  final notifier = SettingsNotifier(
    ref.watch(settingsRepositoryProvider).requireValue,
  );
  notifier.init();
  return notifier;
});
