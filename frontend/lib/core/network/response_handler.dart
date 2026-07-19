import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';

/// Checks the HTTP response status and throws appropriate exceptions.
///
/// - 401 → [AuthException] (session expired)
/// - 200, 201 → success (no-op)
/// - anything else → [ServerException] with error message from body
void checkResponse(Response<dynamic> response, String defaultMessage) {
  if (response.statusCode == 401) {
    throw const AuthException(message: 'Session expired');
  }
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw ServerException(
      message: response.body is Map<String, dynamic>
          ? (response.body as Map<String, dynamic>)['error'] as String? ??
              defaultMessage
          : defaultMessage,
    );
  }
}
