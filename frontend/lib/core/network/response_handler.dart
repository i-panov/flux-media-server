import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flux_media_server/core/error/exceptions.dart';
import 'package:flux_media_server/core/error/failures.dart';
import 'package:flux_media_server/core/network/interceptors/token_refresh_interceptor.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;

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
    final body = response.body;
    String? errorMessage;
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      errorMessage = error is String ? error : null;
    }
    throw ServerException(
      message: errorMessage ?? defaultMessage,
    );
  }
}

/// Преобразует исключение в соответствующий [Failure].
///
/// Сетевые ошибки ([http.ClientException], [SocketException],
/// [TimeoutException]) становятся [NetworkFailure], а не
/// [ServerFailure] с сырым текстом.
Failure _failureFor(Object e) {
  if (e is AuthException) return AuthFailure(message: e.message);
  if (e is ServerException) return ServerFailure(message: e.message);
  if (e is NetworkException) return NetworkFailure(message: e.message);
  if (e is http.ClientException) return NetworkFailure(message: e.message);
  if (e is SocketException) return NetworkFailure(message: e.message);
  if (e is TimeoutException) {
    return NetworkFailure(message: e.message ?? 'Request timed out');
  }
  return ServerFailure(message: e.toString());
}

/// Wraps a repository call with token-refresh retry logic.
/// Retries once on [TokenRefreshedException], converts exceptions to [Failure].
Future<Either<Failure, T>> safeRepositoryCall<T>(
  Future<T> Function() call,
) async {
  try {
    return Right(await call());
  } on TokenRefreshedException {
    // Token was just refreshed — retry with the new token.
    try {
      return Right(await call());
    } on Exception catch (e) {
      return Left(_failureFor(e));
    }
  } on Exception catch (e) {
    return Left(_failureFor(e));
  }
}
