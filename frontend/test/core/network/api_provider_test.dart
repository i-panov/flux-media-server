import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this.settings);

  final AppSettings settings;

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<void> setServerUrl(String url) async {}

  @override
  Future<void> setAuthToken(String token) async {}

  @override
  Future<void> clearAuthToken() async {}

  @override
  Future<void> setRefreshToken(String token) async {}

  @override
  Future<void> clearRefreshToken() async {}

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
  });
}
