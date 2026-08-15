import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/auth_api_client.dart';
import 'package:flux_media_server/core/network/auth_token_refresher.dart';
import 'package:flux_media_server/core/network/response_handler.dart';
import 'package:flux_media_server/shared/models/user.dart';

/// Remote data source for authentication API calls.
class AuthRemoteDataSource {
  /// Creates an [AuthRemoteDataSource] with the given [apiClient]
  /// and [refresher].
  AuthRemoteDataSource(this.apiClient, {required this.refresher});

  /// The API client used for HTTP requests.
  final AuthApiClient apiClient;

  /// Единый refresher токенов (общий с интерцептором и offline-кэшем).
  final AuthTokenRefresher refresher;

  /// Requests a verification code to be sent to [email].
  /// Returns the debug code if server is in debug mode, null otherwise.
  Future<String?> requestCode(String email) async {
    final response = await apiClient.requestCode({'email': email});
    checkResponse(response, 'Failed to send code');
    return response.body?['code'] as String?;
  }

  /// Verifies the code sent to [email] and returns the auth token,
  /// refresh token, and user.
  Future<({String token, String refreshToken, User user})> verifyCode(
    String email,
    String code,
  ) async {
    final response = await apiClient.verifyCode({
      'email': email,
      'code': code,
    });
    checkResponse(response, 'Failed to verify code');
    final body = response.body!;
    return (
      token: body['token'] as String,
      refreshToken: body['refresh_token'] as String,
      user: User.fromJson(body['user'] as Map<String, dynamic>),
    );
  }

  /// Refreshes the access token using a refresh token.
  ///
  /// Использует единый [AuthTokenRefresher], чтобы параллельные вызовы
  /// ждали один общий refresh. Токены возвращаются напрямую (не через
  /// побочное поле refresher), чтобы провал чужого параллельного
  /// refresh не обнулял результат успешного.
  Future<({String token, String refreshToken})> refreshTokens(
    String refreshToken,
  ) async {
    final tokens = await refresher.refreshTokens(refreshToken);
    if (tokens == null) {
      throw const ServerException(message: 'Failed to refresh token');
    }
    return tokens;
  }

  /// Gets the currently authenticated user.
  Future<User> getCurrentUser() async {
    final response = await apiClient.getMe();
    checkResponse(response, 'Failed to get user');
    return User.fromJson(response.body!);
  }
}
