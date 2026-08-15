import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
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
/// Разбирает тело ответа `/auth/refresh`.
///
/// Возвращает токены или `null` при неожиданной форме ответа — вместо
/// TypeError-краша (приведение `as String` бросало Error, которое не
/// ловилось ни одним catch).
({String token, String refreshToken})? parseRefreshTokens(Object? body) {
  if (body is! Map<String, dynamic>) return null;
  final token = body['token'];
  final refreshToken = body['refresh_token'];
  if (token is! String || refreshToken is! String) return null;
  if (token.isEmpty || refreshToken.isEmpty) return null;
  return (token: token, refreshToken: refreshToken);
}

final authTokenRefresherProvider = Provider<AuthTokenRefresher>((ref) {
  return AuthTokenRefresher(
    performRefresh: (refreshToken) async {
      try {
        final response = await ref
            .read(authApiClientProvider)
            .refreshToken({'refresh_token': refreshToken});
        if (response.statusCode != 200) return null;
        final tokens = parseRefreshTokens(response.body);
        if (tokens == null) return null;
        await ref
            .read(settingsProvider.notifier)
            .setTokens(tokens.token, tokens.refreshToken);
        return tokens;
        // ignore: avoid_catching_errors
      } on Error {
        // Неожиданная форма ответа (TypeError и пр.) не должна
        // ронять приложение: считаем refresh неудачным.
        return null;
      }
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
  final serverUrl = ref.watch(
    settingsProvider.select((s) => s.settings.serverUrl),
  );
  return normalizeServerUrl(serverUrl ?? defaultServerAddress);
});

/// Общий низкоуровневый HTTP-клиент для всех Chopper-сервисов: один
/// connection-pool и один набор таймаутов вместо трёх изолированных.
/// Живёт столько же, сколько приложение; при смене baseUrl не закрывается.
final httpClientProvider = Provider<TimeoutHttpClient>((ref) {
  final client = TimeoutHttpClient();
  ref.onDispose(client.close);
  return client;
});

/// Единый [ChopperClient] со всеми API-сервисами. Пересоздаётся только
/// при смене baseUrl; HTTP-клиент при этом остаётся общим (см.
/// [httpClientProvider]), ChopperClient закрывает его не будет —
/// он ему не принадлежит.
final _apiChopperClientProvider = Provider<ChopperClient>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authInterceptor = ref.watch(authInterceptorProvider);
  final tokenRefreshInterceptor = ref.watch(tokenRefreshInterceptorProvider);
  return createChopperClient(
    baseUrl: baseUrl,
    services: const [],
    interceptors: [
      authInterceptor,
      tokenRefreshInterceptor,
      SafeLoggingInterceptor(),
    ],
    httpClient: ref.watch(httpClientProvider),
  ).client;
});

/// Chopper-сервис аутентификации на общем [ChopperClient].
final authApiClientProvider = Provider<AuthApiClient>((ref) {
  return AuthApiClient.bind(ref.watch(_apiChopperClientProvider));
});

/// Chopper-сервис медиа на общем [ChopperClient].
final mediaApiClientProvider = Provider<MediaApiClient>((ref) {
  return MediaApiClient.bind(ref.watch(_apiChopperClientProvider));
});

/// Chopper-сервис библиотеки (избранное, артисты, коллекции)
/// на общем [ChopperClient].
final libraryApiClientProvider = Provider<LibraryApiClient>((ref) {
  return LibraryApiClient.bind(ref.watch(_apiChopperClientProvider));
});
