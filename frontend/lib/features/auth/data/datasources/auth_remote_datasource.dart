import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/shared/models/user.dart';

void _checkStatus(Response<dynamic> response, String defaultMessage) {
  if (response.statusCode == 401) {
    throw const AuthException(message: 'Session expired');
  }
  if (response.statusCode != 200) {
    throw ServerException(
      message: response.body?['error'] as String? ?? defaultMessage,
    );
  }
}

/// Remote data source for authentication API calls.
class AuthRemoteDataSource {
  /// Creates an [AuthRemoteDataSource] with the given [apiClient].
  AuthRemoteDataSource(this.apiClient);

  /// The API client used for HTTP requests.
  final ApiClient apiClient;

  /// Requests a verification code to be sent to [email].
  /// Returns the debug code if server is in debug mode, null otherwise.
  Future<String?> requestCode(String email) async {
    final Response<Map<String, dynamic>> response =
        await apiClient.requestCode({'email': email});
    _checkStatus(response, 'Failed to send code');
    return response.body?['code'] as String?;
  }

  /// Verifies the code sent to [email] and returns the auth token and user.
  Future<({String token, User user})> verifyCode(
    String email,
    String code,
  ) async {
    final Response<Map<String, dynamic>> response = await apiClient.verifyCode({
      'email': email,
      'code': code,
    });
    _checkStatus(response, 'Failed to verify code');
    final body = response.body!;
    return (
      token: body['token'] as String,
      user: User.fromJson(body['user'] as Map<String, dynamic>),
    );
  }

  /// Gets the currently authenticated user.
  Future<User> getCurrentUser() async {
    final Response<Map<String, dynamic>> response = await apiClient.getMe();
    _checkStatus(response, 'Failed to get user');
    return User.fromJson(response.body!);
  }
}
