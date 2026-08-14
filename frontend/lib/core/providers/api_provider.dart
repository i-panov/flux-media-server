import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/auth_api_client.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/network/interceptors/auth_interceptor.dart';
import 'package:flux_media_server/core/network/interceptors/safe_logging_interceptor.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:flux_media_server/core/network/library_api_client.dart';
import 'package:flux_media_server/core/network/media_api_client.dart';
import 'package:flux_media_server/core/session/settings_provider.dart';
import 'package:flux_media_server/core/utils/url_utils.dart';

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(ref);
});

final tokenRefreshInterceptorProvider =
    Provider<TokenRefreshInterceptor>((ref) {
  return TokenRefreshInterceptor(ref);
});

/// Единый refresher токенов: параллельные 401-запросы ждут один refresh.
///
/// Выполняет POST /auth/refresh через Chopper-клиент и сохраняет токены;
/// при неудаче очищает токены (logout на уровне сессии).
final authTokenRefresherProvider = Provider<AuthTokenRefresher>((ref) {
  return AuthTokenRefresher(
    performRefresh: (refreshToken) async {
      final response = await ref
          .read(authApiClientProvider)
          .refreshToken({'refresh_token': refreshToken});
      if (response.statusCode != 200 || response.body == null) return null;
      final body = response.body!;
      final tokens = (
        token: body['token'] as String,
        refreshToken: body['refresh_token'] as String,
      );
      await ref
          .read(settingsProvider.notifier)
          .setTokens(tokens.token, tokens.refreshToken);
      return tokens;
    },
    onRefreshFailure: () => ref.read(settingsProvider.notifier).logout(),
  );
});

/// BaseUrl API. Хранится в настройках уже нормализованным (включает
/// сегмент `/api`), здесь никакой магии с путями нет.
/// Нормализация применяется и здесь: у ранее сохранённых адресов
/// (записанных до рефакторинга) сегмента `/api` может не быть,
/// и без него запросы уходили бы мимо API (404).
/// Меняется только при реальной смене serverUrl.
final baseUrlProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsProvider);
  return normalizeServerUrl(
    settings.settings.serverUrl ?? defaultServerAddress,
  );
});

/// Chopper-сервис аутентификации. Пересоздаётся при смене baseUrl,
/// закрывает свой HttpClient через onDispose.
final authApiClientProvider = Provider<AuthApiClient>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authInterceptor = ref.watch(authInterceptorProvider);
  final tokenRefreshInterceptor = ref.watch(tokenRefreshInterceptorProvider);
  final bundle = AuthApiClient.create(
    baseUrl: baseUrl,
    authInterceptor: authInterceptor,
    tokenRefreshInterceptor: tokenRefreshInterceptor,
  );
  ref.onDispose(bundle.httpClient.close);
  return bundle.apiClient;
});

/// Chopper-сервис медиа. Пересоздаётся при смене baseUrl,
/// закрывает свой HttpClient через onDispose.
final mediaApiClientProvider = Provider<MediaApiClient>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authInterceptor = ref.watch(authInterceptorProvider);
  final tokenRefreshInterceptor = ref.watch(tokenRefreshInterceptorProvider);
  final bundle = MediaApiClient.create(
    baseUrl: baseUrl,
    interceptors: [
      authInterceptor,
      tokenRefreshInterceptor,
      SafeLoggingInterceptor(),
    ],
  );
  ref.onDispose(bundle.httpClient.close);
  return bundle.apiClient;
});

/// Chopper-сервис библиотеки (избранное, артисты, коллекции).
/// Пересоздаётся при смене baseUrl, закрывает свой HttpClient
/// через onDispose.
final libraryApiClientProvider = Provider<LibraryApiClient>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authInterceptor = ref.watch(authInterceptorProvider);
  final tokenRefreshInterceptor = ref.watch(tokenRefreshInterceptorProvider);
  final bundle = LibraryApiClient.create(
    baseUrl: baseUrl,
    interceptors: [
      authInterceptor,
      tokenRefreshInterceptor,
      SafeLoggingInterceptor(),
    ],
  );
  ref.onDispose(bundle.httpClient.close);
  return bundle.apiClient;
});
