import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/shared/models/user.dart';

/// Remote data source for authentication API calls.
class AuthRemoteDataSource {
  /// Creates an [AuthRemoteDataSource] with the given [apiClient].
  AuthRemoteDataSource(this.apiClient);

  /// The API client used for HTTP requests.
  final ApiClient apiClient;

  /// Requests a verification code to be sent to [email].
  Future<void> requestCode(String email) async {
    final Response<Map<String, dynamic>> response =
        await apiClient.requestCode({'email': email});
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] as String? ?? 'Failed to send code',
      );
    }
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
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] as String? ?? 'Failed to verify code',
      );
    }
    final body = response.body!;
    return (
      token: body['token'] as String,
      user: User.fromJson(body['user'] as Map<String, dynamic>),
    );
  }

  /// Gets the currently authenticated user.
  Future<User> getCurrentUser() async {
    final Response<Map<String, dynamic>> response = await apiClient.getMe();
    if (response.statusCode != 200) {
      throw ServerException(
        message: response.body?['error'] as String? ?? 'Failed to get user',
      );
    }
    return User.fromJson(response.body!);
  }
}
