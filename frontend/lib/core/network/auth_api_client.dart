import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/network/api_service_factory.dart';
import 'package:flux_media_server/core/network/interceptors/auth_interceptor.dart';
import 'package:flux_media_server/core/network/interceptors/safe_logging_interceptor.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';

part 'auth_api_client.chopper.dart';

/// Результат создания [AuthApiClient]: сервис и низкоуровневый
/// HTTP-клиент, который нужно закрыть через `ref.onDispose`.
typedef AuthApiClientBundle = ({
  AuthApiClient apiClient,
  TimeoutHttpClient httpClient,
});

/// Chopper-сервис аутентификации.
///
/// Пути объявлены относительно baseUrl, который уже включает `/api`.
@ChopperApi()
abstract class AuthApiClient extends ChopperService {
  /// Создаёт сервис вместе с его HTTP-клиентом.
  static AuthApiClientBundle create({
    String? baseUrl,
    AuthInterceptor? authInterceptor,
    TokenRefreshInterceptor? tokenRefreshInterceptor,
  }) {
    final created = createChopperClient(
      baseUrl: baseUrl ?? 'http://localhost:8080/api',
      services: [_$AuthApiClient()],
      interceptors: [
        if (authInterceptor != null) authInterceptor,
        if (tokenRefreshInterceptor != null) tokenRefreshInterceptor,
        SafeLoggingInterceptor(),
      ],
    );
    return (
      apiClient: _$AuthApiClient(created.client),
      httpClient: created.httpClient,
    );
  }

  /// Привязывает сервис к существующему [ChopperClient] (общему для всех
  /// сервисов приложения). В отличие от [create], не создаёт собственный
  /// HTTP-клиент.
  static AuthApiClient bind(ChopperClient client) => _$AuthApiClient(client);

  @Post(path: '/auth/request-code')
  Future<Response<Map<String, dynamic>>> requestCode(
    @Body() Map<String, dynamic> body,
  );

  @Post(path: '/auth/verify-code')
  Future<Response<Map<String, dynamic>>> verifyCode(
    @Body() Map<String, dynamic> body,
  );

  @Post(path: '/auth/refresh')
  Future<Response<Map<String, dynamic>>> refreshToken(
    @Body() Map<String, dynamic> body,
  );

  @Get(path: '/auth/me')
  Future<Response<Map<String, dynamic>>> getMe();
}
