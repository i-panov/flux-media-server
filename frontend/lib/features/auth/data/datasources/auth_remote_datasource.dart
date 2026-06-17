import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/network/api_client.dart';
import 'package:flux_media_server/shared/models/user.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<void> requestCode(String email) async {
    final response = await apiClient.requestCode({'email': email});
    if (response.statusCode != 200) {
      throw ServerException(message: response.body?['error'] ?? 'Failed to send code');
    }
  }

  Future<({String token, User user})> verifyCode(String email, String code) async {
    final response = await apiClient.verifyCode({
      'email': email,
      'code': code,
    });
    if (response.statusCode != 200) {
      throw ServerException(message: response.body?['error'] ?? 'Failed to verify code');
    }
    final body = response.body!;
    return (
      token: body['token'] as String,
      user: User.fromJson(body['user'] as Map<String, dynamic>),
    );
  }

  Future<User> getCurrentUser() async {
    final response = await apiClient.getMe();
    if (response.statusCode != 200) {
      throw ServerException(message: response.body?['error'] ?? 'Failed to get user');
    }
    return User.fromJson(response.body! as Map<String, dynamic>);
  }
}
