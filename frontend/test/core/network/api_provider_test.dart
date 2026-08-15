import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this.settings);

  AppSettings settings;

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<void> setServerUrl(String url) async {
    settings = settings.copyWith(serverUrl: url);
  }

  @override
  Future<void> setAuthToken(String token) async {
    settings = settings.copyWith(authToken: token);
  }

  @override
  Future<void> clearAuthToken() async {
    settings = settings.copyWith(authToken: null);
  }

  @override
  Future<void> setRefreshToken(String token) async {
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
  group('baseUrlProvider', () {
    test('appends missing /api to legacy saved serverUrl', () async {
      // Имитация значения, сохранённого до рефакторинга: без сегмента
      // `/api`. Раньше api_provider добавлял его магией, теперь это
      // делает baseUrlProvider — иначе запросы уходили бы на 404.
      final notifier = SettingsNotifier(
        _FakeSettingsRepository(
          const AppSettings(serverUrl: 'http://192.168.1.5:8080'),
        ),
      );
      await notifier.init();

      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => notifier),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(baseUrlProvider), 'http://192.168.1.5:8080/api');
    });

    test('keeps normalized serverUrl unchanged', () async {
      final notifier = SettingsNotifier(
        _FakeSettingsRepository(
          const AppSettings(serverUrl: 'http://192.168.1.5:8080/api'),
        ),
      );
      await notifier.init();

      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => notifier),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(baseUrlProvider), 'http://192.168.1.5:8080/api');
    });

    test('normalizes default address when serverUrl is null', () {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(
              _FakeSettingsRepository(const AppSettings()),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(baseUrlProvider), 'http://localhost:8080/api');
    });

    test('does not change when tokens change (no client recreation)', () async {
      final notifier = SettingsNotifier(
        _FakeSettingsRepository(
          const AppSettings(serverUrl: 'http://host:8080/api'),
        ),
      );
      await notifier.init();

      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => notifier),
        ],
      );
      addTearDown(container.dispose);

      final client1 = container.read(authApiClientProvider);

      // setTokens/logout меняют настройки, но не serverUrl —
      // клиенты пересоздаваться не должны.
      await notifier.setTokens('access-1', 'refresh-1');
      expect(
        identical(container.read(authApiClientProvider), client1),
        isTrue,
      );

      await notifier.logout();
      expect(
        identical(container.read(authApiClientProvider), client1),
        isTrue,
      );
    });

    test('recreates clients when serverUrl changes', () async {
      final notifier = SettingsNotifier(
        _FakeSettingsRepository(
          const AppSettings(serverUrl: 'http://host:8080/api'),
        ),
      );
      await notifier.init();

      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => notifier),
        ],
      );
      addTearDown(container.dispose);

      final client1 = container.read(authApiClientProvider);

      await notifier.setServerUrl('http://other:9000/api');
      final client2 = container.read(authApiClientProvider);

      expect(identical(client1, client2), isFalse);
      expect(container.read(baseUrlProvider), 'http://other:9000/api');
    });
  });

  group('parseRefreshTokens', () {
    test('parses a valid refresh response', () {
      final tokens = parseRefreshTokens({
        'token': 'access-1',
        'refresh_token': 'refresh-1',
      });
      expect(tokens, isNotNull);
      expect(tokens!.token, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
    });

    test('returns null instead of crashing on non-string token', () {
      expect(parseRefreshTokens({'token': 42, 'refresh_token': 'r'}), isNull);
      expect(parseRefreshTokens({'token': null, 'refresh_token': 'r'}), isNull);
      expect(parseRefreshTokens({'token': 't', 'refresh_token': 42}), isNull);
    });

    test('returns null for non-map body', () {
      expect(parseRefreshTokens('plain text'), isNull);
      expect(parseRefreshTokens(null), isNull);
      expect(parseRefreshTokens(<String, dynamic>{}), isNull);
    });

    test('returns null for empty tokens', () {
      expect(parseRefreshTokens({'token': '', 'refresh_token': 'r'}), isNull);
      expect(parseRefreshTokens({'token': 't', 'refresh_token': ''}), isNull);
    });
  });
}
