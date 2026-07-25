import 'dart:async';
import 'dart:io';

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

/// Wraps an async operation, converting low-level exceptions into
/// domain-level [AuthException], [NetworkException], or [ServerException].
Future<T> safeApiCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on AuthException {
    rethrow;
  } on ServerException {
    rethrow;
  } on NetworkException {
    rethrow;
  } on SocketException {
    throw const NetworkException(message: 'No internet connection');
  } on HttpException {
    throw const NetworkException(message: 'Network error');
  } on TimeoutException {
    throw const NetworkException(message: 'Request timed out');
  } on IOException {
    throw const NetworkException(message: 'Network error');
  } on Exception catch (e) {
    throw ServerException(message: e.toString());
  }
}
