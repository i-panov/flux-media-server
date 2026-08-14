import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:flux_media_server/core/providers/api_provider.dart';
import 'package:flux_media_server/core/session/app_settings.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/session/settings_repository.dart';
import 'package:http/http.dart' as http;

/// Exposes Ref for testing.
final _refProvider = Provider<Ref>((ref) => ref);

/// Fake HTTP client that returns canned responses for /auth/refresh.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.response);

  http.Response Function() response;
  int callCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    final res = response();
    return http.StreamedResponse(
      http.ByteStream.fromBytes(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
    );
  }
}

/// Fake settings repository that stores tokens in memory.
class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings = const AppSettings(
    serverUrl: 'http://localhost:8080/api',
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

/// Реальный [AuthTokenRefresher] с фейковым HTTP-клиентом: повторяет
/// логику authTokenRefresherProvider (запрос + сохранение токенов +
/// очистка при неудаче), но без Chopper.
AuthTokenRefresher _buildRefresher(
  Ref ref,
  _FakeHttpClient fakeClient,
) {
  return AuthTokenRefresher(
    performRefresh: (refreshToken) async {
      final response = await fakeClient.post(
        Uri.parse('http://localhost:8080/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tokens = (
        token: data['token'] as String,
        refreshToken: data['refresh_token'] as String,
      );
      await ref
          .read(settingsProvider.notifier)
          .setTokens(tokens.token, tokens.refreshToken);
      return tokens;
    },
    onRefreshFailure: () async {
      await ref.read(settingsProvider.notifier).logout();
    },
  );
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
      container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(fakeRepo),
          authTokenRefresherProvider.overrideWith(
            (ref) => _buildRefresher(ref, fakeClient),
          ),
        ],
      );
      ref = container.read(_refProvider);
      // Load settings so tokens are available.
      await container.read(settingsProvider.notifier).init();
    });

    tearDown(() {
      container.dispose();
    });

    test('refreshes token on 401 and throws TokenRefreshedException',
        () async {
      final interceptor = TokenRefreshInterceptor(ref);

      // Build a fake 401 response.
      final response =
          Response<String>(http.Response('unauthorized', 401), 'unauthorized');

      await expectLater(
        () => interceptor.onResponse(response),
        throwsA(isA<TokenRefreshedException>()),
      );

      expect(fakeClient.callCount, 1);
      // Tokens should be updated.
      final settings = await fakeRepo.getSettings();
      expect(settings.authToken, 'new-token');
      expect(settings.refreshToken, 'new-refresh');
    });

    test('clears tokens when refresh fails (401 from refresh endpoint)',
        () async {
      fakeClient.response = () => http.Response(
            '{"error": "invalid token"}',
            401,
          );

      final interceptor = TokenRefreshInterceptor(ref);

      final response =
          Response<String>(http.Response('unauthorized', 401), 'unauthorized');
      final result = await interceptor.onResponse(response);

      // Should return the 401 response (not throw).
      expect(result.statusCode, 401);
      // Tokens should be cleared.
      final settings = await fakeRepo.getSettings();
      expect(settings.authToken, isNull);
      expect(settings.refreshToken, isNull);
    });

    test('passes through non-401 responses', () async {
      final interceptor = TokenRefreshInterceptor(ref);

      final response = Response<String>(http.Response('ok', 200), 'ok');
      final result = await interceptor.onResponse(response);

      expect(result.statusCode, 200);
      expect(fakeClient.callCount, 0);
    });

    test('returns 401 when no refresh token stored', () async {
      await fakeRepo.clearRefreshToken();
      // Reload settings into the notifier.
      await container.read(settingsProvider.notifier).init();

      final interceptor = TokenRefreshInterceptor(ref);

      final response =
          Response<String>(http.Response('unauthorized', 401), 'unauthorized');
      final result = await interceptor.onResponse(response);

      expect(result.statusCode, 401);
      expect(fakeClient.callCount, 0);
    });

    test('parallel 401s wait for a single refresh', () async {
      final interceptor = TokenRefreshInterceptor(ref);

      Future<void> hit() async {
        final response = Response<String>(
          http.Response('unauthorized', 401),
          'unauthorized',
        );
        try {
          await interceptor.onResponse(response);
        } on TokenRefreshedException {
          // Ожидаемое исключение.
        }
      }

      await Future.wait([hit(), hit(), hit()]);

      // Все три параллельных 401 должны дождаться одного refresh.
      expect(fakeClient.callCount, 1);
    });
  });
}
