import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/session/settings_local_datasource.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final mockStorage = <String, String>{};
  var throwOnAllKeys = false;

  const keyPrefix = kDebugMode ? 'debug_' : 'release_';

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      final args = methodCall.arguments as Map<dynamic, dynamic>;
      final key = args['key'] as String;
      if (throwOnAllKeys) {
        throw PlatformException(code: 'not_available');
      }
      switch (methodCall.method) {
        case 'read':
          return mockStorage[key];
        case 'write':
          mockStorage[key] = args['value'] as String;
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
    throwOnAllKeys = false;
  });

  group('fallback cleanup', () {
    late SettingsLocalDataSource dataSource;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      dataSource = SettingsLocalDataSource(prefs, const FlutterSecureStorage());
    });

    test('clearAuthToken removes insecure fallback even when secure delete '
        'succeeds', () async {
      await prefs.setString('${keyPrefix}auth_token_insecure', 'stale');
      mockStorage['${keyPrefix}auth_token'] = 'stale';

      await dataSource.clearAuthToken();

      // Secure delete прошёл успешно, но plaintext-фолбэк обязан
      // быть удалён безусловно.
      expect(prefs.getString('${keyPrefix}auth_token_insecure'), isNull);
      expect(mockStorage.containsKey('${keyPrefix}auth_token'), isFalse);
    });

    test('clearRefreshToken removes insecure fallback even when secure delete '
        'succeeds', () async {
      await prefs.setString('${keyPrefix}refresh_token_insecure', 'stale');
      mockStorage['${keyPrefix}refresh_token'] = 'stale';

      await dataSource.clearRefreshToken();

      expect(prefs.getString('${keyPrefix}refresh_token_insecure'), isNull);
      expect(mockStorage.containsKey('${keyPrefix}refresh_token'), isFalse);
    });

    test('clearAuthToken removes both secure and fallback when secure delete '
        'fails (debug fallback)', () async {
      throwOnAllKeys = true;
      await prefs.setString('${keyPrefix}auth_token_insecure', 'stale');

      await dataSource.clearAuthToken();

      expect(prefs.getString('${keyPrefix}auth_token_insecure'), isNull);
    });
  });

  group('release mode (no insecure fallback)', () {
    late SettingsLocalDataSource dataSource;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      dataSource = SettingsLocalDataSource(
        prefs,
        const FlutterSecureStorage(),
        allowInsecureFallback: false,
      );
    });

    test('setAuthToken rethrows instead of writing plaintext fallback',
        () async {
      throwOnAllKeys = true;

      await expectLater(
        dataSource.setAuthToken('secret'),
        throwsA(isA<PlatformException>()),
      );
      expect(prefs.getString('${keyPrefix}auth_token_insecure'), isNull);
    });

    test('getAuthToken rethrows instead of reading fallback', () async {
      throwOnAllKeys = true;
      await prefs.setString('${keyPrefix}auth_token_insecure', 'stale');

      await expectLater(
        dataSource.getAuthToken(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('clearAuthToken rethrows on secure delete failure', () async {
      throwOnAllKeys = true;

      await expectLater(
        dataSource.clearAuthToken(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('setRefreshToken rethrows instead of writing plaintext fallback',
        () async {
      throwOnAllKeys = true;

      await expectLater(
        dataSource.setRefreshToken('secret'),
        throwsA(isA<PlatformException>()),
      );
      expect(prefs.getString('${keyPrefix}refresh_token_insecure'), isNull);
    });

    test('getRefreshToken rethrows instead of reading fallback', () async {
      throwOnAllKeys = true;
      await prefs.setString('${keyPrefix}refresh_token_insecure', 'stale');

      await expectLater(
        dataSource.getRefreshToken(),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
