import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_local_datasource.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';
import 'package:flux_media_server/core/session/settings_repository_impl.dart';
import 'package:flux_media_server/core/utils/logger.dart';
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

final settingsLocalDataSourceProvider = Provider<SettingsLocalDataSource>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsLocalDataSource(prefs, _secureStorage);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final ds = ref.watch(settingsLocalDataSourceProvider);
  return SettingsRepositoryImpl(ds);
});

@freezed
sealed class SettingsState with _$SettingsState {
  const factory({required AppSettings settings}) = _SettingsState;
}

class SettingsNotifier extends Notifier<SettingsState> {
  // Не final: build() перезапускается при смене зависимости —
  // повторное присваивание late final дало бы LateInitializationError.
  late SettingsRepository _repository;

  @override
  SettingsState build() {
    _repository = ref.watch(settingsRepositoryProvider);
    return const SettingsState(settings: AppSettings());
  }

  /// Поколение асинхронных init: setServerUrl посреди стартовой
  /// загрузки не должен затираться её устаревшим результатом.
  int _generation = 0;

  /// Loads settings from the repository. Called at app startup.
  Future<void> init() async {
    final generation = ++_generation;
    var settings = await _repository.getSettings();
    if (generation != _generation) return;
    // Миграция: раньше хранился полный baseUrl с хвостовым `/api` —
    // срезаем ОДИН раз по флагу (без флага реверс-прокси вида
    // https://ex.com/api резался бы при каждом старте, и UI показывал
    // бы не то, что вводили). Ошибка записи флага/адреса не должна
    // ронять старт приложения (main без try) — логируем и едем дальше
    // со значением как есть.
    if (!_repository.isServerUrlMigrationDone()) {
      try {
        final stored = settings.serverUrl;
        if (stored != null) {
          final stripped = stripApiSuffix(stored);
          if (stripped != stored) {
            // Пока считали/писали, мог прийти ручной setServerUrl:
            // его значение новее, поверх не пишем (флаг всё равно
            // взводим ниже — миграция одноразовая).
            if (generation != _generation) return;
            await _repository.setServerUrl(stripped);
            settings = settings.copyWith(serverUrl: stripped);
          }
        }
        await _repository.setServerUrlMigrationDone();
      } catch (e) {
        AppLogger.error('Server URL migration failed', e);
      }
    }
    if (generation != _generation) return;
    state = SettingsState(settings: settings);
  }

  Future<void> setServerUrl(String url) async {
    // Храним введённый адрес как есть (лёгкая нормализация без /api) —
    // сегмент API подставляет normalizeServerUrl динамически.
    // Поколение как в init: ручное сохранение посреди чужого await
    // не должно перемежаться с миграцией.
    final generation = ++_generation;
    final normalized = normalizeServerAddress(url);
    await _repository.setServerUrl(normalized);
    if (generation != _generation) return;
    state = SettingsState(
      settings: state.settings.copyWith(serverUrl: normalized),
    );
  }

  Future<void> setTokens(String accessToken, String refreshToken) async {
    final previousAuth = state.settings.authToken;
    await _repository.setAuthToken(accessToken);
    try {
      await _repository.setRefreshToken(refreshToken);
    } catch (_) {
      // Роллбек: refresh-токен не сохранился — откатываем access,
      // чтобы пара токенов не «разъехалась» (атомарность записи).
      try {
        if (previousAuth != null) {
          await _repository.setAuthToken(previousAuth);
        } else {
          await _repository.clearAuthToken();
        }
      } catch (_) {
        // Роллбек тоже упал — исходная ошибка важнее.
      }
      rethrow;
    }
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
      settings: state.settings.copyWith(authToken: null, refreshToken: null),
    );
  }

  Future<void> setLocale(String locale) async {
    await _repository.setLocale(locale);
    state = SettingsState(settings: state.settings.copyWith(locale: locale));
  }

  /// Доверие самоподписанным сертификатам. Сохраняется ДО смены адреса
  /// сервера: общий HTTP-клиент пересоздаётся при смене serverUrl, и
  /// флаг обязан быть уже в настройках к этому моменту.
  Future<void> setTrustSelfSignedCertificates({required bool value}) async {
    await _repository.setTrustSelfSignedCertificates(value: value);
    state = SettingsState(
      settings: state.settings.copyWith(trustSelfSignedCertificates: value),
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
