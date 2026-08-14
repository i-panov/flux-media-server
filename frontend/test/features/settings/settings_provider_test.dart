import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/settings_local_datasource.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Mock the secure storage platform channel with in-memory storage.
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final mockStorage = <String, String>{};
  final writeCalls = <String>[];
  var throwOnRefreshToken = false;
  var throwOnAllKeys = false;

  const keyPrefix = kDebugMode ? 'debug_' : 'release_';

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      final args = methodCall.arguments as Map<dynamic, dynamic>;
      final key = args['key'] as String;
      if ((throwOnAllKeys || throwOnRefreshToken) &&
          (throwOnAllKeys || key.contains('refresh_token'))) {
        throw PlatformException(code: 'not_available');
      }
      switch (methodCall.method) {
        case 'read':
          return mockStorage[key];
        case 'write':
          mockStorage[key] = args['value'] as String;
          writeCalls.add(key);
          return null;
        case 'delete':
          mockStorage.remove(key);
          return null;
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  setUp(() {
    mockStorage.clear();
    writeCalls.clear();
    throwOnRefreshToken = false;
    throwOnAllKeys = false;
  });

  group('SettingsLocalDataSource', () {
    late SettingsLocalDataSource dataSource;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      dataSource = SettingsLocalDataSource(prefs, const FlutterSecureStorage());
    });

    test('getServerUrl returns null when empty', () {
      expect(dataSource.getServerUrl(), isNull);
    });

    test('setServerUrl persists value', () async {
      await dataSource.setServerUrl('http://localhost:8080');
      expect(dataSource.getServerUrl(), 'http://localhost:8080/api');
    });

    test('getAuthToken returns null when empty', () async {
      final token = await dataSource.getAuthToken();
      expect(token, isNull);
    });

    test('setAuthToken and getAuthToken roundtrip', () async {
      await dataSource.setAuthToken('token-1');
      expect(await dataSource.getAuthToken(), 'token-1');
      expect(mockStorage['${keyPrefix}auth_token'], 'token-1');
    });

    test('clearAuthToken removes the token', () async {
      await dataSource.setAuthToken('token-1');
      await dataSource.clearAuthToken();
      expect(await dataSource.getAuthToken(), isNull);
      expect(mockStorage.containsKey('${keyPrefix}auth_token'), isFalse);
    });

    test('refresh token roundtrip', () async {
      await dataSource.setRefreshToken('refresh-1');
      expect(await dataSource.getRefreshToken(), 'refresh-1');
      expect(mockStorage['${keyPrefix}refresh_token'], 'refresh-1');
    });

    test('clearRefreshToken removes the token', () async {
      await dataSource.setRefreshToken('refresh-1');
      await dataSource.clearRefreshToken();
      expect(await dataSource.getRefreshToken(), isNull);
      expect(mockStorage.containsKey('${keyPrefix}refresh_token'), isFalse);
    });

    test('locale defaults to en and persists', () async {
      expect(dataSource.getLocale(), 'en');
      await dataSource.setLocale('ru');
      expect(dataSource.getLocale(), 'ru');
      expect(prefs.getString('${keyPrefix}locale'), 'ru');
    });
  });

  group('SettingsLocalDataSource fallback', () {
    late SettingsLocalDataSource dataSource;
    late SharedPreferences prefs;

    setUp(() async {
      throwOnRefreshToken = true;
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      dataSource = SettingsLocalDataSource(prefs, const FlutterSecureStorage());
    });

    test('setRefreshToken falls back to insecure prefs', () async {
      await dataSource.setRefreshToken('refresh-fallback');
      expect(
        prefs.getString('${keyPrefix}refresh_token_insecure'),
        'refresh-fallback',
      );
    });

    test('getRefreshToken reads from insecure prefs', () async {
      await prefs.setString('${keyPrefix}refresh_token_insecure', 'stored');
      expect(await dataSource.getRefreshToken(), 'stored');
    });

    test('clearRefreshToken removes the insecure fallback', () async {
      await prefs.setString('${keyPrefix}refresh_token_insecure', 'stored');
      await dataSource.clearRefreshToken();
      expect(
        prefs.getString('${keyPrefix}refresh_token_insecure'),
        isNull,
      );
    });

    test('auth token uses its own fallback key', () async {
      throwOnAllKeys = true;
      await dataSource.setAuthToken('token-fallback');
      expect(
        prefs.getString('${keyPrefix}auth_token_insecure'),
        'token-fallback',
      );
    });
  });

  group('SettingsRepositoryImpl', () {
    late SettingsRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repository = SettingsRepositoryImpl(
        SettingsLocalDataSource(prefs, const FlutterSecureStorage()),
      );
    });

    test('getSettings returns defaults when empty', () async {
      final settings = await repository.getSettings();
      expect(settings.serverUrl, isNull);
      expect(settings.authToken, isNull);
      expect(settings.refreshToken, isNull);
      expect(settings.locale, 'en');
    });

    test('setServerUrl persists and returns value', () async {
      await repository.setServerUrl('http://localhost:8080');
      final settings = await repository.getSettings();
      expect(settings.serverUrl, 'http://localhost:8080/api');
    });

    test('setAuthToken and clearAuthToken work', () async {
      await repository.setAuthToken('test-token');
      final settingsBefore = await repository.getSettings();
      expect(settingsBefore.authToken, 'test-token');

      await repository.clearAuthToken();
      final settingsAfter = await repository.getSettings();
      expect(settingsAfter.authToken, isNull);
    });

    test('refresh token set/get/clear through repository', () async {
      await repository.setRefreshToken('refresh-1');
      expect((await repository.getSettings()).refreshToken, 'refresh-1');

      await repository.clearRefreshToken();
      expect((await repository.getSettings()).refreshToken, isNull);
    });

    test('locale persists through repository', () async {
      expect(repository.getLocale(), 'en');
      await repository.setLocale('ru');
      expect(repository.getLocale(), 'ru');
    });
  });

  group('SettingsNotifier', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('init loads persisted settings', () async {
      await container
          .read(settingsProvider.notifier)
          .setServerUrl('http://host:9000');
      await container.read(settingsProvider.notifier).setTokens('a', 'r');

      final fresh = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(fresh.dispose);
      await fresh.read(settingsProvider.notifier).init();

      final settings = fresh.read(settingsProvider).settings;
      expect(settings.serverUrl, 'http://host:9000/api');
      expect(settings.authToken, 'a');
      expect(settings.refreshToken, 'r');
    });

    test('setTokens persists both tokens', () async {
      await container.read(settingsProvider.notifier).setTokens('at', 'rt');

      expect(mockStorage['${keyPrefix}auth_token'], 'at');
      expect(mockStorage['${keyPrefix}refresh_token'], 'rt');
      final settings = container.read(settingsProvider).settings;
      expect(settings.authToken, 'at');
      expect(settings.refreshToken, 'rt');
    });

    test('logout clears both tokens', () async {
      await container.read(settingsProvider.notifier).setTokens('at', 'rt');
      await container.read(settingsProvider.notifier).logout();

      expect(mockStorage.containsKey('${keyPrefix}auth_token'), isFalse);
      expect(mockStorage.containsKey('${keyPrefix}refresh_token'), isFalse);
      final settings = container.read(settingsProvider).settings;
      expect(settings.authToken, isNull);
      expect(settings.refreshToken, isNull);
    });

    test('setServerUrl normalizes the value', () async {
      await container
          .read(settingsProvider.notifier)
          .setServerUrl('http://host:8080');

      final settings = container.read(settingsProvider).settings;
      expect(settings.serverUrl, 'http://host:8080/api');
    });

    test('setLocale updates only locale (no extra token IO)', () async {
      await container.read(settingsProvider.notifier).setTokens('at', 'rt');
      final writesBefore = writeCalls.length;

      await container.read(settingsProvider.notifier).setLocale('ru');

      expect(writeCalls.length, writesBefore);
      expect(mockStorage['${keyPrefix}auth_token'], 'at');
      expect(mockStorage['${keyPrefix}refresh_token'], 'rt');
      final settings = container.read(settingsProvider).settings;
      expect(settings.locale, 'ru');
      expect(settings.authToken, 'at');
      expect(settings.serverUrl, isNull);
    });
  });
}
