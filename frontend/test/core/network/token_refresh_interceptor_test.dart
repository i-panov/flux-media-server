import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:flux_media_server/features/settings/domain/entities/app_settings.dart';
import 'package:flux_media_server/features/settings/domain/repositories/settings_repository.dart';
import 'package:flux_media_server/features/settings/presentation/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Exposes Ref for testing.
final _refProvider = Provider<Ref>((ref) => ref);

/// Fake HTTP client that returns canned responses for /auth/refresh.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._refreshResponse);

  final http.Response Function() _refreshResponse;
  int callCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    final response = _refreshResponse();
    return http.StreamedResponse(
      http.ByteStream.fromBytes(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

/// Fake settings repository that stores tokens in memory.
class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings = const AppSettings(
    serverUrl: 'http://localhost:8080',
    authToken: 'old-token',
    refreshToken: 'old-refresh',
  );

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<void> setServerUrl(String url) async {
    _settings = _settings.copyWith(serverUrl: url);
  }

  @override
  Future<void> setAuthToken(String token) async {
    _settings = _settings.copyWith(authToken: token);
  }

  @override
  Future<void> setRefreshToken(String token) async {
    _settings = _settings.copyWith(refreshToken: token);
  }

  @override
  Future<void> clearAuthToken() async {
    _settings = _settings.copyWith(authToken: null);
  }

  @override
  Future<void> clearRefreshToken() async {
    _settings = _settings.copyWith(refreshToken: null);
  }

  @override
  Future<void> setLocale(String locale) async {
    _settings = _settings.copyWith(locale: locale);
  }

  @override
  String getLocale() => _settings.locale;
}

void main() {
  group('TokenRefreshInterceptor', () {
    late _FakeSettingsRepository fakeRepo;
    late _FakeHttpClient fakeClient;
    late ProviderContainer container;
    late Ref ref;

    setUp(() async {
      fakeRepo = _FakeSettingsRepository();
      fakeClient = _FakeHttpClient(
        () => http.Response(
          jsonEncode({'token': 'new-token', 'refresh_token': 'new-refresh'}),
          200,
        ),
      );
      container = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(fakeRepo),
      ]);
      ref = container.read(_refProvider);
      // Load settings so tokens are available.
      await container.read(settingsProvider.notifier).init();
    });

    tearDown(() {
      container.dispose();
    });

    test('refreshes token on 401 and throws TokenRefreshedException', () async {
      final interceptor = TokenRefreshInterceptor(
        ref,
        httpClient: fakeClient,
      );

      // Build a fake 401 response.
      final response = Response<String>(http.Response('unauthorized', 401), 'unauthorized');

      expect(
        () => interceptor.onResponse(response),
        throwsA(isA<TokenRefreshedException>()),
      );

      // Wait for the async refresh to complete.
      await Future<void>.delayed(Duration.zero);

      expect(fakeClient.callCount, 1);
      // Tokens should be updated.
      final settings = await fakeRepo.getSettings();
      expect(settings.authToken, 'new-token');
      expect(settings.refreshToken, 'new-refresh');
    });

    test('clears tokens when refresh fails (401 from refresh endpoint)',
        () async {
      fakeClient = _FakeHttpClient(
        () => http.Response('{"error": "invalid token"}', 401),
      );

      final interceptor = TokenRefreshInterceptor(
        ref,
        httpClient: fakeClient,
      );

      final response = Response<String>(http.Response('unauthorized', 401), 'unauthorized');
      final result = await interceptor.onResponse(response);

      // Should return the 401 response (not throw).
      expect(result.statusCode, 401);
      // Tokens should be cleared.
      final settings = await fakeRepo.getSettings();
      expect(settings.authToken, isNull);
      expect(settings.refreshToken, isNull);
    });

    test('passes through non-401 responses', () async {
      final interceptor = TokenRefreshInterceptor(
        ref,
        httpClient: fakeClient,
      );

      final response = Response<String>(http.Response('ok', 200), 'ok');
      final result = await interceptor.onResponse(response);

      expect(result.statusCode, 200);
      expect(fakeClient.callCount, 0);
    });

    test('returns 401 when no refresh token stored', () async {
      await fakeRepo.clearRefreshToken();
      // Reload settings into the notifier.
      await container.read(settingsProvider.notifier).init();

      final interceptor = TokenRefreshInterceptor(
        ref,
        httpClient: fakeClient,
      );

      final response = Response<String>(http.Response('unauthorized', 401), 'unauthorized');
      final result = await interceptor.onResponse(response);

      expect(result.statusCode, 401);
      expect(fakeClient.callCount, 0);
    });
  });
}
