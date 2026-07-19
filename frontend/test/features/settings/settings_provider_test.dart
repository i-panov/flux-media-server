import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flux_media_server/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:flux_media_server/features/settings/data/repositories/settings_repository_impl.dart';

void main() {
  // Mock the secure storage platform channel with in-memory storage
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final mockStorage = <String, String>{};

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      final args = methodCall.arguments as Map<dynamic, dynamic>;
      switch (methodCall.method) {
        case 'read':
          return mockStorage[args['key'] as String];
        case 'write':
          mockStorage[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          mockStorage.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    mockStorage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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
      expect(dataSource.getServerUrl(), 'http://localhost:8080');
    });

    test('getAuthToken returns null when empty', () async {
      final token = await dataSource.getAuthToken();
      expect(token, isNull);
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
    });

    test('setServerUrl persists and returns value', () async {
      await repository.setServerUrl('http://localhost:8080');
      final settings = await repository.getSettings();
      expect(settings.serverUrl, 'http://localhost:8080');
    });

    test('setAuthToken and clearAuthToken work', () async {
      await repository.setAuthToken('test-token');
      final settingsBefore = await repository.getSettings();
      expect(settingsBefore.authToken, 'test-token');

      await repository.clearAuthToken();
      final settingsAfter = await repository.getSettings();
      expect(settingsAfter.authToken, isNull);
    });
  });
}
