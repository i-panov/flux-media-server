import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flux_media_server/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:flux_media_server/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';

void main() {
  group('SettingsRepositoryImpl', () {
    late SettingsRepositoryImpl repository;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repository = SettingsRepositoryImpl(SettingsLocalDataSource(prefs));
    });

    test('getSettings returns defaults when empty', () {
      final settings = repository.getSettings();
      expect(settings.serverUrl, isNull);
      expect(settings.authToken, isNull);
    });

    test('setServerUrl persists and returns value', () async {
      await repository.setServerUrl('http://localhost:8080');
      final settings = repository.getSettings();
      expect(settings.serverUrl, 'http://localhost:8080');
    });

    test('clearAuthToken removes token', () async {
      await prefs.setString('auth_token', 'test-token');
      expect(repository.getSettings().authToken, 'test-token');

      await repository.clearAuthToken();
      expect(repository.getSettings().authToken, isNull);
    });
  });

  group('SettingsNotifier', () {
    late SettingsNotifier notifier;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final repo =
          SettingsRepositoryImpl(SettingsLocalDataSource(prefs));
      notifier = SettingsNotifier(repo);
    });

    tearDown(() => notifier.dispose());

    test('init loads current settings', () {
      notifier.init();
      expect(notifier.state.settings.serverUrl, isNull);
    });

    test('setServerUrl updates state', () async {
      notifier.init();
      await notifier.setServerUrl('http://example.com');
      expect(notifier.state.settings.serverUrl, 'http://example.com');
    });

    test('logout clears auth token', () async {
      await prefs.setString('auth_token', 'token');
      notifier.init();

      await notifier.logout();
      expect(notifier.state.settings.authToken, isNull);
    });
  });
}
