import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';

/// Репозиторий, у которого можно включить отказ записи refresh-токена.
class _FlakySettingsRepository implements SettingsRepository {
  AppSettings settings = const AppSettings(
    serverUrl: 'http://host:8080/api',
    authToken: 'old-access',
    refreshToken: 'old-refresh',
  );

  bool failRefreshWrite = false;
  bool failAccessWrite = false;

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<void> setServerUrl(String url) async {
    settings = settings.copyWith(serverUrl: url);
  }

  @override
  Future<void> setAuthToken(String token) async {
    if (failAccessWrite) throw Exception('access write failed');
    settings = settings.copyWith(authToken: token);
  }

  @override
  Future<void> clearAuthToken() async {
    settings = settings.copyWith(authToken: null);
  }

  @override
  Future<void> setRefreshToken(String token) async {
    if (failRefreshWrite) throw Exception('refresh write failed');
    settings = settings.copyWith(refreshToken: token);
  }

  @override
  Future<void> clearRefreshToken() async {
    settings = settings.copyWith(refreshToken: null);
  }

  @override
  String getLocale() => 'en';

  @override
  Future<void> setLocale(String locale) async {}
}

void main() {
  group('SettingsNotifier.setTokens atomicity', () {
    late _FlakySettingsRepository repo;
    late SettingsNotifier notifier;
    late ProviderContainer container;

    setUp(() {
      repo = _FlakySettingsRepository();
      container = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
      ],);
      notifier = container.read(settingsProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('rolls back access token when refresh write fails', () async {
      await notifier.init();
      repo.failRefreshWrite = true;

      await expectLater(
        notifier.setTokens('new-access', 'new-refresh'),
        throwsException,
      );

      // Старая пара токенов восстановлена.
      final settings = repo.settings;
      expect(settings.authToken, 'old-access');
      expect(settings.refreshToken, 'old-refresh');
      expect(notifier.state.settings.authToken, 'old-access');
      expect(notifier.state.settings.refreshToken, 'old-refresh');
    });

    test('clears access token on rollback when there was none before',
        () async {
      repo.settings = const AppSettings(serverUrl: 'http://host:8080/api');
      await notifier.init();
      repo.failRefreshWrite = true;

      await expectLater(
        notifier.setTokens('new-access', 'new-refresh'),
        throwsException,
      );

      expect(repo.settings.authToken, isNull);
      expect(notifier.state.settings.authToken, isNull);
    });

    test('keeps both tokens when both writes succeed', () async {
      await notifier.init();

      await notifier.setTokens('new-access', 'new-refresh');

      expect(repo.settings.authToken, 'new-access');
      expect(repo.settings.refreshToken, 'new-refresh');
      expect(notifier.state.settings.authToken, 'new-access');
      expect(notifier.state.settings.refreshToken, 'new-refresh');
    });
  });
}
